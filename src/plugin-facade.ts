/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import type {
  NativeNavigationConfigureOptions,
  NativeNavigationIcon,
  NativeNavigationNavbarOptions,
  NativeNavigationPlugin,
  NativeNavigationTabbarOptions,
} from "./definitions";

const MAX_SVG_INPUT_BYTES = 256 * 1024;
const MAX_BASE64_PAYLOAD_CHARACTERS = Math.ceil(MAX_SVG_INPUT_BYTES / 3) * 4 + 4;
const MAX_PERCENT_ENCODED_PAYLOAD_CHARACTERS = MAX_SVG_INPUT_BYTES * 3;
const SVG_DATA_PREFIX = "data:image/svg+xml";
const textEncoder = new TextEncoder();

type JsonRecord = Record<string, unknown>;

const isJsonRecord = (value: unknown): value is JsonRecord =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** Removes runtime null/undefined values so patch semantics stay identical on every platform. */
export const normalizeNativeNavigationPatch = <T>(value: T): T => {
  if (Array.isArray(value)) {
    return value
      .filter((entry) => entry !== null && entry !== undefined)
      .map((entry) => normalizeNativeNavigationPatch(entry)) as unknown as T;
  }
  if (!isJsonRecord(value)) return value;

  const normalizedEntries = Object.entries(value)
    .filter(([, entry]) => entry !== null && entry !== undefined)
    .map(([key, entry]) => [key, normalizeNativeNavigationPatch(entry)] as const);
  return Object.fromEntries(normalizedEntries) as T;
};

const assertSvgByteLength = (value: string, path: string): void => {
  if (textEncoder.encode(value).byteLength > MAX_SVG_INPUT_BYTES) {
    throw new RangeError(`${path} exceeds the ${MAX_SVG_INPUT_BYTES}-byte SVG limit`);
  }
};

const assertBase64SvgPayload = (payload: string, path: string): void => {
  if (payload.length > MAX_BASE64_PAYLOAD_CHARACTERS) {
    throw new RangeError(`${path} exceeds the encoded SVG limit`);
  }

  const compact = payload.replace(/\s/g, "");
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(compact) || compact.length % 4 === 1) {
    throw new TypeError(`${path} contains malformed base64 SVG data`);
  }
  const padding = compact.endsWith("==") ? 2 : compact.endsWith("=") ? 1 : 0;
  const decodedBytes = Math.floor((compact.length * 3) / 4) - padding;
  if (decodedBytes > MAX_SVG_INPUT_BYTES) {
    throw new RangeError(`${path} exceeds the ${MAX_SVG_INPUT_BYTES}-byte SVG limit`);
  }
};

const assertPercentEncodedSvgPayload = (payload: string, path: string): void => {
  if (payload.length > MAX_PERCENT_ENCODED_PAYLOAD_CHARACTERS) {
    throw new RangeError(`${path} exceeds the encoded SVG limit`);
  }
  let decoded: string;
  try {
    decoded = decodeURIComponent(payload);
  } catch {
    throw new TypeError(`${path} contains malformed percent-encoded SVG data`);
  }
  assertSvgByteLength(decoded, path);
};

const assertSvgSource = (value: string, path: string): void => {
  const trimmed = value.trim();
  if (trimmed.startsWith("<svg")) {
    assertSvgByteLength(trimmed, path);
    return;
  }

  const commaIndex = trimmed.indexOf(",");
  if (commaIndex < 0) return;
  const metadata = trimmed.slice(0, commaIndex).toLowerCase();
  if (!metadata.startsWith(SVG_DATA_PREFIX)) return;

  const payload = trimmed.slice(commaIndex + 1);
  if (metadata.includes(";base64")) {
    assertBase64SvgPayload(payload, path);
  } else {
    assertPercentEncodedSvgPayload(payload, path);
  }
};

const assertIconPayload = (icon: NativeNavigationIcon | undefined, path: string): void => {
  if (!icon) return;
  if (icon.svg !== undefined) assertSvgByteLength(icon.svg, `${path}.svg`);
  if (icon.ios?.svg !== undefined) assertSvgByteLength(icon.ios.svg, `${path}.ios.svg`);
  if (icon.android?.svg !== undefined) {
    assertSvgByteLength(icon.android.svg, `${path}.android.svg`);
  }
  if (icon.src !== undefined) assertSvgSource(icon.src, `${path}.src`);
  if (icon.android?.resource !== undefined) {
    assertSvgSource(icon.android.resource, `${path}.android.resource`);
  }
  if (icon.android?.image !== undefined) {
    assertSvgSource(icon.android.image, `${path}.android.image`);
  }
};

/** Rejects oversized navbar SVGs before native code allocates decoded buffers. */
export const assertSafeNavbarIcons = (options: NativeNavigationNavbarOptions): void => {
  options.leftItems?.forEach((item, index) => {
    assertIconPayload(item.icon, `leftItems[${index}].icon`);
  });
  options.rightItems?.forEach((item, index) => {
    assertIconPayload(item.icon, `rightItems[${index}].icon`);
  });
};

/** Rejects oversized tabbar SVGs before native code allocates decoded buffers. */
export const assertSafeTabbarIcons = (options: NativeNavigationTabbarOptions): void => {
  options.tabs?.forEach((tab, index) => {
    assertIconPayload(tab.icon, `tabs[${index}].icon`);
    assertIconPayload(tab.selectedIcon, `tabs[${index}].selectedIcon`);
  });
};

/**
 * Wraps the Capacitor bridge with cross-platform patch normalization and
 * tab-selection state repair.
 * The raw native implementations remain the source of rendering behavior.
 */
export const createNativeNavigationFacade = (
  bridge: NativeNavigationPlugin,
): NativeNavigationPlugin => {
  let hasTabbarState = false;
  let selectedTabId: string | undefined;
  let selectedStateDirty = false;
  let selectionGeneration = 0;
  let observerRegistration: Promise<void> | undefined;

  const rememberNativeSelection = (id: string): void => {
    selectedTabId = id;
    selectedStateDirty = hasTabbarState;
    selectionGeneration += 1;
  };

  const ensureTabSelectionObserver = (): Promise<void> => {
    observerRegistration ??= bridge
      .addListener("tabSelect", (event) => rememberNativeSelection(event.id))
      .then(() => undefined);
    return observerRegistration;
  };

  const synchronizeSelectedState = async (): Promise<void> => {
    await ensureTabSelectionObserver();
    if (!hasTabbarState || !selectedStateDirty || selectedTabId === undefined) return;

    const generation = selectionGeneration;
    const selectedId = selectedTabId;
    selectedStateDirty = false;
    try {
      await bridge.setTabbar({ selectedId });
    } catch (error) {
      selectedStateDirty = true;
      throw error;
    }
    if (selectionGeneration !== generation) selectedStateDirty = true;
  };

  const configure = async (
    options: NativeNavigationConfigureOptions = {},
  ): Promise<Awaited<ReturnType<NativeNavigationPlugin["configure"]>>> => {
    const normalized = normalizeNativeNavigationPatch(options);
    if (hasTabbarState) await synchronizeSelectedState();
    return bridge.configure(normalized);
  };

  const setNavbar = async (
    options: NativeNavigationNavbarOptions,
  ): Promise<Awaited<ReturnType<NativeNavigationPlugin["setNavbar"]>>> => {
    const normalized = normalizeNativeNavigationPatch(options);
    assertSafeNavbarIcons(normalized);
    return bridge.setNavbar(normalized);
  };

  const setTabbar = async (
    options: NativeNavigationTabbarOptions,
  ): Promise<Awaited<ReturnType<NativeNavigationPlugin["setTabbar"]>>> => {
    const normalized = normalizeNativeNavigationPatch(options);
    assertSafeTabbarIcons(normalized);
    await ensureTabSelectionObserver();

    const hasExplicitSelectedId = Object.prototype.hasOwnProperty.call(normalized, "selectedId");
    const generation = selectionGeneration;
    if (hasExplicitSelectedId) selectedTabId = normalized.selectedId;
    const effectiveOptions =
      !hasExplicitSelectedId && selectedTabId !== undefined
        ? { ...normalized, selectedId: selectedTabId }
        : normalized;

    const result = await bridge.setTabbar(effectiveOptions);
    hasTabbarState = true;
    if (selectionGeneration === generation) selectedStateDirty = false;
    return result;
  };

  const overrides = new Map<PropertyKey, unknown>();
  overrides.set("configure", configure);
  overrides.set("setNavbar", setNavbar);
  overrides.set("setTabbar", setTabbar);

  return new Proxy(bridge, {
    get(target, property) {
      if (overrides.has(property)) return overrides.get(property);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
};
