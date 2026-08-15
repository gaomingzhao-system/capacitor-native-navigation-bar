import { describe, expect, it, vi } from "vitest";

import type {
  NativeNavigationPlugin,
  NativeNavigationTabSelectEvent,
  NativeNavigationTabbarOptions,
} from "../src/definitions";
import { createNativeNavigationFacade } from "../src/plugin-facade";

const emptyInsets = {
  insets: {
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
    navbarHeight: 0,
    tabbarHeight: 0,
  },
};

const makeBridge = () => {
  let tabSelectListener: ((event: NativeNavigationTabSelectEvent) => void) | undefined;
  const configure = vi.fn(async () => emptyInsets);
  const setNavbar = vi.fn(async () => emptyInsets);
  const setTabbar = vi.fn(async () => emptyInsets);
  const bridge = {
    configure,
    setNavbar,
    setTabbar,
    beginTransition: vi.fn(async () => ({ id: "transition", direction: "forward", duration: 0 })),
    finishTransition: vi.fn(async () => ({ id: "transition", direction: "forward", duration: 0 })),
    getPluginVersion: vi.fn(async () => ({ version: "test" })),
    addListener: vi.fn(
      async (eventName: string, listener: (event: NativeNavigationTabSelectEvent) => void) => {
        if (eventName === "tabSelect") tabSelectListener = listener;
        return { remove: async () => undefined };
      },
    ),
  } as unknown as NativeNavigationPlugin;

  return {
    bridge,
    configure,
    setNavbar,
    setTabbar,
    emitTabSelect: (event: NativeNavigationTabSelectEvent) => tabSelectListener?.(event),
  };
};

describe("createNativeNavigationFacade", () => {
  it("persists a native tab selection before later partial updates", async () => {
    const raw = makeBridge();
    const plugin = createNativeNavigationFacade(raw.bridge);
    await plugin.setTabbar({
      tabs: [{ id: "home" }, { id: "search" }],
      selectedId: "home",
    });

    raw.emitTabSelect({ id: "search", index: 1, title: "Search" });
    await plugin.configure({});

    expect(raw.setTabbar).toHaveBeenNthCalledWith(2, { selectedId: "search" });

    await plugin.setTabbar({ colors: { tint: "#ff0000" } });
    expect(raw.setTabbar).toHaveBeenLastCalledWith({
      colors: { tint: "#ff0000" },
      selectedId: "search",
    });
  });

  it("removes runtime null values before forwarding patch state", async () => {
    const raw = makeBridge();
    const plugin = createNativeNavigationFacade(raw.bridge);
    const options = {
      tabs: [{ id: "home", badge: null }],
      colors: { tint: null, background: "#ffffff" },
      style: null,
    } as unknown as NativeNavigationTabbarOptions;

    await plugin.setTabbar(options);

    expect(raw.setTabbar).toHaveBeenLastCalledWith({
      tabs: [{ id: "home" }],
      colors: { background: "#ffffff" },
    });
  });

  it("rejects oversized encoded SVG payloads before crossing the native bridge", async () => {
    const raw = makeBridge();
    const plugin = createNativeNavigationFacade(raw.bridge);
    const oversizedPayload = "A".repeat(350_000);

    await expect(
      plugin.setNavbar({
        leftItems: [
          {
            id: "unsafe",
            icon: { src: `data:image/svg+xml;base64,${oversizedPayload}` },
          },
        ],
      }),
    ).rejects.toThrow("encoded SVG limit");
    expect(raw.setNavbar).not.toHaveBeenCalled();
  });
});
