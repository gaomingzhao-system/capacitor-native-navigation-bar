from pathlib import Path
import re
import textwrap

ROOT = Path(__file__).resolve().parents[1]


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(textwrap.dedent(content).lstrip(), encoding="utf-8")


def replace_regex(path: str, pattern: str, replacement: str, count: int = 1) -> None:
    target = ROOT / path
    source = target.read_text(encoding="utf-8")
    updated, matches = re.subn(pattern, textwrap.dedent(replacement).strip("\n"), source, count=count, flags=re.S)
    if matches != count:
        raise RuntimeError(f"{path}: expected {count} matches for {pattern!r}, got {matches}")
    target.write_text(updated, encoding="utf-8")


def insert_before_final(path: str, content: str) -> None:
    target = ROOT / path
    source = target.read_text(encoding="utf-8")
    marker = "\n})\n"
    index = source.rfind(marker)
    if index < 0:
        raise RuntimeError(f"{path}: final describe marker not found")
    updated = source[:index] + "\n" + textwrap.dedent(content).strip("\n") + source[index:]
    target.write_text(updated, encoding="utf-8")


write(
    "src/patch.ts",
    r'''
    type JsonRecord = Record<string, unknown>

    const isJsonRecord = (value: unknown): value is JsonRecord =>
      typeof value === "object" && value !== null && !Array.isArray(value)

    const normalizePatchValue = (value: unknown, preserveNull: boolean): unknown => {
      if (Array.isArray(value)) {
        return value
          .filter((entry) => entry !== null && entry !== undefined)
          .map((entry) => normalizePatchValue(entry, false))
      }
      if (!isJsonRecord(value)) return value

      const normalizedEntries = Object.entries(value)
        .filter(([, entry]) => entry !== undefined && (preserveNull || entry !== null))
        .map(([key, entry]) => [key, normalizePatchValue(entry, preserveNull)] as const)
      return Object.fromEntries(normalizedEntries)
    }

    /**
     * Removes `undefined` values while retaining object-level `null` as an
     * explicit reset marker. Null fields inside array entries are removed,
     * because arrays such as `tabs` replace complete native models rather than
     * acting as nested patches.
     */
    export const normalizeNativeNavigationPatch = <T>(value: T): T =>
      normalizePatchValue(value, true) as T

    /** Applies native-compatible patch semantics, including null deletion. */
    export const mergeNativeNavigationPatch = <T extends JsonRecord>(
      current: T,
      patch: JsonRecord,
      nestedKeys: ReadonlySet<string> = new Set(),
    ): T => {
      const result: JsonRecord = { ...current }
      for (const [key, value] of Object.entries(patch)) {
        if (value === undefined) continue
        if (value === null) {
          delete result[key]
          continue
        }
        if (nestedKeys.has(key) && isJsonRecord(value)) {
          const previous = isJsonRecord(result[key]) ? result[key] : {}
          result[key] = mergeNativeNavigationPatch(previous, value)
          continue
        }
        result[key] = value
      }
      return result as T
    }
    ''',
)

write(
    "src/validation.ts",
    r'''
    import type {
      NativeNavigationBeginTransitionOptions,
      NativeNavigationConfigureOptions,
      NativeNavigationFinishTransitionOptions,
      NativeNavigationGlassOptions,
      NativeNavigationIcon,
      NativeNavigationNavbarOptions,
      NativeNavigationRect,
      NativeNavigationTabbarOptions,
      NativeNavigationTabbarStyle,
    } from "./definitions"

    export const NATIVE_NAVIGATION_MAX_DURATION_MS = 60_000
    export const NATIVE_NAVIGATION_MAX_LAYOUT_DIMENSION = 2_048
    export const NATIVE_NAVIGATION_MAX_ICON_DIMENSION = 256
    export const NATIVE_NAVIGATION_MAX_TRANSITION_COORDINATE = 1_000_000
    export const NATIVE_NAVIGATION_MAX_TRANSITION_DIMENSION = 4_096
    const MAX_TABS = 64
    const MAX_NAVBAR_ITEMS = 32

    type JsonRecord = Record<string, unknown>

    const isRecord = (value: unknown): value is JsonRecord =>
      typeof value === "object" && value !== null && !Array.isArray(value)

    const assertFiniteRange = (
      value: unknown,
      path: string,
      minimum: number,
      maximum: number,
      allowNull = true,
    ): void => {
      if (value === undefined || (allowNull && value === null)) return
      if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
        throw new RangeError(`${path} must be a finite value between ${minimum} and ${maximum}`)
      }
    }

    const assertEnum = (
      value: unknown,
      path: string,
      allowed: readonly string[],
    ): void => {
      if (value === undefined || value === null) return
      if (typeof value !== "string" || !allowed.includes(value)) {
        throw new TypeError(`${path} must be one of: ${allowed.join(", ")}`)
      }
    }

    const assertArray = (value: unknown, path: string, maximum: number): unknown[] | undefined => {
      if (value === undefined || value === null) return undefined
      if (!Array.isArray(value)) throw new TypeError(`${path} must be an array`)
      if (value.length > maximum) throw new RangeError(`${path} must contain at most ${maximum} entries`)
      return value
    }

    const validateGlass = (value: unknown, path: string): void => {
      if (value === undefined || value === null) return
      if (!isRecord(value)) throw new TypeError(`${path} must be an object`)
      assertEnum(value.effect, `${path}.effect`, ["none", "liquidGlass"])
      assertFiniteRange(value.blurRadius, `${path}.blurRadius`, 0, NATIVE_NAVIGATION_MAX_LAYOUT_DIMENSION)
      assertFiniteRange(value.surfaceAlpha, `${path}.surfaceAlpha`, 0, 1)
    }

    const validateIcon = (value: unknown, path: string): void => {
      if (value === undefined || value === null) return
      if (!isRecord(value)) throw new TypeError(`${path} must be an object`)
      assertFiniteRange(value.width, `${path}.width`, 1, NATIVE_NAVIGATION_MAX_ICON_DIMENSION)
      assertFiniteRange(value.height, `${path}.height`, 1, NATIVE_NAVIGATION_MAX_ICON_DIMENSION)
    }

    const validateStyle = (value: unknown, path: string): void => {
      if (value === undefined || value === null) return
      if (!isRecord(value)) throw new TypeError(`${path} must be an object`)
      assertEnum(value.shape, `${path}.shape`, ["floating", "curve"])
      for (const key of [
        "height",
        "horizontalMargin",
        "maxWidth",
        "bottomGap",
        "cornerRadius",
        "centerButtonDiameter",
        "centerButtonLift",
      ]) {
        assertFiniteRange(value[key], `${path}.${key}`, 0, NATIVE_NAVIGATION_MAX_LAYOUT_DIMENSION)
      }
    }

    const validateRect = (value: unknown, path: string): void => {
      if (value === undefined || value === null) return
      if (!isRecord(value)) throw new TypeError(`${path} must be an object`)
      assertFiniteRange(
        value.x,
        `${path}.x`,
        -NATIVE_NAVIGATION_MAX_TRANSITION_COORDINATE,
        NATIVE_NAVIGATION_MAX_TRANSITION_COORDINATE,
        false,
      )
      assertFiniteRange(
        value.y,
        `${path}.y`,
        -NATIVE_NAVIGATION_MAX_TRANSITION_COORDINATE,
        NATIVE_NAVIGATION_MAX_TRANSITION_COORDINATE,
        false,
      )
      assertFiniteRange(value.width, `${path}.width`, Number.EPSILON, NATIVE_NAVIGATION_MAX_TRANSITION_DIMENSION, false)
      assertFiniteRange(value.height, `${path}.height`, Number.EPSILON, NATIVE_NAVIGATION_MAX_TRANSITION_DIMENSION, false)
    }

    export const validateNativeNavigationConfigureOptions = (
      options: NativeNavigationConfigureOptions,
    ): void => {
      const runtime = options as unknown as JsonRecord
      assertEnum(runtime.platformStyle, "platformStyle", ["auto", "ios", "android"])
      assertEnum(runtime.contentInsetMode, "contentInsetMode", ["css", "none"])
      assertFiniteRange(runtime.animationDuration, "animationDuration", 0, NATIVE_NAVIGATION_MAX_DURATION_MS)
      validateGlass(runtime.glass, "glass")
    }

    export const validateNativeNavigationNavbarOptions = (
      options: NativeNavigationNavbarOptions,
    ): void => {
      const runtime = options as unknown as JsonRecord
      assertEnum(runtime.blurEffect, "blurEffect", [
        "none",
        "systemDefault",
        "extraLight",
        "light",
        "dark",
        "regular",
        "prominent",
        "systemUltraThinMaterial",
        "systemThinMaterial",
        "systemMaterial",
        "systemThickMaterial",
        "systemChromeMaterial",
        "systemUltraThinMaterialLight",
        "systemThinMaterialLight",
        "systemMaterialLight",
        "systemThickMaterialLight",
        "systemChromeMaterialLight",
        "systemUltraThinMaterialDark",
        "systemThinMaterialDark",
        "systemMaterialDark",
        "systemThickMaterialDark",
        "systemChromeMaterialDark",
      ])
      validateGlass(runtime.glass, "glass")
      for (const [key, maximum] of [
        ["leftItems", MAX_NAVBAR_ITEMS],
        ["rightItems", MAX_NAVBAR_ITEMS],
      ] as const) {
        const items = assertArray(runtime[key], key, maximum)
        items?.forEach((item, index) => {
          if (!isRecord(item)) throw new TypeError(`${key}[${index}] must be an object`)
          if (typeof item.id !== "string" || item.id.length === 0) {
            throw new TypeError(`${key}[${index}].id must be a non-empty string`)
          }
          validateIcon(item.icon, `${key}[${index}].icon`)
        })
      }
    }

    export const validateNativeNavigationTabbarOptions = (
      options: NativeNavigationTabbarOptions,
    ): void => {
      const runtime = options as unknown as JsonRecord
      assertEnum(runtime.labelVisibilityMode, "labelVisibilityMode", ["auto", "selected", "labeled", "unlabeled"])
      assertEnum(runtime.blurEffect, "blurEffect", [
        "none",
        "systemDefault",
        "extraLight",
        "light",
        "dark",
        "regular",
        "prominent",
        "systemUltraThinMaterial",
        "systemThinMaterial",
        "systemMaterial",
        "systemThickMaterial",
        "systemChromeMaterial",
        "systemUltraThinMaterialLight",
        "systemThinMaterialLight",
        "systemMaterialLight",
        "systemThickMaterialLight",
        "systemChromeMaterialLight",
        "systemUltraThinMaterialDark",
        "systemThinMaterialDark",
        "systemMaterialDark",
        "systemThickMaterialDark",
        "systemChromeMaterialDark",
      ])
      validateGlass(runtime.glass, "glass")
      validateStyle(runtime.style, "style")

      const tabs = assertArray(runtime.tabs, "tabs", MAX_TABS)
      const ids = new Set<string>()
      tabs?.forEach((tab, index) => {
        if (!isRecord(tab)) throw new TypeError(`tabs[${index}] must be an object`)
        if (typeof tab.id !== "string" || tab.id.length === 0) {
          throw new TypeError(`tabs[${index}].id must be a non-empty string`)
        }
        if (ids.has(tab.id)) throw new TypeError(`tabs contains duplicate id ${JSON.stringify(tab.id)}`)
        ids.add(tab.id)
        assertEnum(tab.role, `tabs[${index}].role`, ["normal", "search", "prominent"])
        validateIcon(tab.icon, `tabs[${index}].icon`)
        validateIcon(tab.selectedIcon, `tabs[${index}].selectedIcon`)
      })
    }

    export const validateNativeNavigationTransitionOptions = (
      options: NativeNavigationBeginTransitionOptions | NativeNavigationFinishTransitionOptions,
    ): void => {
      const runtime = options as unknown as JsonRecord
      assertEnum(runtime.direction, "direction", ["forward", "back", "root", "tab", "zoom", "none"])
      assertFiniteRange(runtime.duration, "duration", 0, NATIVE_NAVIGATION_MAX_DURATION_MS)
      assertFiniteRange(runtime.cornerRadius, "cornerRadius", 0, NATIVE_NAVIGATION_MAX_LAYOUT_DIMENSION)
      validateRect(runtime.sourceRect, "sourceRect")
      validateRect(runtime.targetRect, "targetRect")
    }
    ''',
)

write(
    "src/plugin-facade.ts",
    r'''
    /* This Source Code Form is subject to the terms of the Mozilla Public
     * License, v. 2.0. If a copy of the MPL was not distributed with this
     * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

    import type {
      NativeNavigationBeginTransitionOptions,
      NativeNavigationConfigureOptions,
      NativeNavigationFinishTransitionOptions,
      NativeNavigationIcon,
      NativeNavigationNavbarOptions,
      NativeNavigationPlugin,
      NativeNavigationTabbarOptions,
    } from "./definitions"
    import { normalizeNativeNavigationPatch } from "./patch"
    import {
      validateNativeNavigationConfigureOptions,
      validateNativeNavigationNavbarOptions,
      validateNativeNavigationTabbarOptions,
      validateNativeNavigationTransitionOptions,
    } from "./validation"

    export { normalizeNativeNavigationPatch } from "./patch"

    const MAX_SVG_INPUT_BYTES = 256 * 1024
    const MAX_BASE64_PAYLOAD_CHARACTERS = Math.ceil(MAX_SVG_INPUT_BYTES / 3) * 4 + 4
    const MAX_PERCENT_ENCODED_PAYLOAD_CHARACTERS = MAX_SVG_INPUT_BYTES * 3
    const SVG_DATA_PREFIX = "data:image/svg+xml"
    const textEncoder = new TextEncoder()

    type NativeNavigationTabs = NonNullable<NativeNavigationTabbarOptions["tabs"]>
    type NativeNavigationTabbarStyle = NonNullable<NativeNavigationTabbarOptions["style"]>
    type RuntimeTabbarPatch = NativeNavigationTabbarOptions & {
      selectedId?: string | null
      tabs?: NativeNavigationTabs | null
      style?: NativeNavigationTabbarStyle | null
    }

    const normalizeDetachedTabRoles = (
      tabs: NativeNavigationTabs,
      selectedId: string | undefined,
      shape: NativeNavigationTabbarStyle["shape"],
    ): NativeNavigationTabs => {
      if (shape === "curve") return tabs

      let detachedIndex = -1
      for (let index = tabs.length - 1; index >= 0; index -= 1) {
        const tab = tabs[index]
        if (!tab || (tab.hidden === true && tab.id !== selectedId)) continue
        if (tab.role === "search" || tab.role === "prominent") {
          detachedIndex = index
          break
        }
      }
      if (detachedIndex < 0) return tabs

      let changed = false
      const normalizedTabs = tabs.slice()
      for (let index = 0; index < tabs.length; index += 1) {
        if (index === detachedIndex) continue
        const tab = tabs[index]
        if (!tab || (tab.hidden === true && tab.id !== selectedId)) continue
        if (tab.role !== "search" && tab.role !== "prominent") continue
        normalizedTabs[index] = { ...tab, role: "normal" }
        changed = true
      }
      return changed ? normalizedTabs : tabs
    }

    const assertSvgByteLength = (value: string, path: string): void => {
      if (textEncoder.encode(value).byteLength > MAX_SVG_INPUT_BYTES) {
        throw new RangeError(`${path} exceeds the ${MAX_SVG_INPUT_BYTES}-byte SVG limit`)
      }
    }

    const assertBase64SvgPayload = (payload: string, path: string): void => {
      if (payload.length > MAX_BASE64_PAYLOAD_CHARACTERS) {
        throw new RangeError(`${path} exceeds the encoded SVG limit`)
      }

      const compact = payload.replace(/\s/g, "")
      if (!/^[A-Za-z0-9+/]*={0,2}$/.test(compact) || compact.length % 4 === 1) {
        throw new TypeError(`${path} contains malformed base64 SVG data`)
      }
      const padding = compact.endsWith("==") ? 2 : compact.endsWith("=") ? 1 : 0
      const decodedBytes = Math.floor((compact.length * 3) / 4) - padding
      if (decodedBytes > MAX_SVG_INPUT_BYTES) {
        throw new RangeError(`${path} exceeds the ${MAX_SVG_INPUT_BYTES}-byte SVG limit`)
      }
    }

    const assertPercentEncodedSvgPayload = (payload: string, path: string): void => {
      if (payload.length > MAX_PERCENT_ENCODED_PAYLOAD_CHARACTERS) {
        throw new RangeError(`${path} exceeds the encoded SVG limit`)
      }
      let decoded: string
      try {
        decoded = decodeURIComponent(payload)
      } catch {
        throw new TypeError(`${path} contains malformed percent-encoded SVG data`)
      }
      assertSvgByteLength(decoded, path)
    }

    const assertSvgSource = (value: string, path: string): void => {
      const trimmed = value.trim()
      if (trimmed.startsWith("<svg")) {
        assertSvgByteLength(trimmed, path)
        return
      }

      const commaIndex = trimmed.indexOf(",")
      if (commaIndex < 0) return
      const metadata = trimmed.slice(0, commaIndex).toLowerCase()
      if (!metadata.startsWith(SVG_DATA_PREFIX)) return

      const payload = trimmed.slice(commaIndex + 1)
      if (metadata.includes(";base64")) {
        assertBase64SvgPayload(payload, path)
      } else {
        assertPercentEncodedSvgPayload(payload, path)
      }
    }

    const assertIconPayload = (icon: NativeNavigationIcon | undefined, path: string): void => {
      if (!icon) return
      if (icon.svg !== undefined) assertSvgByteLength(icon.svg, `${path}.svg`)
      if (icon.ios?.svg !== undefined) assertSvgByteLength(icon.ios.svg, `${path}.ios.svg`)
      if (icon.android?.svg !== undefined) assertSvgByteLength(icon.android.svg, `${path}.android.svg`)
      if (icon.src !== undefined) assertSvgSource(icon.src, `${path}.src`)
      if (icon.android?.resource !== undefined) assertSvgSource(icon.android.resource, `${path}.android.resource`)
      if (icon.android?.image !== undefined) assertSvgSource(icon.android.image, `${path}.android.image`)
    }

    export const assertSafeNavbarIcons = (options: NativeNavigationNavbarOptions): void => {
      options.leftItems?.forEach((item, index) => assertIconPayload(item.icon, `leftItems[${index}].icon`))
      options.rightItems?.forEach((item, index) => assertIconPayload(item.icon, `rightItems[${index}].icon`))
    }

    export const assertSafeTabbarIcons = (options: NativeNavigationTabbarOptions): void => {
      options.tabs?.forEach((tab, index) => {
        assertIconPayload(tab.icon, `tabs[${index}].icon`)
        assertIconPayload(tab.selectedIcon, `tabs[${index}].selectedIcon`)
      })
    }

    export const createNativeNavigationFacade = (
      bridge: NativeNavigationPlugin,
    ): NativeNavigationPlugin => {
      let hasTabbarState = false
      let selectedTabId: string | undefined
      let selectedStateDirty = false
      let selectionGeneration = 0
      let observerRegistration: Promise<void> | undefined
      let tabDefinitions: NativeNavigationTabs | undefined
      let tabbarStyle: NativeNavigationTabbarStyle = {}
      let tabbarOperationTail: Promise<void> = Promise.resolve()

      const enqueueTabbarOperation = <T>(operation: () => Promise<T>): Promise<T> => {
        const result = tabbarOperationTail.then(operation, operation)
        tabbarOperationTail = result.then(
          () => undefined,
          () => undefined,
        )
        return result
      }

      const normalizedTabDefinitions = (
        tabs: NativeNavigationTabs | undefined,
        selectedId: string | undefined,
        style: NativeNavigationTabbarStyle,
      ): NativeNavigationTabs | undefined =>
        tabs === undefined ? undefined : normalizeDetachedTabRoles(tabs, selectedId, style.shape)

      const rememberNativeSelection = (id: string): void => {
        if (!id) return
        selectedTabId = id
        selectedStateDirty = hasTabbarState
        selectionGeneration += 1
      }

      const ensureTabSelectionObserver = (): Promise<void> => {
        if (observerRegistration) return observerRegistration

        const addListener = (
          bridge as unknown as {
            addListener?: (
              eventName: "tabSelect",
              listener: (event: { id: string }) => void,
            ) => Promise<unknown>
          }
        ).addListener
        if (typeof addListener !== "function") {
          observerRegistration = Promise.resolve()
          return observerRegistration
        }

        const registration = Promise.resolve(
          addListener.call(bridge, "tabSelect", (event) => rememberNativeSelection(event.id)),
        )
          .then(() => undefined)
          .catch((error: unknown) => {
            if (observerRegistration === registration) observerRegistration = undefined
            throw error
          })
        observerRegistration = registration
        return registration
      }

      const synchronizeSelectedState = async (): Promise<void> => {
        await ensureTabSelectionObserver()
        if (!hasTabbarState || !selectedStateDirty || selectedTabId === undefined) return

        const generation = selectionGeneration
        const synchronizedOptions: NativeNavigationTabbarOptions = { selectedId: selectedTabId }
        const tabs = normalizedTabDefinitions(tabDefinitions, selectedTabId, tabbarStyle)
        if (tabs !== undefined) synchronizedOptions.tabs = tabs
        validateNativeNavigationTabbarOptions(synchronizedOptions)
        assertSafeTabbarIcons(synchronizedOptions)

        await bridge.setTabbar(synchronizedOptions)
        if (selectionGeneration === generation) selectedStateDirty = false
      }

      const configure = async (
        options: NativeNavigationConfigureOptions = {},
      ): Promise<Awaited<ReturnType<NativeNavigationPlugin["configure"]>>> => {
        const normalized = normalizeNativeNavigationPatch(options)
        validateNativeNavigationConfigureOptions(normalized)
        if (hasTabbarState) await enqueueTabbarOperation(synchronizeSelectedState)
        return bridge.configure(normalized)
      }

      const setNavbar = async (
        options: NativeNavigationNavbarOptions,
      ): Promise<Awaited<ReturnType<NativeNavigationPlugin["setNavbar"]>>> => {
        const normalized = normalizeNativeNavigationPatch(options)
        validateNativeNavigationNavbarOptions(normalized)
        assertSafeNavbarIcons(normalized)
        return bridge.setNavbar(normalized)
      }

      const setTabbar = (
        options: NativeNavigationTabbarOptions,
      ): Promise<Awaited<ReturnType<NativeNavigationPlugin["setTabbar"]>>> =>
        enqueueTabbarOperation(async () => {
          const normalized = normalizeNativeNavigationPatch(options)
          await ensureTabSelectionObserver()

          const runtime = normalized as RuntimeTabbarPatch
          const hasExplicitSelectedId = Object.prototype.hasOwnProperty.call(runtime, "selectedId")
          const hasExplicitTabs = Object.prototype.hasOwnProperty.call(runtime, "tabs")
          const hasStylePatch = Object.prototype.hasOwnProperty.call(runtime, "style")
          const generation = selectionGeneration

          const nextSelectedId = hasExplicitSelectedId ? (runtime.selectedId ?? undefined) : selectedTabId
          const nextTabDefinitions = hasExplicitTabs ? (runtime.tabs ?? undefined) : tabDefinitions
          const nextTabbarStyle = hasStylePatch
            ? runtime.style === null
              ? {}
              : { ...tabbarStyle, ...runtime.style }
            : tabbarStyle

          let effectiveOptions: NativeNavigationTabbarOptions = normalized
          if (!hasExplicitSelectedId && nextSelectedId !== undefined) {
            effectiveOptions = { ...effectiveOptions, selectedId: nextSelectedId }
          }
          if (
            nextTabDefinitions !== undefined &&
            (hasExplicitTabs || hasExplicitSelectedId || hasStylePatch || selectedStateDirty)
          ) {
            effectiveOptions = {
              ...effectiveOptions,
              tabs: normalizedTabDefinitions(nextTabDefinitions, nextSelectedId, nextTabbarStyle),
            }
          }

          validateNativeNavigationTabbarOptions(effectiveOptions)
          assertSafeTabbarIcons(effectiveOptions)
          const result = await bridge.setTabbar(effectiveOptions)

          tabDefinitions = nextTabDefinitions
          tabbarStyle = nextTabbarStyle
          hasTabbarState = true
          if (selectionGeneration === generation) {
            selectedTabId = nextSelectedId
            selectedStateDirty = false
          } else {
            selectedStateDirty = true
          }
          return result
        })

      const beginTransition = async (
        options: NativeNavigationBeginTransitionOptions = {},
      ): Promise<Awaited<ReturnType<NativeNavigationPlugin["beginTransition"]>>> => {
        const normalized = normalizeNativeNavigationPatch(options)
        validateNativeNavigationTransitionOptions(normalized)
        return bridge.beginTransition(normalized)
      }

      const finishTransition = async (
        options: NativeNavigationFinishTransitionOptions = {},
      ): Promise<Awaited<ReturnType<NativeNavigationPlugin["finishTransition"]>>> => {
        const normalized = normalizeNativeNavigationPatch(options)
        validateNativeNavigationTransitionOptions(normalized)
        return bridge.finishTransition(normalized)
      }

      const overrides = new Map<PropertyKey, unknown>()
      overrides.set("configure", configure)
      overrides.set("setNavbar", setNavbar)
      overrides.set("setTabbar", setTabbar)
      overrides.set("beginTransition", beginTransition)
      overrides.set("finishTransition", finishTransition)

      return new Proxy(bridge, {
        get(target, property) {
          if (overrides.has(property)) return overrides.get(property)
          const value = Reflect.get(target, property, target)
          return typeof value === "function" ? value.bind(target) : value
        },
      })
    }
    ''',
)

write(
    "src/components.ts",
    r'''
    /* This Source Code Form is subject to the terms of the Mozilla Public
     * License, v. 2.0. If a copy of the MPL was not distributed with this
     * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

    import type {
      NativeNavigationConfigureOptions,
      NativeNavigationNavbarOptions,
      NativeNavigationTabbarOptions,
    } from "./definitions"
    import { NativeNavigation } from "./registry"

    type AttributeSnapshot = Map<string, string | null>
    type RuntimePatch = Record<string, unknown>

    const parseBoolean = (value: string | null, defaultValue = false): boolean => {
      if (value === null) return defaultValue
      return value === "" || value === "true" || value === "1"
    }

    const typedAttribute = <T extends string>(element: Element, name: string): T | null =>
      element.getAttribute(name) as T | null

    const numberAttribute = (element: Element, name: string): number | null => {
      const value = element.getAttribute(name)
      if (value === null) return null
      if (value.trim() === "") throw new TypeError(`${name} must be a finite non-negative number`)
      const number = Number(value)
      if (!Number.isFinite(number) || number < 0) {
        throw new TypeError(`${name} must be a finite non-negative number`)
      }
      return number
    }

    const jsonAttribute = <T>(element: Element, name: string, removedValue: T): T => {
      const value = element.getAttribute(name)
      if (value === null) return removedValue
      try {
        return JSON.parse(value) as T
      } catch (error) {
        throw new TypeError(`${name} contains invalid JSON`, { cause: error })
      }
    }

    const setChanged = (
      patch: RuntimePatch,
      changed: ReadonlySet<string>,
      attribute: string,
      key: string,
      value: unknown,
    ): void => {
      if (changed.has(attribute)) patch[key] = value
    }

    export function defineNativeNavigationElements(): void {
      if (typeof customElements === "undefined" || typeof HTMLElement === "undefined") return

      abstract class NativeNavigationElement extends HTMLElement {
        private syncQueued = false
        private syncTail: Promise<void> = Promise.resolve()
        private appliedAttributes: AttributeSnapshot = new Map()
        private forceFullSync = true

        protected abstract applyState(changed: ReadonlySet<string>): Promise<unknown>

        connectedCallback(): void {
          this.forceFullSync = true
          this.requestSync()
        }

        disconnectedCallback(): void {
          this.forceFullSync = true
        }

        attributeChangedCallback(): void {
          if (this.isConnected) this.requestSync()
        }

        private observedNames(): string[] {
          return (this.constructor as typeof HTMLElement & { observedAttributes?: string[] }).observedAttributes ?? []
        }

        private snapshot(names: readonly string[]): AttributeSnapshot {
          return new Map(names.map((name) => [name, this.getAttribute(name)]))
        }

        private requestSync(): void {
          if (this.syncQueued) return
          this.syncQueued = true
          this.syncTail = this.syncAfter(this.syncTail)
        }

        private async syncAfter(previous: Promise<void>): Promise<void> {
          await previous
          this.syncQueued = false
          if (!this.isConnected) return

          const names = this.observedNames()
          const snapshot = this.snapshot(names)
          const changed = new Set(
            this.forceFullSync
              ? names
              : names.filter((name) => snapshot.get(name) !== this.appliedAttributes.get(name)),
          )
          if (changed.size === 0) return

          try {
            await this.applyState(changed)
            for (const name of changed) this.appliedAttributes.set(name, snapshot.get(name) ?? null)
            this.forceFullSync = false
          } catch (error) {
            const message = error instanceof Error ? error.message : String(error)
            const detail = { element: this.localName, message }
            this.dispatchEvent(
              new CustomEvent("nativeNavigationError", {
                detail,
                bubbles: true,
                composed: true,
              }),
            )
            if (typeof window !== "undefined") {
              window.dispatchEvent(new CustomEvent("capNativeNavigation:error", { detail }))
            }
          }
        }
      }

      class CapNativeNavigationProvider extends NativeNavigationElement {
        static get observedAttributes(): string[] {
          return [
            "enabled",
            "platform-style",
            "content-inset-mode",
            "animation-duration",
            "colors",
            "glass",
          ]
        }

        protected override applyState(changed: ReadonlySet<string>): Promise<unknown> {
          const patch: RuntimePatch = {}
          setChanged(patch, changed, "enabled", "enabled", parseBoolean(this.getAttribute("enabled"), true))
          setChanged(
            patch,
            changed,
            "platform-style",
            "platformStyle",
            typedAttribute<NonNullable<NativeNavigationConfigureOptions["platformStyle"]>>(
              this,
              "platform-style",
            ) ?? "auto",
          )
          setChanged(
            patch,
            changed,
            "content-inset-mode",
            "contentInsetMode",
            typedAttribute<NonNullable<NativeNavigationConfigureOptions["contentInsetMode"]>>(
              this,
              "content-inset-mode",
            ) ?? "css",
          )
          setChanged(patch, changed, "animation-duration", "animationDuration", numberAttribute(this, "animation-duration"))
          setChanged(
            patch,
            changed,
            "colors",
            "colors",
            jsonAttribute(this, "colors", null as NativeNavigationConfigureOptions["colors"] | null),
          )
          setChanged(
            patch,
            changed,
            "glass",
            "glass",
            jsonAttribute(this, "glass", null as NativeNavigationConfigureOptions["glass"] | null),
          )
          return NativeNavigation.configure(patch as NativeNavigationConfigureOptions)
        }
      }

      class CapNativeNavbar extends NativeNavigationElement {
        static get observedAttributes(): string[] {
          return [
            "hidden",
            "title",
            "subtitle",
            "large",
            "transparent",
            "blur-effect",
            "back-button",
            "back-title",
            "left-items",
            "right-items",
            "colors",
            "glass",
            "animated",
          ]
        }

        protected override applyState(changed: ReadonlySet<string>): Promise<unknown> {
          const patch: RuntimePatch = {}
          setChanged(patch, changed, "hidden", "hidden", parseBoolean(this.getAttribute("hidden")))
          setChanged(patch, changed, "title", "title", this.getAttribute("title"))
          setChanged(patch, changed, "subtitle", "subtitle", this.getAttribute("subtitle"))
          setChanged(patch, changed, "large", "large", parseBoolean(this.getAttribute("large")))
          setChanged(patch, changed, "transparent", "transparent", parseBoolean(this.getAttribute("transparent")))
          setChanged(
            patch,
            changed,
            "blur-effect",
            "blurEffect",
            typedAttribute<NonNullable<NativeNavigationNavbarOptions["blurEffect"]>>(this, "blur-effect"),
          )
          if (changed.has("back-button") || changed.has("back-title")) {
            patch.backButton = {
              visible: parseBoolean(this.getAttribute("back-button")),
              title: this.getAttribute("back-title"),
            }
          }
          setChanged(patch, changed, "left-items", "leftItems", jsonAttribute(this, "left-items", []))
          setChanged(patch, changed, "right-items", "rightItems", jsonAttribute(this, "right-items", []))
          setChanged(
            patch,
            changed,
            "colors",
            "colors",
            jsonAttribute(this, "colors", null as NativeNavigationNavbarOptions["colors"] | null),
          )
          setChanged(
            patch,
            changed,
            "glass",
            "glass",
            jsonAttribute(this, "glass", null as NativeNavigationNavbarOptions["glass"] | null),
          )
          setChanged(patch, changed, "animated", "animated", parseBoolean(this.getAttribute("animated")))
          return NativeNavigation.setNavbar(patch as NativeNavigationNavbarOptions)
        }
      }

      class CapNativeTabbar extends NativeNavigationElement {
        static get observedAttributes(): string[] {
          return [
            "hidden",
            "tabs",
            "selected-id",
            "labels",
            "label-visibility-mode",
            "icons",
            "colors",
            "glass",
            "style",
            "blur-effect",
            "disable-transparent-on-scroll-edge",
            "disable-indicator",
            "indicator-color",
            "ripple-color",
            "badge-background-color",
            "badge-text-color",
            "experimental-baked-tint-colors",
            "animated",
          ]
        }

        protected override applyState(changed: ReadonlySet<string>): Promise<unknown> {
          const patch: RuntimePatch = {}
          setChanged(patch, changed, "hidden", "hidden", parseBoolean(this.getAttribute("hidden")))
          setChanged(patch, changed, "tabs", "tabs", jsonAttribute(this, "tabs", []))
          setChanged(patch, changed, "selected-id", "selectedId", this.getAttribute("selected-id"))
          setChanged(patch, changed, "labels", "labels", parseBoolean(this.getAttribute("labels"), true))
          setChanged(
            patch,
            changed,
            "label-visibility-mode",
            "labelVisibilityMode",
            typedAttribute<NonNullable<NativeNavigationTabbarOptions["labelVisibilityMode"]>>(
              this,
              "label-visibility-mode",
            ),
          )
          setChanged(patch, changed, "icons", "icons", parseBoolean(this.getAttribute("icons"), true))
          setChanged(
            patch,
            changed,
            "colors",
            "colors",
            jsonAttribute(this, "colors", null as NativeNavigationTabbarOptions["colors"] | null),
          )
          setChanged(
            patch,
            changed,
            "glass",
            "glass",
            jsonAttribute(this, "glass", null as NativeNavigationTabbarOptions["glass"] | null),
          )
          setChanged(
            patch,
            changed,
            "style",
            "style",
            jsonAttribute(this, "style", null as NativeNavigationTabbarOptions["style"] | null),
          )
          setChanged(
            patch,
            changed,
            "blur-effect",
            "blurEffect",
            typedAttribute<NonNullable<NativeNavigationTabbarOptions["blurEffect"]>>(this, "blur-effect"),
          )
          setChanged(
            patch,
            changed,
            "disable-transparent-on-scroll-edge",
            "disableTransparentOnScrollEdge",
            parseBoolean(this.getAttribute("disable-transparent-on-scroll-edge")),
          )
          setChanged(
            patch,
            changed,
            "disable-indicator",
            "disableIndicator",
            parseBoolean(this.getAttribute("disable-indicator")),
          )
          setChanged(patch, changed, "indicator-color", "indicatorColor", this.getAttribute("indicator-color"))
          setChanged(patch, changed, "ripple-color", "rippleColor", this.getAttribute("ripple-color"))
          setChanged(
            patch,
            changed,
            "badge-background-color",
            "badgeBackgroundColor",
            this.getAttribute("badge-background-color"),
          )
          setChanged(patch, changed, "badge-text-color", "badgeTextColor", this.getAttribute("badge-text-color"))
          setChanged(
            patch,
            changed,
            "experimental-baked-tint-colors",
            "experimentalBakedTintColors",
            parseBoolean(this.getAttribute("experimental-baked-tint-colors")),
          )
          setChanged(patch, changed, "animated", "animated", parseBoolean(this.getAttribute("animated")))
          return NativeNavigation.setTabbar(patch as NativeNavigationTabbarOptions)
        }
      }

      if (!customElements.get("cap-native-navigation-provider"))
        customElements.define("cap-native-navigation-provider", CapNativeNavigationProvider)
      if (!customElements.get("cap-native-navbar"))
        customElements.define("cap-native-navbar", CapNativeNavbar)
      if (!customElements.get("cap-native-tabbar"))
        customElements.define("cap-native-tabbar", CapNativeTabbar)
    }
    ''',
)

write(
    "src/web.ts",
    r'''
    /* This Source Code Form is subject to the terms of the Mozilla Public
     * License, v. 2.0. If a copy of the MPL was not distributed with this
     * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

    import { WebPlugin } from "@capacitor/core"

    import type {
      NativeNavigationBeginTransitionOptions,
      NativeNavigationConfigureOptions,
      NativeNavigationFinishTransitionOptions,
      NativeNavigationInsets,
      NativeNavigationInsetsResult,
      NativeNavigationNavbarOptions,
      NativeNavigationPlugin,
      NativeNavigationTabbarOptions,
      NativeNavigationTransitionDirection,
      NativeNavigationTransitionResult,
      PluginVersionResult,
    } from "./definitions"
    import { mergeNativeNavigationPatch } from "./patch"
    import {
      validateNativeNavigationConfigureOptions,
      validateNativeNavigationNavbarOptions,
      validateNativeNavigationTabbarOptions,
      validateNativeNavigationTransitionOptions,
    } from "./validation"

    const DEFAULT_NAVBAR_HEIGHT = 44
    const DEFAULT_TABBAR_HEIGHT = 64
    const DEFAULT_TABBAR_BOTTOM_GAP = 10
    const DEFAULT_TRANSITION_DURATION = 350
    const CSS_INSET_VARIABLES = [
      "--cap-native-navigation-top",
      "--cap-native-navigation-right",
      "--cap-native-navigation-bottom",
      "--cap-native-navigation-left",
      "--cap-native-navbar-height",
      "--cap-native-tabbar-height",
    ] as const

    export class NativeNavigationWeb extends WebPlugin implements NativeNavigationPlugin {
      private config: NativeNavigationConfigureOptions = {
        contentInsetMode: "css",
        enabled: true,
        platformStyle: "auto",
      }
      private navbar: NativeNavigationNavbarOptions = {}
      private tabbar: NativeNavigationTabbarOptions = {}
      private hasNavbarState = false
      private hasTabbarState = false
      private transitionSequence = 0
      private activeTransition: NativeNavigationTransitionResult | null = null

      async configure(
        options: NativeNavigationConfigureOptions = {},
      ): Promise<NativeNavigationInsetsResult> {
        validateNativeNavigationConfigureOptions(options)
        this.config = mergeNativeNavigationPatch(
          this.config as unknown as Record<string, unknown>,
          options as unknown as Record<string, unknown>,
          new Set(["colors", "glass"]),
        ) as NativeNavigationConfigureOptions
        return this.applyInsets()
      }

      async setNavbar(options: NativeNavigationNavbarOptions): Promise<NativeNavigationInsetsResult> {
        validateNativeNavigationNavbarOptions(options)
        this.navbar = mergeNativeNavigationPatch(
          this.navbar as unknown as Record<string, unknown>,
          options as unknown as Record<string, unknown>,
          new Set(["colors", "glass"]),
        ) as NativeNavigationNavbarOptions
        this.hasNavbarState = true
        return this.applyInsets()
      }

      async setTabbar(options: NativeNavigationTabbarOptions): Promise<NativeNavigationInsetsResult> {
        validateNativeNavigationTabbarOptions(options)
        this.tabbar = mergeNativeNavigationPatch(
          this.tabbar as unknown as Record<string, unknown>,
          options as unknown as Record<string, unknown>,
          new Set(["colors", "style", "glass"]),
        ) as NativeNavigationTabbarOptions
        this.hasTabbarState = true
        return this.applyInsets()
      }

      async beginTransition(
        options: NativeNavigationBeginTransitionOptions = {},
      ): Promise<NativeNavigationTransitionResult> {
        validateNativeNavigationTransitionOptions(options)
        if (this.activeTransition) {
          const interrupted = { ...this.activeTransition, duration: 0 }
          this.activeTransition = null
          this.notifyListeners("transitionEnd", interrupted)
          this.dispatchWindowEvent("transitionEnd", interrupted)
        }
        const transition = this.createTransition(options.id, options.direction, options.duration)
        this.activeTransition = transition
        this.notifyListeners("transitionStart", transition)
        this.dispatchWindowEvent("transitionStart", transition)
        return transition
      }

      async finishTransition(
        options: NativeNavigationFinishTransitionOptions = {},
      ): Promise<NativeNavigationTransitionResult> {
        validateNativeNavigationTransitionOptions(options)
        const activeTransition = this.activeTransition
        if (!activeTransition) throw new Error("No active transition")
        if (options.id !== undefined && options.id !== activeTransition.id) {
          throw new Error("Transition id does not match the active transition")
        }

        const transition = {
          ...activeTransition,
          direction: options.direction ?? activeTransition.direction,
          duration: options.duration ?? activeTransition.duration,
        }

        this.activeTransition = null
        this.notifyListeners("transitionEnd", transition)
        this.dispatchWindowEvent("transitionEnd", transition)
        return transition
      }

      async getPluginVersion(): Promise<PluginVersionResult> {
        return { version: "web" }
      }

      private createTransition(
        id: string | undefined,
        direction: NativeNavigationTransitionDirection = "forward",
        duration = this.config.animationDuration ?? DEFAULT_TRANSITION_DURATION,
      ): NativeNavigationTransitionResult {
        return { id: id ?? this.nextTransitionId(), direction, duration }
      }

      private nextTransitionId(): string {
        this.transitionSequence += 1
        return `transition-${Date.now()}-${this.transitionSequence}`
      }

      private currentTabbarHeight(): number {
        const style = this.tabbar.style
        const shape = style?.shape ?? "floating"
        const defaultHeight = shape === "curve" ? 76 : DEFAULT_TABBAR_HEIGHT
        const height = style?.height ?? defaultHeight
        const bottomGap = style?.bottomGap ?? (shape === "curve" ? 0 : DEFAULT_TABBAR_BOTTOM_GAP)
        const centerButtonLift =
          shape === "curve" ? (style?.centerButtonLift ?? (style?.centerButtonDiameter ?? 56) / 2) : 0
        return Math.ceil(height + bottomGap + centerButtonLift)
      }

      private hasVisibleTabItems(): boolean {
        const selectedId = this.tabbar.selectedId
        return (this.tabbar.tabs ?? []).some((tab) => tab.hidden !== true || tab.id === selectedId)
      }

      private applyInsets(): NativeNavigationInsetsResult {
        const enabled = this.config.enabled !== false
        const navbarVisible = enabled && this.hasNavbarState && this.navbar.hidden !== true
        const tabbarVisible =
          enabled && this.hasTabbarState && this.tabbar.hidden !== true && this.hasVisibleTabItems()
        const tabbarHeight = tabbarVisible ? this.currentTabbarHeight() : 0
        const insets: NativeNavigationInsets = {
          top: navbarVisible ? DEFAULT_NAVBAR_HEIGHT : 0,
          right: 0,
          bottom: tabbarHeight,
          left: 0,
          navbarHeight: navbarVisible ? DEFAULT_NAVBAR_HEIGHT : 0,
          tabbarHeight,
        }

        if (typeof document !== "undefined") {
          const root = document.documentElement
          if (this.config.contentInsetMode === "none") {
            for (const name of CSS_INSET_VARIABLES) root.style.removeProperty(name)
          } else {
            root.style.setProperty("--cap-native-navigation-top", `${insets.top}px`)
            root.style.setProperty("--cap-native-navigation-right", `${insets.right}px`)
            root.style.setProperty("--cap-native-navigation-bottom", `${insets.bottom}px`)
            root.style.setProperty("--cap-native-navigation-left", `${insets.left}px`)
            root.style.setProperty("--cap-native-navbar-height", `${insets.navbarHeight}px`)
            root.style.setProperty("--cap-native-tabbar-height", `${insets.tabbarHeight}px`)
          }
        }

        const event = { insets }
        this.notifyListeners("safeAreaChanged", event)
        this.dispatchWindowEvent("safeAreaChanged", event)
        return { insets }
      }

      private dispatchWindowEvent(name: string, detail: unknown): void {
        if (typeof window === "undefined") return
        window.dispatchEvent(new CustomEvent(`capNativeNavigation:${name}`, { detail }))
      }
    }
    ''',
)

replace_regex(
    "test/plugin-facade.test.ts",
    r'''  it\("removes runtime null values before forwarding patch state".*?\n  \}\)''',
    r'''
      it("keeps object-level null reset markers but removes null fields from array entries", async () => {
        const raw = makeBridge()
        const plugin = createNativeNavigationFacade(raw.bridge)
        const options = {
          tabs: [{ id: "home", badge: null }],
          colors: { tint: null, background: "#ffffff" },
          style: null,
        } as unknown as NativeNavigationTabbarOptions

        await plugin.setTabbar(options)

        expect(raw.setTabbar).toHaveBeenLastCalledWith({
          tabs: [{ id: "home" }],
          colors: { tint: null, background: "#ffffff" },
          style: null,
        })
      })
    ''',
)

insert_before_final(
    "test/plugin-facade.test.ts",
    r'''
      it("does not commit failed tabbar state into later partial updates", async () => {
        const raw = makeBridge()
        const plugin = createNativeNavigationFacade(raw.bridge)
        raw.setTabbar.mockRejectedValueOnce(new Error("native rejected"))

        await expect(
          plugin.setTabbar({ tabs: [{ id: "failed" }], selectedId: "failed" }),
        ).rejects.toThrow("native rejected")
        await plugin.setTabbar({ colors: { tint: "#ff0000" } })

        expect(raw.setTabbar).toHaveBeenLastCalledWith({ colors: { tint: "#ff0000" } })
      })

      it("retries tab selection listener registration after a transient failure", async () => {
        const raw = makeBridge()
        const plugin = createNativeNavigationFacade(raw.bridge)
        const addListener = raw.bridge.addListener as unknown as ReturnType<typeof vi.fn>
        addListener.mockRejectedValueOnce(new Error("bridge not ready"))

        await expect(plugin.setTabbar({ tabs: [{ id: "home" }] })).rejects.toThrow("bridge not ready")
        await expect(plugin.setTabbar({ tabs: [{ id: "home" }] })).resolves.toEqual(emptyInsets)
        expect(addListener).toHaveBeenCalledTimes(2)
      })

      it("serializes concurrent tabbar patches in invocation order", async () => {
        const raw = makeBridge()
        const plugin = createNativeNavigationFacade(raw.bridge)
        let releaseFirst: (() => void) | undefined
        raw.setTabbar.mockImplementationOnce(
          () => new Promise((resolve) => {
            releaseFirst = () => resolve(emptyInsets)
          }),
        )

        const first = plugin.setTabbar({ tabs: [{ id: "home" }], selectedId: "home" })
        const second = plugin.setTabbar({ style: { bottomGap: 20 } })
        await Promise.resolve()
        expect(raw.setTabbar).toHaveBeenCalledTimes(1)

        releaseFirst?.()
        await Promise.all([first, second])
        expect(raw.setTabbar).toHaveBeenNthCalledWith(2, {
          selectedId: "home",
          style: { bottomGap: 20 },
          tabs: [{ id: "home" }],
        })
      })

      it("rejects non-finite layout and transition values before native allocation", async () => {
        const raw = makeBridge()
        const plugin = createNativeNavigationFacade(raw.bridge)

        await expect(
          plugin.setTabbar({ tabs: [{ id: "home" }], style: { height: Number.NaN } }),
        ).rejects.toThrow("style.height")
        await expect(plugin.beginTransition({ duration: Number.POSITIVE_INFINITY })).rejects.toThrow("duration")
        expect(raw.setTabbar).not.toHaveBeenCalled()
      })
    ''',
)

replace_regex(
    "test/components.test.ts",
    r'''  it\("parses JSON attributes and falls back when they are malformed".*?\n  \}\)''',
    r'''
      it("rejects malformed JSON without clearing the last valid native state", async () => {
        const tabbar = document.createElement("cap-native-tabbar")
        const errors = vi.fn()
        tabbar.addEventListener("nativeNavigationError", errors)
        tabbar.setAttribute("tabs", '[{"id":"a"},{"id":"b"}]')
        document.body.append(tabbar)
        await flush()
        expect(setTabbar).toHaveBeenCalledTimes(1)
        setTabbar.mockClear()

        tabbar.setAttribute("tabs", "not json")
        await flush()

        expect(setTabbar).not.toHaveBeenCalled()
        expect(errors).toHaveBeenCalledTimes(1)
      })
    ''',
)

insert_before_final(
    "test/components.test.ts",
    r'''
      it("sends explicit reset markers when optional attributes are removed", async () => {
        const navbar = document.createElement("cap-native-navbar")
        navbar.setAttribute("title", "Before")
        navbar.setAttribute("colors", '{"tint":"#ff0000"}')
        document.body.append(navbar)
        await flush()
        setNavbar.mockClear()

        navbar.removeAttribute("title")
        navbar.removeAttribute("colors")
        await flush()

        expect(setNavbar).toHaveBeenCalledTimes(1)
        expect(setNavbar.mock.calls[0][0]).toEqual({ title: null, colors: null })
      })

      it("retries all unapplied attributes after a rejected native call", async () => {
        const navbar = document.createElement("cap-native-navbar")
        document.body.append(navbar)
        await flush()
        setNavbar.mockClear()
        setNavbar.mockRejectedValueOnce(new Error("native unavailable"))

        navbar.setAttribute("title", "first")
        await flush()
        navbar.setAttribute("subtitle", "retry")
        await flush()

        expect(setNavbar.mock.calls.at(-1)?.[0]).toMatchObject({ title: "first", subtitle: "retry" })
      })
    ''',
)

insert_before_final(
    "test/web.test.ts",
    r'''
      it("applies null reset markers with the same semantics as native", async () => {
        await plugin.setTabbar({
          tabs: [{ id: "home" }],
          style: { height: 100, bottomGap: 20 },
        })
        const reset = await plugin.setTabbar({
          style: null,
        } as unknown as NativeNavigationTabbarOptions)

        expect(reset.insets.bottom).toBe(74)
      })

      it("rejects invalid runtime dimensions instead of emitting invalid CSS", async () => {
        await expect(
          plugin.setTabbar({ tabs: [{ id: "home" }], style: { height: Number.NaN } }),
        ).rejects.toThrow("style.height")
        expect(cssVar("--cap-native-navigation-bottom")).toBe("")
      })
    ''',
)

print("phase 1 source transformations completed")
