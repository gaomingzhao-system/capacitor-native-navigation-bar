/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import type {
  NativeNavigationConfigureOptions,
  NativeNavigationNavbarOptions,
  NativeNavigationTabbarOptions,
} from "./definitions"
import { NativeNavigation } from "./registry"

const parseBoolean = (value: string | null, defaultValue = false): boolean => {
  if (value === null) return defaultValue
  return value === "" || value === "true" || value === "1"
}

const normalizeAttribute = (value: string | null): string | undefined => (value ? value : undefined)

const typedAttribute = <T extends string>(element: Element, name: string): T | undefined =>
  normalizeAttribute(element.getAttribute(name)) as T | undefined

const nonNegativeFiniteNumberAttribute = (element: Element, name: string): number | undefined => {
  const value = element.getAttribute(name)
  if (value === null || value.trim() === "") return undefined
  const number = Number(value)
  return Number.isFinite(number) && number >= 0 ? number : undefined
}

const parseJsonAttribute = <T>(element: Element, name: string, fallback: T): T => {
  const value = element.getAttribute(name)
  if (!value) return fallback
  try {
    return JSON.parse(value) as T
  } catch {
    return fallback
  }
}

export function defineNativeNavigationElements(): void {
  if (typeof customElements === "undefined" || typeof HTMLElement === "undefined") return

  /*
   * Attribute changes arrive one callback per attribute. Setting several
   * attributes in the same task would otherwise fire one native call per
   * attribute, with promises that can settle out of order. Syncs are coalesced
   * into a single microtask and then serialized, so native sees one update per
   * attribute burst, in order.
   */
  abstract class NativeNavigationElement extends HTMLElement {
    private syncQueued = false
    private syncTail: Promise<void> = Promise.resolve()

    protected abstract applyState(): Promise<unknown>

    connectedCallback(): void {
      this.requestSync()
    }

    attributeChangedCallback(): void {
      if (this.isConnected) this.requestSync()
    }

    private requestSync(): void {
      if (this.syncQueued) return
      this.syncQueued = true
      this.syncTail = this.syncAfter(this.syncTail)
    }

    private async syncAfter(previous: Promise<void>): Promise<void> {
      await previous
      // Attributes are read only after yielding, so every write made in the
      // same task collapses into this one update.
      this.syncQueued = false
      if (!this.isConnected) return
      try {
        await this.applyState()
      } catch {
        // A rejected native call must not poison the queue or surface as an
        // unhandled rejection; the next attribute change retries.
      }
    }
  }

  class CapNativeNavigationProvider extends NativeNavigationElement {
    static get observedAttributes(): string[] {
      return ["enabled", "platform-style", "animation-duration", "colors", "glass"]
    }

    protected override applyState(): Promise<unknown> {
      const animationDuration = nonNegativeFiniteNumberAttribute(this, "animation-duration")
      const options: NativeNavigationConfigureOptions = {
        enabled: parseBoolean(this.getAttribute("enabled"), true),
        platformStyle:
          typedAttribute<NonNullable<NativeNavigationConfigureOptions["platformStyle"]>>(
            this,
            "platform-style",
          ) ?? "auto",
        colors: parseJsonAttribute(
          this,
          "colors",
          undefined as NativeNavigationConfigureOptions["colors"],
        ),
        glass: parseJsonAttribute(
          this,
          "glass",
          undefined as NativeNavigationConfigureOptions["glass"],
        ),
      }
      if (animationDuration !== undefined) options.animationDuration = animationDuration
      return NativeNavigation.configure(options)
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

    protected override applyState(): Promise<unknown> {
      const options: NativeNavigationNavbarOptions = {
        hidden: parseBoolean(this.getAttribute("hidden")),
        title: this.getAttribute("title") ?? undefined,
        subtitle: this.getAttribute("subtitle") ?? undefined,
        large: parseBoolean(this.getAttribute("large")),
        transparent: parseBoolean(this.getAttribute("transparent")),
        blurEffect: typedAttribute<NonNullable<NativeNavigationNavbarOptions["blurEffect"]>>(
          this,
          "blur-effect",
        ),
        backButton: {
          visible: parseBoolean(this.getAttribute("back-button")),
          title: normalizeAttribute(this.getAttribute("back-title")),
        },
        leftItems: parseJsonAttribute(this, "left-items", []),
        rightItems: parseJsonAttribute(this, "right-items", []),
        colors: parseJsonAttribute(
          this,
          "colors",
          undefined as NativeNavigationNavbarOptions["colors"],
        ),
        glass: parseJsonAttribute(
          this,
          "glass",
          undefined as NativeNavigationNavbarOptions["glass"],
        ),
        animated: parseBoolean(this.getAttribute("animated")),
      }
      return NativeNavigation.setNavbar(options)
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

    protected override applyState(): Promise<unknown> {
      const options: NativeNavigationTabbarOptions = {
        hidden: parseBoolean(this.getAttribute("hidden")),
        tabs: parseJsonAttribute(this, "tabs", []),
        selectedId: normalizeAttribute(this.getAttribute("selected-id")),
        labels: parseBoolean(this.getAttribute("labels"), true),
        labelVisibilityMode: typedAttribute<
          NonNullable<NativeNavigationTabbarOptions["labelVisibilityMode"]>
        >(this, "label-visibility-mode"),
        icons: parseBoolean(this.getAttribute("icons"), true),
        colors: parseJsonAttribute(
          this,
          "colors",
          undefined as NativeNavigationTabbarOptions["colors"],
        ),
        glass: parseJsonAttribute(
          this,
          "glass",
          undefined as NativeNavigationTabbarOptions["glass"],
        ),
        style: parseJsonAttribute(
          this,
          "style",
          undefined as NativeNavigationTabbarOptions["style"],
        ),
        blurEffect: typedAttribute<NonNullable<NativeNavigationTabbarOptions["blurEffect"]>>(
          this,
          "blur-effect",
        ),
        disableTransparentOnScrollEdge: parseBoolean(
          this.getAttribute("disable-transparent-on-scroll-edge"),
        ),
        disableIndicator: parseBoolean(this.getAttribute("disable-indicator")),
        indicatorColor: normalizeAttribute(this.getAttribute("indicator-color")),
        rippleColor: normalizeAttribute(this.getAttribute("ripple-color")),
        badgeBackgroundColor: normalizeAttribute(this.getAttribute("badge-background-color")),
        experimentalBakedTintColors: parseBoolean(
          this.getAttribute("experimental-baked-tint-colors"),
        ),
        badgeTextColor: normalizeAttribute(this.getAttribute("badge-text-color")),
        animated: parseBoolean(this.getAttribute("animated")),
      }
      return NativeNavigation.setTabbar(options)
    }
  }

  if (!customElements.get("cap-native-navigation-provider"))
    customElements.define("cap-native-navigation-provider", CapNativeNavigationProvider)
  if (!customElements.get("cap-native-navbar"))
    customElements.define("cap-native-navbar", CapNativeNavbar)
  if (!customElements.get("cap-native-tabbar"))
    customElements.define("cap-native-tabbar", CapNativeTabbar)
}
