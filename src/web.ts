/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { WebPlugin } from "@capacitor/core"

import type {
  NativeNavigationBeginTransitionOptions,
  NativeNavigationConfigureOptions,
  NativeNavigationFinishTransitionOptions,
  NativeNavigationNavbarOptions,
  NativeNavigationPlugin,
  NativeNavigationTabbarOptions,
  NativeNavigationTransitionDirection,
  NativeNavigationTransitionResult,
  PluginVersionResult,
} from "./definitions"

const DEFAULT_TRANSITION_DURATION = 350
const MAX_TRANSITION_DURATION = 60_000

export class NativeNavigationWeb extends WebPlugin implements NativeNavigationPlugin {
  private config: NativeNavigationConfigureOptions = {
    enabled: true,
    platformStyle: "auto",
  }
  private navbar: NativeNavigationNavbarOptions = {}
  private tabbar: NativeNavigationTabbarOptions = {}
  private transitionSequence = 0
  private activeTransition: NativeNavigationTransitionResult | null = null

  async configure(options: NativeNavigationConfigureOptions = {}): Promise<void> {
    this.validateDuration(options.animationDuration, "animationDuration")
    this.config = {
      ...this.config,
      ...options,
      colors: { ...this.config.colors, ...options.colors },
      glass: { ...this.config.glass, ...options.glass },
    }
  }

  async setNavbar(options: NativeNavigationNavbarOptions): Promise<void> {
    this.navbar = {
      ...this.navbar,
      ...options,
      colors: { ...this.navbar.colors, ...options.colors },
      glass: { ...this.navbar.glass, ...options.glass },
    }
  }

  async setTabbar(options: NativeNavigationTabbarOptions): Promise<void> {
    this.tabbar = {
      ...this.tabbar,
      ...options,
      colors: { ...this.tabbar.colors, ...options.colors },
      style: { ...this.tabbar.style, ...options.style },
      glass: { ...this.tabbar.glass, ...options.glass },
    }
  }

  async beginTransition(
    options: NativeNavigationBeginTransitionOptions = {},
  ): Promise<NativeNavigationTransitionResult> {
    this.validateDuration(options.duration, "duration")
    if (this.activeTransition) {
      const interrupted = { ...this.activeTransition, duration: 0 }
      // Clear ownership before notifying. A listener is allowed to call back
      // into the plugin, and must not be able to finish the interrupted
      // session a second time while its end event is being delivered.
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
    const activeTransition = this.activeTransition
    if (!activeTransition) throw new Error("No active transition")
    if (options.id !== undefined && options.id !== activeTransition.id) {
      throw new Error("Transition id does not match the active transition")
    }
    this.validateDuration(options.duration, "duration")

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

  private validateDuration(value: number | undefined, name: string): void {
    if (
      value !== undefined &&
      (!Number.isFinite(value) || value < 0 || value > MAX_TRANSITION_DURATION)
    ) {
      throw new Error(`${name} must be a finite value between 0 and 60000 milliseconds`)
    }
  }

  private dispatchWindowEvent(name: string, detail: unknown): void {
    if (typeof window === "undefined") return
    window.dispatchEvent(new CustomEvent(`capNativeNavigation:${name}`, { detail }))
  }
}
