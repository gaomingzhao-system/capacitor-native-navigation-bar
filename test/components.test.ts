import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

type Options = Record<string, unknown>

const configure = vi.fn(async (_options: Options) => {})
const setNavbar = vi.fn(async (_options: Options) => {})
const setTabbar = vi.fn(async (_options: Options) => {})

vi.mock("@capacitor/core", () => ({
  registerPlugin: () => ({ configure, setNavbar, setTabbar }),
}))

const { defineNativeNavigationElements } = await import("../src/components")

/** Yields a macrotask so every queued microtask (the coalesced sync) settles. */
const flush = () => new Promise<void>((resolve) => setTimeout(resolve, 0))

describe("defineNativeNavigationElements", () => {
  beforeEach(() => {
    configure.mockClear()
    setNavbar.mockClear()
    setTabbar.mockClear()
    defineNativeNavigationElements()
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("registers the three custom elements exactly once", () => {
    const provider = customElements.get("cap-native-navigation-provider")
    defineNativeNavigationElements()

    expect(provider).toBeDefined()
    expect(customElements.get("cap-native-navbar")).toBeDefined()
    expect(customElements.get("cap-native-tabbar")).toBeDefined()
    expect(customElements.get("cap-native-navigation-provider")).toBe(provider)
  })

  it("configures with defaults when the provider is connected", async () => {
    document.body.innerHTML = "<cap-native-navigation-provider></cap-native-navigation-provider>"
    await flush()

    expect(configure).toHaveBeenCalledTimes(1)
    expect(configure.mock.calls[0][0]).toMatchObject({
      enabled: true,
      platformStyle: "auto",
    })
  })

  it("parses JSON attributes and falls back when they are malformed", async () => {
    document.body.innerHTML =
      '<cap-native-tabbar tabs=\'[{"id":"a"},{"id":"b"}]\' colors="not json" selected-id="b"></cap-native-tabbar>'
    await flush()

    const options = setTabbar.mock.calls[0][0]
    expect(options.tabs).toEqual([{ id: "a" }, { id: "b" }])
    expect(options.selectedId).toBe("b")
    expect(options.colors).toBeUndefined()
  })

  it("treats a bare boolean attribute as true and a missing one as its default", async () => {
    document.body.innerHTML = "<cap-native-navbar large transparent></cap-native-navbar>"
    await flush()

    const options = setNavbar.mock.calls[0][0]
    expect(options.large).toBe(true)
    expect(options.transparent).toBe(true)
    expect(options.hidden).toBe(false)
    expect(options.animated).toBe(false)
  })

  it("keeps `labels` and `icons` defaulted to true on the tabbar", async () => {
    document.body.innerHTML = "<cap-native-tabbar></cap-native-tabbar>"
    await flush()

    const options = setTabbar.mock.calls[0][0]
    expect(options.labels).toBe(true)
    expect(options.icons).toBe(true)
  })

  it("maps tabbar style and scroll-edge transparency attributes", async () => {
    const tabbar = document.createElement("cap-native-tabbar")
    document.body.append(tabbar)
    await flush()
    setTabbar.mockClear()

    tabbar.setAttribute("style", '{"shape":"curve","height":88}')
    tabbar.setAttribute("disable-transparent-on-scroll-edge", "")
    await flush()

    expect(setTabbar).toHaveBeenCalledTimes(1)
    const options = setTabbar.mock.calls[0][0]
    expect(options.style).toEqual({ shape: "curve", height: 88 })
    expect(options.disableTransparentOnScrollEdge).toBe(true)
  })

  it.each([
    ["0", 0],
    ["250.5", 250.5],
  ])("passes a finite non-negative animation duration (%s)", async (value, expected) => {
    document.body.innerHTML = `<cap-native-navigation-provider animation-duration="${value}"></cap-native-navigation-provider>`
    await flush()

    expect(configure.mock.calls[0][0].animationDuration).toBe(expected)
  })

  it.each(["", "-1", "NaN", "Infinity"])(
    "omits an invalid animation duration (%s)",
    async (value) => {
      document.body.innerHTML = `<cap-native-navigation-provider animation-duration="${value}"></cap-native-navigation-provider>`
      await flush()

      expect(configure.mock.calls[0][0]).not.toHaveProperty("animationDuration")
    },
  )

  it("coalesces a burst of attribute writes into one native call", async () => {
    const navbar = document.createElement("cap-native-navbar")
    document.body.append(navbar)
    await flush()
    expect(setNavbar).toHaveBeenCalledTimes(1)

    navbar.setAttribute("title", "One")
    navbar.setAttribute("subtitle", "Two")
    navbar.setAttribute("large", "")
    navbar.setAttribute("transparent", "")
    await flush()

    expect(setNavbar).toHaveBeenCalledTimes(2)
    expect(setNavbar.mock.calls[1][0]).toMatchObject({
      title: "One",
      subtitle: "Two",
      large: true,
    })
  })

  it("does not call native for attribute changes while disconnected", async () => {
    const navbar = document.createElement("cap-native-navbar")
    document.body.append(navbar)
    await flush()
    setNavbar.mockClear()

    navbar.remove()
    navbar.setAttribute("title", "ignored")
    await flush()

    expect(setNavbar).not.toHaveBeenCalled()
  })

  it("survives a rejected native call and still applies the next change", async () => {
    const navbar = document.createElement("cap-native-navbar")
    document.body.append(navbar)
    await flush()

    setNavbar.mockRejectedValueOnce(new Error("native unavailable"))
    navbar.setAttribute("title", "fails")
    await flush()

    navbar.setAttribute("title", "recovers")
    await flush()

    expect(setNavbar.mock.calls[setNavbar.mock.calls.length - 1][0]).toMatchObject({
      title: "recovers",
    })
  })

  it("maps the back button attributes onto the backButton option", async () => {
    document.body.innerHTML = '<cap-native-navbar back-button back-title="Up"></cap-native-navbar>'
    await flush()

    expect(setNavbar.mock.calls[0][0].backButton).toEqual({ visible: true, title: "Up" })
  })
})
