import { beforeEach, describe, expect, it, vi } from "vitest"

import { NativeNavigationWeb } from "../src/web"

const cssVar = (name: string) => document.documentElement.style.getPropertyValue(name)

const CSS_INSET_VARIABLES = [
  "--cap-native-navigation-top",
  "--cap-native-navigation-right",
  "--cap-native-navigation-bottom",
  "--cap-native-navigation-left",
  "--cap-native-navbar-height",
  "--cap-native-tabbar-height",
] as const

const clearCssVars = () => {
  for (const name of CSS_INSET_VARIABLES) {
    document.documentElement.style.removeProperty(name)
  }
}

describe("NativeNavigationWeb", () => {
  let plugin: NativeNavigationWeb

  beforeEach(() => {
    clearCssVars()
    plugin = new NativeNavigationWeb()
  })

  it("starts with both bars hidden", async () => {
    const { insets } = await plugin.configure()

    expect(insets).toEqual({
      top: 0,
      right: 0,
      bottom: 0,
      left: 0,
      navbarHeight: 0,
      tabbarHeight: 0,
    })
  })

  it("reports the navbar height once the navbar is shown", async () => {
    const { insets } = await plugin.setNavbar({ hidden: false, title: "Home" })

    expect(insets.top).toBe(44)
    expect(insets.navbarHeight).toBe(44)
    expect(insets.bottom).toBe(0)
  })

  it("shows the navbar on its first update when hidden is omitted", async () => {
    const { insets } = await plugin.setNavbar({ title: "Home" })

    expect(insets.top).toBe(44)
    expect(insets.navbarHeight).toBe(44)
  })

  it("shows the tabbar on its first update when hidden is omitted", async () => {
    const { insets } = await plugin.setTabbar({ tabs: [{ id: "home" }] })

    expect(insets.bottom).toBe(74)
    expect(insets.tabbarHeight).toBe(74)
  })

  it("keeps the tabbar hidden when it has no visible items", async () => {
    const empty = await plugin.setTabbar({ hidden: false, tabs: [] })
    expect(empty.insets.bottom).toBe(0)

    const hidden = await plugin.setTabbar({ tabs: [{ id: "private", hidden: true }] })
    expect(hidden.insets.bottom).toBe(0)
  })

  it("keeps a selected hidden tab visible like the native implementations", async () => {
    const { insets } = await plugin.setTabbar({
      selectedId: "private",
      tabs: [{ id: "private", hidden: true }],
    })

    expect(insets.bottom).toBe(74)
  })

  it("writes CSS variables by default and removes all of them in `none` mode", async () => {
    await plugin.setNavbar({ hidden: false })
    await plugin.setTabbar({ hidden: false })
    for (const name of CSS_INSET_VARIABLES) expect(cssVar(name)).not.toBe("")

    await plugin.configure({ contentInsetMode: "none" })
    for (const name of CSS_INSET_VARIABLES) expect(cssVar(name)).toBe("")
  })

  it("uses the floating defaults when no style is given", async () => {
    const { insets } = await plugin.setTabbar({ hidden: false, tabs: [{ id: "a" }] })

    expect(insets.bottom).toBe(74)
    expect(insets.tabbarHeight).toBe(74)
  })

  it("derives the floating tabbar height from height + bottom gap", async () => {
    const { insets } = await plugin.setTabbar({
      hidden: false,
      tabs: [{ id: "home" }],
      style: { shape: "floating", height: 64, bottomGap: 10 },
    })

    expect(insets.bottom).toBe(74)
  })

  it("adds the center button lift for curve tabbars", async () => {
    const { insets } = await plugin.setTabbar({
      hidden: false,
      tabs: [{ id: "home" }],
      style: { shape: "curve", height: 76, centerButtonDiameter: 56 },
    })

    // 76 height + 0 default curve gap + 28 lift (half the 56pt center button).
    expect(insets.bottom).toBe(104)
  })

  it("reports zero insets while disabled but keeps the requested state", async () => {
    await plugin.setNavbar({ hidden: false })
    await plugin.setTabbar({ hidden: false, tabs: [{ id: "home" }] })

    const disabled = await plugin.configure({ enabled: false })
    expect(disabled.insets.top).toBe(0)
    expect(disabled.insets.bottom).toBe(0)

    const enabled = await plugin.configure({ enabled: true })
    expect(enabled.insets.top).toBe(44)
    expect(enabled.insets.bottom).toBe(74)
  })

  it("merges the nested style object across calls instead of replacing it", async () => {
    await plugin.setTabbar({
      hidden: false,
      tabs: [{ id: "home" }],
      style: { shape: "floating", height: 100 },
    })

    // The second call sets only bottomGap. If `style` were replaced rather than
    // merged, the height would fall back to 64 and this would be 84.
    const { insets } = await plugin.setTabbar({ style: { bottomGap: 20 } })
    expect(insets.bottom).toBe(120)
  })

  it("keeps top-level state across successive calls that omit it", async () => {
    await plugin.setTabbar({
      hidden: false,
      tabs: [{ id: "home" }],
      colors: { tint: "#ff0000" },
    })

    // `hidden` is not repeated, so the spread must preserve the previous value.
    const { insets } = await plugin.setTabbar({ colors: { badgeText: "#0000ff" } })
    expect(insets.bottom).toBe(74)
  })

  it("emits safeAreaChanged to plugin listeners and to the window", async () => {
    const pluginListener = vi.fn()
    const windowListener = vi.fn()
    await plugin.addListener("safeAreaChanged", pluginListener)
    window.addEventListener("capNativeNavigation:safeAreaChanged", windowListener)

    await plugin.setNavbar({ hidden: false })

    expect(pluginListener).toHaveBeenCalledTimes(1)
    expect(pluginListener.mock.calls[0][0].insets.top).toBe(44)
    expect(windowListener).toHaveBeenCalledTimes(1)

    window.removeEventListener("capNativeNavigation:safeAreaChanged", windowListener)
  })

  it("rejects finish when there is no active transition", async () => {
    await expect(plugin.finishTransition()).rejects.toThrow("No active transition")
  })

  it("ends an interrupted transition exactly once before replacing it", async () => {
    const ended = vi.fn()
    await plugin.addListener("transitionEnd", ended)
    await plugin.beginTransition({ id: "old", duration: 120 })

    await plugin.beginTransition({ id: "new", duration: 80 })

    expect(ended).toHaveBeenCalledTimes(1)
    expect(ended).toHaveBeenCalledWith({ id: "old", direction: "forward", duration: 0 })
    await expect(plugin.finishTransition({ id: "new" })).resolves.toMatchObject({ id: "new" })
  })

  it("generates unique ids for transitions begun in the same millisecond", async () => {
    const now = vi.spyOn(Date, "now").mockReturnValue(1_234)
    try {
      const first = await plugin.beginTransition()
      const second = await plugin.beginTransition()

      expect(first.id).not.toBe(second.id)
      await expect(plugin.finishTransition({ id: first.id })).rejects.toThrow(
        "Transition id does not match the active transition",
      )
      await expect(plugin.finishTransition({ id: second.id })).resolves.toMatchObject({
        id: second.id,
      })
    } finally {
      now.mockRestore()
    }
  })

  it("round-trips a transition and keeps the id across begin/finish", async () => {
    const started = vi.fn()
    const ended = vi.fn()
    await plugin.addListener("transitionStart", started)
    await plugin.addListener("transitionEnd", ended)

    const begun = await plugin.beginTransition({ id: "t1", direction: "forward", duration: 120 })
    expect(begun).toEqual({ id: "t1", direction: "forward", duration: 120 })

    const finished = await plugin.finishTransition({})
    expect(finished.id).toBe("t1")
    expect(finished.direction).toBe("forward")
    expect(started).toHaveBeenCalledTimes(1)
    expect(ended).toHaveBeenCalledTimes(1)
  })

  it("overrides direction and duration on finish", async () => {
    await plugin.beginTransition({ id: "t2" })
    const finished = await plugin.finishTransition({ id: "t2", direction: "back", duration: 10 })

    expect(finished).toEqual({ id: "t2", direction: "back", duration: 10 })
  })

  it("rejects a mismatched transition id without clearing the active transition", async () => {
    await plugin.beginTransition({ id: "t3" })

    await expect(plugin.finishTransition({ id: "other" })).rejects.toThrow(
      "Transition id does not match the active transition",
    )
    await expect(plugin.finishTransition({ id: "t3" })).resolves.toMatchObject({ id: "t3" })
  })

  it("rejects invalid configured durations without changing the previous default", async () => {
    await plugin.configure({ animationDuration: 500 })

    await Promise.all(
      [Number.NaN, Number.POSITIVE_INFINITY, -1, 60_001].map((animationDuration) =>
        expect(plugin.configure({ animationDuration })).rejects.toThrow(
          "animationDuration must be a finite value between 0 and 60000 milliseconds",
        ),
      ),
    )

    await expect(plugin.beginTransition({ id: "configured" })).resolves.toMatchObject({
      duration: 500,
    })
  })

  it("rejects an invalid begin duration without replacing the active transition", async () => {
    await plugin.beginTransition({ id: "active", duration: 120 })

    await Promise.all(
      [Number.NaN, Number.NEGATIVE_INFINITY, -1, 60_001].map((duration) =>
        expect(plugin.beginTransition({ id: "invalid", duration })).rejects.toThrow(
          "duration must be a finite value between 0 and 60000 milliseconds",
        ),
      ),
    )

    await expect(plugin.finishTransition({ id: "active" })).resolves.toMatchObject({
      id: "active",
    })
  })

  it("rejects an invalid finish duration without clearing the active transition", async () => {
    await plugin.beginTransition({ id: "active", duration: 120 })

    await Promise.all(
      [Number.NaN, Number.POSITIVE_INFINITY, -1, 60_001].map((duration) =>
        expect(plugin.finishTransition({ id: "active", duration })).rejects.toThrow(
          "duration must be a finite value between 0 and 60000 milliseconds",
        ),
      ),
    )

    await expect(plugin.finishTransition({ id: "active", duration: 0 })).resolves.toMatchObject({
      id: "active",
      duration: 0,
    })
  })

  it("uses the configured animation duration as the transition default", async () => {
    await plugin.configure({ animationDuration: 500 })
    const begun = await plugin.beginTransition({})

    expect(begun.duration).toBe(500)
  })

  it("reports `web` as the implementation version", async () => {
    await expect(plugin.getPluginVersion()).resolves.toEqual({ version: "web" })
  })
})
