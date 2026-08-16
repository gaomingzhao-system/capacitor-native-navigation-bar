/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import type {
  NativeNavigationBeginTransitionOptions,
  NativeNavigationFinishTransitionOptions,
  NativeNavigationRect,
  NativeNavigationTransitionResult,
} from "./definitions";
import { NativeNavigation } from "./registry";

export { NativeNavigation };
export * from "./definitions";
export { defineNativeNavigationElements } from "./components";

/** A DOM element, DOMRect, or NativeNavigationRect convertible into viewport coordinates for zoom transitions. */
export type NativeNavigationRectTarget = Element | DOMRect | NativeNavigationRect;

const isElement = (target: NativeNavigationRectTarget): target is Element =>
  typeof Element !== "undefined" && target instanceof Element;

/** Convert an element or DOMRect into viewport coordinates accepted by native zoom transitions. */
export const getNativeNavigationRect = (
  target: NativeNavigationRectTarget,
): NativeNavigationRect => {
  const rect = isElement(target) ? target.getBoundingClientRect() : target;
  return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
};

/** Begin an Apple-Zoom-style native transition from a DOM element or rect. */
export const beginZoomTransition = (
  target: NativeNavigationRectTarget,
  options: Omit<NativeNavigationBeginTransitionOptions, "direction" | "sourceRect"> = {},
): Promise<NativeNavigationTransitionResult> =>
  NativeNavigation.beginTransition({
    ...options,
    direction: "zoom",
    sourceRect: getNativeNavigationRect(target),
  });

/** Finish an Apple-Zoom-style native transition into an optional DOM element or rect on the destination route. */
export const finishZoomTransition = (
  target?: NativeNavigationRectTarget,
  options: Omit<NativeNavigationFinishTransitionOptions, "direction" | "targetRect"> = {},
): Promise<NativeNavigationTransitionResult> =>
  NativeNavigation.finishTransition({
    ...options,
    direction: "zoom",
    targetRect: target ? getNativeNavigationRect(target) : undefined,
  });
