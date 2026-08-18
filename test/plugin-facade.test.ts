import { describe, expect, it, vi } from "vitest"

import type {
  NativeNavigationPlugin,
  NativeNavigationTabSelectEvent,
  NativeNavigationTabbarOptions,
} from "../src/definitions"
import { createNativeNavigationFacade } from "../src/plugin-facade"

const makeBridge = () => {
  let tabSelectListener: ((event: NativeNavigationTabSelectEvent) => void) | undefined
  const configure = vi.fn(async () => {})
  const setNavbar = vi.fn(async () => {})
  const setTabbar = vi.fn(async () => {})
  const bridge = {
    configure,
    setNavbar,
    setTabbar,
    beginTransition: vi.fn(async () => ({ id: "transition", direction: "forward", duration: 0 })),
    finishTransition: vi.fn(async () => ({ id: "transition", direction: "forward", duration: 0 })),
    getPluginVersion: vi.fn(async () => ({ version: "test" })),
    addListener: vi.fn(
      async (eventName: string, listener: (event: NativeNavigationTabSelectEvent) => void) => {
        if (eventName === "tabSelect") tabSelectListener = listener
        return { remove: async () => undefined }
      },
    ),
  } as unknown as NativeNavigationPlugin

  return {
    bridge,
    configure,
    setNavbar,
    setTabbar,
    emitTabSelect: (event: NativeNavigationTabSelectEvent) => tabSelectListener?.(event),
  }
}

describe("createNativeNavigationFacade", () => {
  it("persists a native tab selection before later partial updates", async () => {
    const raw = makeBridge()
    const plugin = createNativeNavigationFacade(raw.bridge)
    const tabs = [{ id: "home" }, { id: "search" }]
    await plugin.setTabbar({ tabs, selectedId: "home" })

    raw.emitTabSelect({ id: "search", index: 1, title: "Search" })
    await plugin.configure({})

    expect(raw.setTabbar).toHaveBeenNthCalledWith(2, { selectedId: "search", tabs })

    await plugin.setTabbar({ colors: { tint: "#ff0000" } })
    expect(raw.setTabbar).toHaveBeenLastCalledWith({
      colors: { tint: "#ff0000" },
      selectedId: "search",
    })
  })

  it("keeps earlier visible detached-role tabs as normal tabs when the last role wins", async () => {
    const raw = makeBridge()
    const plugin = createNativeNavigationFacade(raw.bridge)

    await plugin.setTabbar({
      selectedId: "home",
      tabs: [
        { id: "home" },
        { id: "search-a", role: "search" },
        { id: "prominent", role: "prominent" },
        { id: "search-b", role: "search" },
      ],
    })

    expect(raw.setTabbar).toHaveBeenCalledWith({
      selectedId: "home",
      tabs: [
        { id: "home" },
        { id: "search-a", role: "normal" },
        { id: "prominent", role: "normal" },
        { id: "search-b", role: "search" },
      ],
    })
  })

  it("ignores a hidden trailing role when choosing the detached visible tab", async () => {
    const raw = makeBridge()
    const plugin = createNativeNavigationFacade(raw.bridge)
    const tabs = [
      { id: "home" },
      { id: "search-visible", role: "search" as const },
      { id: "search-hidden", role: "search" as const, hidden: true },
    ]

    await plugin.setTabbar({ selectedId: "home", tabs })

    expect(raw.setTabbar).toHaveBeenCalledWith({ selectedId: "home", tabs })
  })

  it("re-evaluates detached roles when a hidden role becomes selected", async () => {
    const raw = makeBridge()
    const plugin = createNativeNavigationFacade(raw.bridge)
    const tabs = [
      { id: "home" },
      { id: "search-visible", role: "search" as const },
      { id: "search-hidden", role: "search" as const, hidden: true },
    ]
    await plugin.setTabbar({ selectedId: "home", tabs })

    await plugin.setTabbar({ selectedId: "search-hidden" })

    expect(raw.setTabbar).toHaveBeenLastCalledWith({
      selectedId: "search-hidden",
      tabs: [
        { id: "home" },
        { id: "search-visible", role: "normal" },
        { id: "search-hidden", role: "search", hidden: true },
      ],
    })
  })

  it("preserves role declarations for curve bars and restores floating normalization", async () => {
    const raw = makeBridge()
    const plugin = createNativeNavigationFacade(raw.bridge)
    const tabs = [
      { id: "home" },
      { id: "search-a", role: "search" as const },
      { id: "search-b", role: "search" as const },
    ]

    await plugin.setTabbar({ selectedId: "home", style: { shape: "curve" }, tabs })
    expect(raw.setTabbar).toHaveBeenLastCalledWith({
      selectedId: "home",
      style: { shape: "curve" },
      tabs,
    })

    await plugin.setTabbar({ style: { shape: "floating" } })
    expect(raw.setTabbar).toHaveBeenLastCalledWith({
      selectedId: "home",
      style: { shape: "floating" },
      tabs: [
        { id: "home" },
        { id: "search-a", role: "normal" },
        { id: "search-b", role: "search" },
      ],
    })
  })

  it("removes runtime null values before forwarding patch state", async () => {
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
      colors: { background: "#ffffff" },
    })
  })

  it("rejects oversized encoded SVG payloads before crossing the native bridge", async () => {
    const raw = makeBridge()
    const plugin = createNativeNavigationFacade(raw.bridge)
    const oversizedPayload = "A".repeat(350_000)

    await expect(
      plugin.setNavbar({
        leftItems: [
          {
            id: "unsafe",
            icon: { src: `data:image/svg+xml;base64,${oversizedPayload}` },
          },
        ],
      }),
    ).rejects.toThrow("encoded SVG limit")
    expect(raw.setNavbar).not.toHaveBeenCalled()
  })
})
