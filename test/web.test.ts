import { beforeEach, describe, expect, it, vi } from "vitest";

import { NativeNavigationWeb } from "../src/web";

const cssVar = (name: string) => document.documentElement.style.getPropertyValue(name);

const clearCssVars = () => {
  for (const name of [
    "--cap-native-navigation-top",
    "--cap-native-navigation-right",
    "--cap-native-navigation-bottom",
    "--cap-native-navigation-left",
    "--cap-native-navbar-height",
    "--cap-native-tabbar-height",
  ]) {
    document.documentElement.style.removeProperty(name);
  }
};

describe("NativeNavigationWeb", () => {
  let plugin: NativeNavigationWeb;

  beforeEach(() => {
    clearCssVars();
    plugin = new NativeNavigationWeb();
  });

  it("starts with both bars hidden", async () => {
    const { insets } = await plugin.configure();

    expect(insets).toEqual({
      top: 0,
      right: 0,
      bottom: 0,
      left: 0,
      navbarHeight: 0,
      tabbarHeight: 0,
    });
  });

  it("reports the navbar height once the navbar is shown", async () => {
    const { insets } = await plugin.setNavbar({ hidden: false, title: "Home" });

    expect(insets.top).toBe(44);
    expect(insets.navbarHeight).toBe(44);
    expect(insets.bottom).toBe(0);
  });

  it("writes CSS variables by default and skips them in `none` mode", async () => {
    await plugin.setNavbar({ hidden: false });
    expect(cssVar("--cap-native-navbar-height")).toBe("44px");

    clearCssVars();
    await plugin.configure({ contentInsetMode: "none" });
    expect(cssVar("--cap-native-navbar-height")).toBe("");
  });

  it("uses the floating defaults when no style is given", async () => {
    const { insets } = await plugin.setTabbar({ hidden: false, tabs: [{ id: "a" }] });

    /*
     * 49 (bar) + 10 (floating bottom gap). Upstream's `DEFAULT_TABBAR_HEIGHT`
     * shortcut is unreachable because `setTabbar` always materialises a `style`
     * object while merging, so the gap is always added. Behaviour preserved
     * deliberately — see COMPATIBILITY.md.
     */
    expect(insets.bottom).toBe(59);
    expect(insets.tabbarHeight).toBe(59);
  });

  it("derives the floating tabbar height from height + bottom gap", async () => {
    const { insets } = await plugin.setTabbar({
      hidden: false,
      style: { shape: "floating", height: 64, bottomGap: 10 },
    });

    expect(insets.bottom).toBe(74);
  });

  it("adds the center button lift for curve tabbars", async () => {
    const { insets } = await plugin.setTabbar({
      hidden: false,
      style: { shape: "curve", height: 76, centerButtonDiameter: 56 },
    });

    // 76 height + 0 default curve gap + 28 lift (half the 56pt center button).
    expect(insets.bottom).toBe(104);
  });

  it("reports zero insets while disabled but keeps the requested state", async () => {
    await plugin.setNavbar({ hidden: false });
    await plugin.setTabbar({ hidden: false });

    const disabled = await plugin.configure({ enabled: false });
    expect(disabled.insets.top).toBe(0);
    expect(disabled.insets.bottom).toBe(0);

    const enabled = await plugin.configure({ enabled: true });
    expect(enabled.insets.top).toBe(44);
    expect(enabled.insets.bottom).toBe(59);
  });

  it("merges the nested style object across calls instead of replacing it", async () => {
    await plugin.setTabbar({ hidden: false, style: { shape: "floating", height: 100 } });

    // The second call sets only bottomGap. If `style` were replaced rather than
    // merged, the height would fall back to 49 and this would be 69.
    const { insets } = await plugin.setTabbar({ style: { bottomGap: 20 } });
    expect(insets.bottom).toBe(120);
  });

  it("keeps top-level state across successive calls that omit it", async () => {
    await plugin.setTabbar({ hidden: false, colors: { tint: "#ff0000" } });

    // `hidden` is not repeated, so the spread must preserve the previous value.
    const { insets } = await plugin.setTabbar({ colors: { badgeText: "#0000ff" } });
    expect(insets.bottom).toBe(59);
  });

  it("emits safeAreaChanged to plugin listeners and to the window", async () => {
    const pluginListener = vi.fn();
    const windowListener = vi.fn();
    await plugin.addListener("safeAreaChanged", pluginListener);
    window.addEventListener("capNativeNavigation:safeAreaChanged", windowListener);

    await plugin.setNavbar({ hidden: false });

    expect(pluginListener).toHaveBeenCalledTimes(1);
    expect(pluginListener.mock.calls[0][0].insets.top).toBe(44);
    expect(windowListener).toHaveBeenCalledTimes(1);

    window.removeEventListener("capNativeNavigation:safeAreaChanged", windowListener);
  });

  it("round-trips a transition and keeps the id across begin/finish", async () => {
    const started = vi.fn();
    const ended = vi.fn();
    await plugin.addListener("transitionStart", started);
    await plugin.addListener("transitionEnd", ended);

    const begun = await plugin.beginTransition({ id: "t1", direction: "forward", duration: 120 });
    expect(begun).toEqual({ id: "t1", direction: "forward", duration: 120 });

    const finished = await plugin.finishTransition({});
    expect(finished.id).toBe("t1");
    expect(finished.direction).toBe("forward");
    expect(started).toHaveBeenCalledTimes(1);
    expect(ended).toHaveBeenCalledTimes(1);
  });

  it("overrides direction and duration on finish", async () => {
    await plugin.beginTransition({ id: "t2" });
    const finished = await plugin.finishTransition({ id: "t2", direction: "back", duration: 10 });

    expect(finished).toEqual({ id: "t2", direction: "back", duration: 10 });
  });

  it("creates a fresh transition when finishing an unknown id", async () => {
    await plugin.beginTransition({ id: "t3" });
    const finished = await plugin.finishTransition({ id: "other" });

    expect(finished.id).toBe("other");
  });

  it("uses the configured animation duration as the transition default", async () => {
    await plugin.configure({ animationDuration: 500 });
    const begun = await plugin.beginTransition({});

    expect(begun.duration).toBe(500);
  });

  it("reports `web` as the implementation version", async () => {
    await expect(plugin.getPluginVersion()).resolves.toEqual({ version: "web" });
  });
});
