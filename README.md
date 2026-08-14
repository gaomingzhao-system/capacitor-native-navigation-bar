# capacitor-native-navigation-bar

Native navbar, tabbar, safe-area reporting and WebView snapshot transitions for
Capacitor apps — **on Capacitor 7 as well as Capacitor 8+**.

The plugin renders real UIKit / Android views on top of the WebView, reports how
much of the viewport they cover (as an event and as CSS variables), and can play
a native transition over a snapshot of the WebView while JavaScript swaps the
route underneath.

This is a port of [`@capgo/capacitor-native-navigation`][upstream] (MPL-2.0) with
the compatibility work needed to make it installable and correct on Capacitor 7.
See [COMPATIBILITY.md](./COMPATIBILITY.md) for the full list of changes and the
evidence behind each one.

## Supported versions

|                                 | Minimum | Verified against                        |
| ------------------------------- | ------- | --------------------------------------- |
| Capacitor                       | 7.0.0   | 7.6.8 and 8.5.0                         |
| iOS deployment target           | 14.0    | iOS 26 simulator, CocoaPods **and** SPM |
| Android minSdk                  | 23      | API 36 emulator, AGP 8.7.2 and 8.13.0   |
| Node (for building the package) | 20.19   | 24                                      |

`peerDependencies` is `@capacitor/core: >=7.0.0 <10.0.0`. Both majors are
typechecked in CI-style scripts (`pnpm run typecheck`) against real
`@capacitor/core` 7 and 8 type definitions.

## Installation

```bash
npm install capacitor-native-navigation-bar && npx cap sync
```

pnpm and bun work too; the Capacitor CLI discovers the plugin through
`package.json` in either layout.

### iOS

- Xcode 15 or newer.
- CocoaPods: nothing to do — `npx cap sync ios` adds
  `pod 'CapacitorNativeNavigationBar'` to the generated Podfile.
- Swift Package Manager: nothing to do either — the package declares
  `platforms: [.iOS(.v14)]` and a `capacitor-swift-pm` range that spans
  Capacitor 7 and 8, so it resolves against whichever version `cap sync` pinned.
- The plugin adds its chrome to `bridge.viewController.view`. If your app
  replaces the root view controller, add the plugin's views after that.

### Android

- JDK 21 (the same JDK Capacitor 7 and 8 require).
- Nothing to configure: the module reads `compileSdkVersion`, `minSdkVersion`
  and `targetSdkVersion` from the app's `variables.gradle`, falling back to
  Capacitor 7's values when built standalone.
- `load()` calls `Window.setDecorFitsSystemWindows(false)` so the native bars can
  draw into the system bar areas. This is inherited from upstream and applies to
  the whole activity.

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

### Native transitions

Wrap a route change so native animates over a snapshot of the old page:

```ts
await NativeNavigation.beginTransition({ direction: "forward" });
await router.push("/details");
await NativeNavigation.finishTransition({ direction: "forward" });
```

`beginZoomTransition(element)` / `finishZoomTransition(element)` do the same for
Apple-Zoom-style transitions, taking element rects in viewport coordinates.

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
[`src/definitions.ts`](./src/definitions.ts) and ship as `dist/esm/index.d.ts`.

## Platform behaviour

- **iOS 26+** uses the system Liquid Glass `UITabBarController` for floating tab
  bars, and `UIGlassEffect` for the custom capsule. Earlier iOS falls back to
  `UIBlurEffect` materials — the whole Liquid Glass path is behind runtime
  `if #available` checks, so it compiles and runs at the iOS 14 floor.
- **Android 12+** renders the `liquidGlass` effect with a `RenderEffect` blur of
  the WebView behind the bars. Android 11 and older get a translucent surface.
- Icons accept inline SVG (rendered natively on both platforms), SF Symbols and
  bundled image/drawable names.

## Differences from the upstream Capgo plugin

Migration is an import-path change; the bridge name (`NativeNavigation`), method
names, option shapes, return types and event names are unchanged.

```diff
- import { NativeNavigation } from '@capgo/capacitor-native-navigation'
+ import { NativeNavigation } from 'capacitor-native-navigation-bar'
```

Because both packages register the same `NativeNavigation` bridge name, do not
install them side by side.

Everything else — the lowered platform floors, the fixed defects, the tooling
swap and the two deliberate behaviour preservations — is documented in
[COMPATIBILITY.md](./COMPATIBILITY.md).

## Development

```bash
pnpm install
pnpm run lint      # oxfmt --check, oxlint, tsc (against @capacitor/core 7 and 8), wiring check
pnpm run test      # vitest
pnpm run build     # tsdown -> dist/esm, dist/plugin.cjs, dist/plugin.js
pnpm run verify:ios      # xcodebuild -scheme CapacitorNativeNavigationBar
pnpm run verify:android  # cd android && ./gradlew clean build test
```

`xcodebuild test -scheme CapacitorNativeNavigationBar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
runs the Swift unit tests.

## License

MPL-2.0, inherited from the upstream project. See [LICENSE](./LICENSE) and
[NOTICE](./NOTICE) — every derived source file keeps the MPL Exhibit A header and
the attribution to Capgo.

[upstream]: https://github.com/Cap-go/capacitor-native-navigation
