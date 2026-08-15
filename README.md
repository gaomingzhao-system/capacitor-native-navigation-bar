# capacitor-native-navigation-bar

Native navbar, tabbar, safe-area reporting, and WebView snapshot transitions for
**Capacitor 7** apps. Ships as an **ESM-only** npm package.

The plugin renders real UIKit / Android views on top of the WebView, reports how
much of the viewport they cover (as an event and as CSS variables), and can play
a native transition over a snapshot of the WebView while JavaScript swaps the
route underneath.

> 🇯🇵 [日本語 README](./README.ja.md)

## Supported versions

|                                 | This release | Notes                                          |
| ------------------------------- | ------------ | ---------------------------------------------- |
| Capacitor                       | 7.x only     | `peerDependencies`: `@capacitor/core: ^7.0.0`  |
| Module format                   | ESM only     | no CommonJS, no IIFE/UMD, no `unpkg` bundle    |
| Node.js (to build this package) | ≥ 22.13.0    | verified on 22.23.2 and current-LTS 24.19.0    |
| TypeScript                      | 7.x          | native compiler; see [below](#typescript-7)    |
| iOS deployment target           | 15.0         | higher than Capacitor 7's own 14.0 — see below |
| Android `minSdk`                | 30 (11)      | higher than Capacitor 7's own 23 — see below   |

Version **7.2.0** is the first public npm release. The package major follows
the supported Capacitor major, so this release line supports Capacitor 7 only.

### Your app's floors must meet this plugin's floors

This plugin's iOS and Android floors are **intentionally higher** than
Capacitor 7's own defaults, for modern-OS support. A plugin's minimum may
exceed what Capacitor itself requires, but only if the **consuming app** also
meets it:

- **iOS**: the Capacitor 7 template ships `platform :ios, '14.0'` in the
  Podfile and an Xcode project deployment target of 14.0. Raise both to
  **15.0** before installing this plugin.
  - **Swift Package Manager hard-fails** on this mismatch (verified): `The
package product 'CapacitorNativeNavigationBar' requires minimum platform
version 15.0 for the iOS platform, but this target supports 14.0`.
  - **CocoaPods does not** — it happily builds a 15.0-targeted pod into a
    14.0-targeted app (per-target deployment targets are valid Xcode config).
    Raise it anyway: otherwise the app claims iOS 14 support (allowing
    installs on OS versions this plugin was never exercised on) while linking
    code that assumes iOS 15 APIs are unconditionally available below its own
    `if #available` guards.
- **Android**: the Capacitor 7 template ships `minSdkVersion = 23` in
  `android/variables.gradle`. Raise it to **30** before installing this
  plugin, or the manifest merger fails the build:
  `uses-sdk:minSdkVersion 23 cannot be smaller than version 30 declared in
library`. Also set `compileSdkVersion = 36` and use Android Gradle Plugin
  8.9.1 or newer; the default AndroidX Core 1.18.0 dependency publishes those
  consumer minimums.

## Installation

```bash
npm install capacitor-native-navigation-bar && npx cap sync
```

pnpm and bun work too; the Capacitor CLI discovers the plugin through
`package.json` in either layout.

### iOS

- Xcode 16 or newer (the Capacitor 7 toolchain requirement).
- Raise your app's iOS deployment target to 15.0 (see above) before syncing —
  required for SPM, strongly recommended for CocoaPods.
- CocoaPods: nothing else to do — `npx cap sync ios` adds
  `pod 'CapacitorNativeNavigationBar'` to the generated Podfile.
- Swift Package Manager: nothing else to do either — the package declares
  `platforms: [.iOS(.v15)]` and pins `capacitor-swift-pm` to the Capacitor 7
  major (`from: "7.0.0"`), so it resolves against whatever 7.x patch `cap
sync` pinned.
- The plugin adds its chrome to `bridge.viewController.view`. If your app
  replaces the root view controller, add the plugin's views after that.

### Android

- Use JDK 21.
- Before syncing, set `minSdkVersion = 30` and `compileSdkVersion = 36` in
  `android/variables.gradle` (see above).
- Use Android Gradle Plugin 8.9.1 or newer. This repository's standalone
  baseline is AGP 8.13.2 with Gradle 8.14.3. The module reads
  `targetSdkVersion` from the app; its standalone fallback is API 36.
- `load()` calls `Window.setDecorFitsSystemWindows(false)` so the native bars
  can draw into the system bar areas. This applies to the whole activity.

## Usage

```ts
import {
  NativeNavigation,
  beginZoomTransition,
  finishZoomTransition,
} from "capacitor-native-navigation-bar";

await NativeNavigation.configure({ animationDuration: 300 });

await NativeNavigation.setNavbar({
  title: "Library",
  backButton: { visible: true },
  rightItems: [{ id: "search", icon: { ios: { sfSymbol: "magnifyingglass" }, svg: "<svg …/>" } }],
  colors: { tint: "#0a84ff" },
});

const { insets } = await NativeNavigation.setTabbar({
  selectedId: "home",
  tabs: [
    { id: "home", title: "Home", icon: { svg: "<svg …/>" } },
    { id: "library", title: "Library", badge: 3, icon: { svg: "<svg …/>" } },
    { id: "search", title: "Search", role: "search", icon: { svg: "<svg …/>" } },
  ],
  style: { shape: "floating", height: 64, bottomGap: 10 },
});

NativeNavigation.addListener("tabSelect", ({ id }) => router.go(id));
NativeNavigation.addListener("navbarBack", () => router.back());
NativeNavigation.addListener("safeAreaChanged", ({ insets }) => console.log(insets));
```

### Insets

Every state-changing method resolves with the insets the native bars occupy, and
the same values are pushed as a `safeAreaChanged` event plus CSS variables on
`<html>` (unless `contentInsetMode: 'none'`):

```css
body {
  padding-top: var(--cap-native-navigation-top);
  padding-bottom: var(--cap-native-navigation-bottom);
}
/* also: --cap-native-navigation-left/right,
   --cap-native-navbar-height, --cap-native-tabbar-height */
```

The values are CSS pixels/native points on every platform, independent of the
Android display density. Switching to `contentInsetMode: "none"` removes any
variables written by an earlier `"css"` configuration.

`configure`, `setNavbar`, and `setTabbar` use patch semantics: omitted fields
retain their previous values, including nested `colors`, `glass`, and `style`
fields. Pass an explicit empty array or value when you intend to clear state.

### Native transitions

Wrap a route change so native animates over a snapshot of the old page:

```ts
await NativeNavigation.beginTransition({ direction: "forward" });
await router.push("/details");
await NativeNavigation.finishTransition({ direction: "forward" });
```

`beginZoomTransition(element)` / `finishZoomTransition(element)` do the same for
Apple-Zoom-style transitions, taking element rects in viewport coordinates.

Only the active transition can be finished. A mismatched explicit transition
id is rejected without disturbing the active snapshot.

If `finishTransition` is never called — an app bug, an exception between the
two calls, or the app being backgrounded mid-transition — both platforms
self-heal: a watchdog timer force-restores the WebView shortly after the
requested duration elapses, and Android/iOS both force-restore it immediately
if the app is backgrounded first. A `transitionEnd` event still fires so
listeners relying on a matching pair aren't left hanging. See
[PLATFORM.md](./PLATFORM.md) for details.

### Custom elements

`defineNativeNavigationElements()` registers `<cap-native-navigation-provider>`,
`<cap-native-navbar>` and `<cap-native-tabbar>`, which mirror their attributes
onto the plugin calls. Attribute writes made in the same task are coalesced into
one native call.

## API

| Method                       | Returns                       | Notes                                                                                                     |
| ---------------------------- | ----------------------------- | --------------------------------------------------------------------------------------------------------- |
| `configure(options?)`        | `{ insets }`                  | Global enable/disable, inset mode, default animation duration, shared colors and glass.                   |
| `setNavbar(options)`         | `{ insets }`                  | Title, subtitle, back button, left/right items, colors, blur/glass, large title.                          |
| `setTabbar(options)`         | `{ insets }`                  | Tabs, selection, labels/icons, badges, colors, `floating`/`curve` shape, detached trailing `search` role. |
| `beginTransition(options?)`  | `{ id, direction, duration }` | Snapshots the WebView and hides the live view.                                                            |
| `finishTransition(options?)` | `{ id, direction, duration }` | Animates the snapshot away. Directions: `forward`, `back`, `root`, `tab`, `zoom`, `none`.                 |
| `getPluginVersion()`         | `{ version }`                 | `native` on iOS/Android, `web` on the web fallback.                                                       |

Events: `navbarBack`, `navbarItemTap`, `tabSelect`, `safeAreaChanged`,
`transitionStart`, `transitionEnd`. Each is also dispatched on `window` as
`capNativeNavigation:<event>`.

Full option and event types live in
[`src/definitions.ts`](./src/definitions.ts) and ship as `dist/index.d.ts`.

## Platform behavior

- **iOS 26+** uses the system Liquid Glass `UITabBarController` for floating tab
  bars, and `UIGlassEffect` for the custom capsule. iOS 15–25 fall back to
  `UIBlurEffect` materials — the whole Liquid Glass path is behind runtime
  `if #available` checks, so it compiles and runs cleanly at the iOS 15 floor.
- **Android 12+** renders the `liquidGlass` effect with a `RenderEffect` blur of
  the WebView behind the bars. Android 11 uses a translucent surface fallback.
- Icons accept inline SVG (rendered natively on both platforms), SF Symbols and
  bundled image/drawable names.

See [PLATFORM.md](./PLATFORM.md) for the full platform and OS-feature support matrix.

## TypeScript 7

This package is typechecked and built with the **native** TypeScript 7
compiler (`typescript@^7.0.2`), which no longer exposes the classic in-process
JS Compiler API (`ts.createProgram`, `ts.transpileModule`, etc. are gone —
`require("typescript")` now only exposes a version string and a set of new
low-level `typescript/unstable/*` AST APIs; the real compiler ships as a
platform-specific native binary, e.g. `@typescript/typescript-darwin-arm64`).

This matters for anyone extending this package's tooling: `tsdown`'s
declaration bundler (`rolldown-plugin-dts`) already detects TypeScript 7 and
spawns its native `tsc` binary instead of calling the old API, so declaration
generation works unmodified — verified by this repository's own build. Tools
that still hard-depend on the classic API (e.g. `ts-morph`, `vue-tsc` in some
modes) would need their own TypeScript 7 support before they could be added
here; none are currently used by this package.

`tsdown` currently prints `TypeScript 7.0 does not yet have a stable API and is
experimental. Some options will be unavailable.` during the build. This is
expected and does not affect the produced output — verified by inspecting
`dist/index.d.ts` and by the `attw`/`publint` checks in `verify:web`.

## Development

```bash
pnpm install
pnpm run lint      # oxfmt --check, oxlint, tsc (TypeScript 7), wiring check
pnpm run test      # vitest
pnpm run build     # tsdown -> dist/index.js + dist/index.d.ts (ESM only)
pnpm run check:package  # publint --strict + attw --pack . --profile esm-only
pnpm run verify:ios      # xcodebuild -scheme CapacitorNativeNavigationBar
pnpm run verify:android  # cd android && ./gradlew clean build test
```

`pnpm run verify:ios:test` runs the Swift unit tests on an iOS Simulator.

## Versioning

Version **7.2.0** is the first public release of
`capacitor-native-navigation-bar` on npm. No earlier `1.x` or `2.x` package
version exists under this package name. The major version intentionally tracks
the supported Capacitor major: `7.x` releases support Capacitor 7, while future
Capacitor 8 support will use a separate `8.x` release line.

## Technical comparison with [`@capgo/capacitor-native-navigation`](https://github.com/Cap-go/capacitor-native-navigation)

The table compares this package with Cap-go 8.3.0 and lists build and native
implementation differences only.

| Area                       | This package                                                                                                        | Cap-go package                                                                            |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Capacitor baseline         | Capacitor 7 only (`@capacitor/core: ^7.0.0`)                                                                        | Capacitor 8+ peer range (`@capacitor/core: >=8.0.0`), developed against 8.x               |
| JavaScript output          | ESM only through `dist/index.js`                                                                                    | ESM, CommonJS, and IIFE/UMD through `module`, `main`, and `unpkg`                         |
| Build toolchain            | TypeScript 7 native compiler, `tsdown`, pnpm 11.9, Node.js 22.13+                                                   | TypeScript 5.9, `tsc`, Rollup, Bun scripts, Node.js 22+                                   |
| iOS SwiftPM dependency     | `capacitor-swift-pm` from `7.0.0`; product `CapacitorNativeNavigationBar`                                           | `capacitor-swift-pm` from `8.0.0`; product `CapgoCapacitorNativeNavigation`               |
| Android build baseline     | Fallback SDK 36, AGP 8.13.2, Gradle 8.14.3, Java 21 language/bytecode                                               | Fallback SDK 36, AGP 8.13.0, Gradle 8.14.3, Java 21 bytecode                              |
| Android minimum SDK        | Hard-enforced `minSdkVersion 30`                                                                                    | Uses the host `minSdkVersion` when supplied; fallback is 24                               |
| Transition recovery        | iOS and Android watchdog plus immediate recovery when the app is backgrounded                                       | No equivalent recovery path in the current native implementation                          |
| Android resize and cleanup | Re-layouts on content-root size changes, removes native views/listeners on destroy, and recycles transition bitmaps | No corresponding root-size observer, teardown path, or explicit transition-bitmap recycle |

## License

MPL-2.0. See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).
