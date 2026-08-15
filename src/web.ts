/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { WebPlugin } from "@capacitor/core";

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
} from "./definitions";

const DEFAULT_NAVBAR_HEIGHT = 44;
const DEFAULT_TABBAR_HEIGHT = 64;
const DEFAULT_TABBAR_BOTTOM_GAP = 10;
const DEFAULT_TRANSITION_DURATION = 350;
const MAX_TRANSITION_DURATION = 60_000;
const CSS_INSET_VARIABLES = [
  "--cap-native-navigation-top",
  "--cap-native-navigation-right",
  "--cap-native-navigation-bottom",
  "--cap-native-navigation-left",
  "--cap-native-navbar-height",
  "--cap-native-tabbar-height",
] as const;

export class NativeNavigationWeb extends WebPlugin implements NativeNavigationPlugin {
  private config: NativeNavigationConfigureOptions = {
    contentInsetMode: "css",
    enabled: true,
    platformStyle: "auto",
  };
  private navbar: NativeNavigationNavbarOptions = {};
  private tabbar: NativeNavigationTabbarOptions = {};
  private hasNavbarState = false;
  private hasTabbarState = false;
  private transitionSequence = 0;
  private activeTransition: NativeNavigationTransitionResult | null = null;

  async configure(
    options: NativeNavigationConfigureOptions = {},
  ): Promise<NativeNavigationInsetsResult> {
    this.validateDuration(options.animationDuration, "animationDuration");
    this.config = {
      ...this.config,
      ...options,
      colors: { ...this.config.colors, ...options.colors },
      glass: { ...this.config.glass, ...options.glass },
    };
    return this.applyInsets();
  }

  async setNavbar(options: NativeNavigationNavbarOptions): Promise<NativeNavigationInsetsResult> {
    this.navbar = {
      ...this.navbar,
      ...options,
      colors: { ...this.navbar.colors, ...options.colors },
      glass: { ...this.navbar.glass, ...options.glass },
    };
    this.hasNavbarState = true;
    return this.applyInsets();
  }

  async setTabbar(options: NativeNavigationTabbarOptions): Promise<NativeNavigationInsetsResult> {
    this.tabbar = {
      ...this.tabbar,
      ...options,
      colors: { ...this.tabbar.colors, ...options.colors },
      style: { ...this.tabbar.style, ...options.style },
      glass: { ...this.tabbar.glass, ...options.glass },
    };
    this.hasTabbarState = true;
    return this.applyInsets();
  }

  async beginTransition(
    options: NativeNavigationBeginTransitionOptions = {},
  ): Promise<NativeNavigationTransitionResult> {
    this.validateDuration(options.duration, "duration");
    if (this.activeTransition) {
      const interrupted = { ...this.activeTransition, duration: 0 };
      // Clear ownership before notifying. A listener is allowed to call back
      // into the plugin, and must not be able to finish the interrupted
      // session a second time while its end event is being delivered.
      this.activeTransition = null;
      this.notifyListeners("transitionEnd", interrupted);
      this.dispatchWindowEvent("transitionEnd", interrupted);
    }
    const transition = this.createTransition(options.id, options.direction, options.duration);
    this.activeTransition = transition;
    this.notifyListeners("transitionStart", transition);
    this.dispatchWindowEvent("transitionStart", transition);
    return transition;
  }

  async finishTransition(
    options: NativeNavigationFinishTransitionOptions = {},
  ): Promise<NativeNavigationTransitionResult> {
    const activeTransition = this.activeTransition;
    if (!activeTransition) throw new Error("No active transition");
    if (options.id !== undefined && options.id !== activeTransition.id) {
      throw new Error("Transition id does not match the active transition");
    }
    this.validateDuration(options.duration, "duration");

    const transition = {
      ...activeTransition,
      direction: options.direction ?? activeTransition.direction,
      duration: options.duration ?? activeTransition.duration,
    };

    this.activeTransition = null;
    this.notifyListeners("transitionEnd", transition);
    this.dispatchWindowEvent("transitionEnd", transition);
    return transition;
  }

  async getPluginVersion(): Promise<PluginVersionResult> {
    return { version: "web" };
  }

  private createTransition(
    id: string | undefined,
    direction: NativeNavigationTransitionDirection = "forward",
    duration = this.config.animationDuration ?? DEFAULT_TRANSITION_DURATION,
  ): NativeNavigationTransitionResult {
    return { id: id ?? this.nextTransitionId(), direction, duration };
  }

  private nextTransitionId(): string {
    this.transitionSequence += 1;
    return `transition-${Date.now()}-${this.transitionSequence}`;
  }

  private validateDuration(value: number | undefined, name: string): void {
    if (
      value !== undefined &&
      (!Number.isFinite(value) || value < 0 || value > MAX_TRANSITION_DURATION)
    ) {
      throw new Error(`${name} must be a finite value between 0 and 60000 milliseconds`);
    }
  }

  private currentTabbarHeight(): number {
    const style = this.tabbar.style;
    const shape = style?.shape ?? "floating";
    const defaultHeight = shape === "curve" ? 76 : DEFAULT_TABBAR_HEIGHT;
    const height = style?.height ?? defaultHeight;
    const bottomGap = style?.bottomGap ?? (shape === "curve" ? 0 : DEFAULT_TABBAR_BOTTOM_GAP);
    const centerButtonLift =
      shape === "curve" ? (style?.centerButtonLift ?? (style?.centerButtonDiameter ?? 56) / 2) : 0;
    return Math.ceil(height + bottomGap + centerButtonLift);
  }

  private hasVisibleTabItems(): boolean {
    const selectedId = this.tabbar.selectedId;
    return (this.tabbar.tabs ?? []).some((tab) => tab.hidden !== true || tab.id === selectedId);
  }

  private applyInsets(): NativeNavigationInsetsResult {
    const enabled = this.config.enabled !== false;
    const navbarVisible = enabled && this.hasNavbarState && this.navbar.hidden !== true;
    const tabbarVisible =
      enabled && this.hasTabbarState && this.tabbar.hidden !== true && this.hasVisibleTabItems();
    const tabbarHeight = tabbarVisible ? this.currentTabbarHeight() : 0;
    const insets: NativeNavigationInsets = {
      top: navbarVisible ? DEFAULT_NAVBAR_HEIGHT : 0,
      right: 0,
      bottom: tabbarHeight,
      left: 0,
      navbarHeight: navbarVisible ? DEFAULT_NAVBAR_HEIGHT : 0,
      tabbarHeight,
    };

    if (typeof document !== "undefined") {
      const root = document.documentElement;
      if (this.config.contentInsetMode === "none") {
        for (const name of CSS_INSET_VARIABLES) root.style.removeProperty(name);
      } else {
        root.style.setProperty("--cap-native-navigation-top", `${insets.top}px`);
        root.style.setProperty("--cap-native-navigation-right", `${insets.right}px`);
        root.style.setProperty("--cap-native-navigation-bottom", `${insets.bottom}px`);
        root.style.setProperty("--cap-native-navigation-left", `${insets.left}px`);
        root.style.setProperty("--cap-native-navbar-height", `${insets.navbarHeight}px`);
        root.style.setProperty("--cap-native-tabbar-height", `${insets.tabbarHeight}px`);
      }
    }

    const event = { insets };
    this.notifyListeners("safeAreaChanged", event);
    this.dispatchWindowEvent("safeAreaChanged", event);
    return { insets };
  }

  private dispatchWindowEvent(name: string, detail: unknown): void {
    if (typeof window === "undefined") return;
    window.dispatchEvent(new CustomEvent(`capNativeNavigation:${name}`, { detail }));
  }
}
