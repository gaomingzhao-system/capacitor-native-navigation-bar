import { beforeEach, describe, expect, it, vi } from "vitest"

const beginTransition = vi.fn(async (options: unknown) => options)
const finishTransition = vi.fn(async (options: unknown) => options)

vi.mock("@capacitor/core", () => ({
  registerPlugin: () => ({ beginTransition, finishTransition }),
}))

const { beginZoomTransition, finishZoomTransition, getNativeNavigationRect } =
  await import("../src/index")

describe("zoom transition helpers", () => {
  beforeEach(() => {
    beginTransition.mockClear()
    finishTransition.mockClear()
  })

  it("passes a plain rect straight through", () => {
    expect(getNativeNavigationRect({ x: 1, y: 2, width: 3, height: 4 })).toEqual({
      x: 1,
      y: 2,
      width: 3,
      height: 4,
    })
  })

  it("reads viewport coordinates from an element", () => {
    const element = document.createElement("div")
    document.body.append(element)
    vi.spyOn(element, "getBoundingClientRect").mockReturnValue({
      x: 10,
      y: 20,
      width: 30,
      height: 40,
      top: 20,
      left: 10,
      right: 40,
      bottom: 60,
      toJSON: () => ({}),
    } as DOMRect)

    expect(getNativeNavigationRect(element)).toEqual({ x: 10, y: 20, width: 30, height: 40 })
    element.remove()
  })

  it("begins a zoom transition from an element rect", async () => {
    const element = document.createElement("div")
    vi.spyOn(element, "getBoundingClientRect").mockReturnValue({
      x: 5,
      y: 6,
      width: 7,
      height: 8,
      top: 6,
      left: 5,
      right: 12,
      bottom: 14,
      toJSON: () => ({}),
    } as DOMRect)

    await beginZoomTransition(element, { id: "zoom-1", duration: 200 })

    expect(beginTransition).toHaveBeenCalledWith({
      id: "zoom-1",
      duration: 200,
      direction: "zoom",
      sourceRect: { x: 5, y: 6, width: 7, height: 8 },
    })
  })

  it("finishes a zoom transition without a target rect", async () => {
    await finishZoomTransition(undefined, { id: "zoom-2" })

    expect(finishTransition).toHaveBeenCalledWith({
      id: "zoom-2",
      direction: "zoom",
      targetRect: undefined,
    })
  })

  it("finishes a zoom transition into a target rect", async () => {
    await finishZoomTransition({ x: 0, y: 0, width: 100, height: 200 })

    expect(finishTransition).toHaveBeenCalledWith({
      direction: "zoom",
      targetRect: { x: 0, y: 0, width: 100, height: 200 },
    })
  })

  it("cannot have its direction or rect overridden by the caller", async () => {
    // `direction`/`sourceRect` are Omit-ed from the options type, but the runtime
    // guarantee is spread order, so pass conflicting values to actually exercise it.
    const hostile = {
      id: "zoom-3",
      direction: "forward",
      sourceRect: { x: 9, y: 9, width: 9, height: 9 },
    }
    await beginZoomTransition(
      { x: 0, y: 0, width: 1, height: 1 },
      hostile as unknown as Parameters<typeof beginZoomTransition>[1],
    )

    expect(beginTransition.mock.calls[0][0]).toEqual({
      id: "zoom-3",
      direction: "zoom",
      sourceRect: { x: 0, y: 0, width: 1, height: 1 },
    })
  })

  it("cannot have its finish direction or target rect overridden by the caller", async () => {
    const hostile = {
      id: "zoom-4",
      direction: "back",
      targetRect: { x: 9, y: 9, width: 9, height: 9 },
    }
    await finishZoomTransition(
      { x: 1, y: 2, width: 3, height: 4 },
      hostile as unknown as Parameters<typeof finishZoomTransition>[1],
    )

    expect(finishTransition.mock.calls[0][0]).toEqual({
      id: "zoom-4",
      direction: "zoom",
      targetRect: { x: 1, y: 2, width: 3, height: 4 },
    })
  })
})
