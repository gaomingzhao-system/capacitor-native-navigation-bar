import { beforeEach, describe, expect, it, vi } from "vitest"

import { NativeNavigationWeb } from "../src/web"

describe("NativeNavigationWeb", () => {
  let plugin: NativeNavigationWeb

  beforeEach(() => {
    plugin = new NativeNavigationWeb()
  })

  it("resolves configure/setNavbar/setTabbar without a return value", async () => {
    await expect(plugin.configure()).resolves.toBeUndefined()
    await expect(plugin.setNavbar({ hidden: false, title: "Home" })).resolves.toBeUndefined()
    await expect(
      plugin.setTabbar({ hidden: false, tabs: [{ id: "home" }] }),
    ).resolves.toBeUndefined()
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
