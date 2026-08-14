# Compatibility notes

Why this port exists, what had to change to support Capacitor 7 alongside
Capacitor 8+, and which upstream defects were fixed on the way.

Upstream reference: [`@capgo/capacitor-native-navigation`][upstream] 8.3.0.

## 1. What actually differs between Capacitor 7 and 8

Taken from the Capacitor repository at tags `7.6.8` and `8.5.0`, not from
release notes.

|                                                     | Capacitor 7                  | Capacitor 8                                                                   | Source                                                                        |
| --------------------------------------------------- | ---------------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| iOS deployment target                               | **14.0**                     | 15.0                                                                          | `ios/Capacitor.podspec`                                                       |
| Android `minSdk`                                    | **23**                       | 24                                                                            | `android/capacitor/build.gradle`                                              |
| Android `compileSdk` / `targetSdk`                  | 35                           | 36                                                                            | same                                                                          |
| Android Gradle Plugin (app template)                | 8.7.2                        | 8.13.0                                                                        | generated `android/build.gradle`                                              |
| Gradle wrapper (app template)                       | 8.11.1                       | 8.14.3                                                                        | generated wrapper                                                             |
| Java source/target                                  | 21                           | 21                                                                            | `android/capacitor/build.gradle`                                              |
| `capacitor-swift-pm` pin written by `cap sync`      | `exact: "7.x.y"`             | `exact: "8.x.y"`                                                              | `cli/src/util/spm.ts`                                                         |
| SPM app platform                                    | `.iOS(.v14)`                 | `.iOS(.v15)`                                                                  | `ios-spm-template`                                                            |
| `com.getcapacitor.Plugin`                           | —                            | **byte-identical**                                                            | `git diff 7.6.8 8.5.0 -- .../Plugin.java` is empty                            |
| `@capacitor/core` `web-plugin.ts`, `definitions.ts` | —                            | **byte-identical**                                                            | `git diff 7.6.8 8.5.0 -- core/src/` touches only `core-plugins.ts`/`index.ts` |
| `CAPPlugin` / `CAPBridgedPlugin` / `CAPPluginCall`  | —                            | additive only (`handleWKWebViewURLAuthenticationChallenge`, two deprecations) | `git diff` of `ios/Capacitor/Capacitor/`                                      |
| `CapacitorWebView.edgeToEdgeHandler()`              | present                      | **removed**                                                                   | `android/.../CapacitorWebView.java`                                           |
| Android `adjustMarginsForEdgeToEdge` config         | present, default `"disable"` | removed                                                                       | `CapConfig.java`                                                              |

The important consequence: **the plugin API surface is unchanged**, so no
version-specific implementation forks are needed. Everything that breaks is
packaging metadata and platform floors — which is exactly what a
`peerDependencies` bump alone does not fix.

## 2. Compatibility changes

### 2.1 iOS deployment target 15.0 → 14.0 (hard install blocker)

A Capacitor 7 app's Podfile declares `platform :ios, '14.0'` and its Xcode
project uses `IPHONEOS_DEPLOYMENT_TARGET = 14.0`. CocoaPods refuses to integrate
a pod whose minimum is higher than the host target, so upstream's
`s.ios.deployment_target = '15.0'` cannot install at all. The SPM path fails the
same way: the generated app package declares `platforms: [.iOS(.v14)]` and SwiftPM
rejects a dependency that requires more.

Both `CapacitorNativeNavigationBar.podspec` and `Package.swift` now declare
14.0/`.v14`. The one iOS 15+ API upstream used unguarded, `UIColor.tintColor`
(in the experimental baked-tint path), is resolved at runtime by
`nativeNavigationDefaultTintColor()`. Every other newer API — `scrollEdgeAppearance`
(15), `setTabBarHidden` (18), `UIGlassEffect` / Liquid Glass (26) — was already
behind `if #available` and stays that way.

### 2.2 `capacitor-swift-pm` version range

`cap sync` writes `.package(url: ".../capacitor-swift-pm.git", exact: "<@capacitor/ios version>")`
into the app's generated `Package.swift`. A plugin pinned to `from: "8.0.0"`
therefore cannot resolve inside a Capacitor 7 app, and `from: "7.0.0"` cannot
resolve inside a Capacitor 8 app. This package declares the two-major range
`"7.0.0"..<"10.0.0"`, which intersects with either pin.

Verified by building a Capacitor 7 SPM app (resolves 7.6.8) and a Capacitor 8 SPM
app (resolves 8.5.0) with the same plugin sources.

### 2.3 Android `minSdk` 24 → 23, and the API-24 calls behind it

Capacitor 7's `variables.gradle` sets `minSdkVersion = 23`, and the plugin module
inherits it through `rootProject.ext`. Upstream compiles fine there but calls two
Java-8-collection APIs that only exist from **API 24**:

- `List.removeIf(...)` — `NativeNavigationPlugin.java:284` (upstream)
- `Collection.stream()` — `NativeNavigationPlugin.java:1806` (upstream), inside
  `layoutChrome()`, i.e. on **every** tabbar layout pass

Without core-library desugaring (not enabled by the Capacitor Android template),
a Capacitor 7 app running on Android 6.0 throws `NoSuchMethodError` as soon as the
tabbar is shown. Both are replaced with index loops
(`moveLastDetachedTrailingItemToEnd()`, `hasDetachedTrailingItem()`), which are
also allocation-free. The `minSdkVersion` fallback is 23 to match Capacitor 7.

### 2.4 Android build configuration

- `compileSdk` fallback is 35 (Capacitor 7's value); the app's
  `rootProject.ext.compileSdkVersion` still wins, so Capacitor 8 apps compile at 36.
- The module's own `buildscript` classpath pins AGP **8.7.2** instead of 8.13.0.
  When the module is consumed by an app, Gradle's parent-first classloading means
  the app's AGP is what is actually used — verified by building the same sources
  in an AGP 8.7.2 app and an AGP 8.13.0 app. The lower pin only affects standalone
  `cd android && ./gradlew build`, where it keeps the module buildable with the
  Gradle 8.11.1 wrapper this repository ships.
- `sourceCompatibility`/`targetCompatibility` are Java 17 rather than 21. Both
  Capacitor majors require a JDK 21 toolchain, so this is purely a lower bytecode
  floor; nothing in the sources needs Java 21 language features.
- `androidx.core` is now an explicit dependency instead of being inherited from
  `appcompat`, because `androidx.core.graphics.PathParser` (used by the SVG icon
  renderer) only became public API in core 1.7.0.
- The ProGuard rules that keep the plugin class and its `@PluginMethod`s are
  shipped as `consumerProguardFiles`, so release builds of consuming apps get
  them automatically.

### 2.5 Capacitor 7's edge-to-edge WebView margins

Capacitor 7 has `CapacitorWebView.edgeToEdgeHandler()`, which — when an app sets
`android.adjustMarginsForEdgeToEdge` to `"auto"` or `"force"` — applies the system
bar insets as **margins on the WebView**. Capacitor 8 deleted that method. Upstream
computes the reported insets as `statusBarInset + navbarHeight`, which
double-counts the status bar in that configuration.

`currentInsets()` now measures the chrome against the WebView's actual position
inside the content root (`webViewTopOffsetInRoot()` / `webViewBottomGapInRoot()`).
When the WebView is not offset — the default in Capacitor 7 and always in
Capacitor 8 — the expressions reduce to upstream's exact values, which the
runtime verification confirms (identical numbers on both majors).

### 2.6 Packaging and naming

The Capacitor CLI derives the iOS pod name, SPM package name and SPM product name
from the npm package name via `fixName()` (identical in v7 and v8):
`capacitor-native-navigation-bar` → `CapacitorNativeNavigationBar`. The podspec
filename, `Package(name:)` and `.library(name:)` all use it.
`scripts/check-wiring.mjs` asserts this, the bridge-name agreement across
JS/Swift/Java, and the platform floors, so a rename cannot silently break `cap sync`.

### 2.7 Dual-format types

`package.json` sets `"type": "module"`, which makes every emitted `.d.ts` an ESM
declaration file. Serving that same file under the `require` condition — where
the runtime file is real CommonJS — is the `attw` "FalseESM" failure, and a
CommonJS consumer on `moduleResolution: node16` gets `TS1479`. The CJS bundle
therefore ships its own `dist/plugin.d.cts` and the exports map splits the
condition:

```jsonc
"exports": {
  ".": {
    "import": { "types": "./dist/esm/index.d.ts", "default": "./dist/esm/index.js" },
    "require": { "types": "./dist/plugin.d.cts",  "default": "./dist/plugin.cjs" }
  }
}
```

`publint` and `attw` run as part of `pnpm run verify:web` so this cannot regress.
`sideEffects` is deliberately **not** declared: `registry.ts` calls
`registerPlugin()` at module scope, which also populates
`Capacitor.Plugins.NativeNavigation`, and an app that relies on that via a
side-effect-only import would break under tree shaking.

## 3. Upstream defects fixed

Each of these is reproducible from upstream's source; none change the documented
API.

| #   | Defect                                                    | Evidence                                                                                                                                                                                                                | Fix                                                                                                                    |
| --- | --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| 1   | `Stream`/`removeIf` crash on API 23                       | see §2.3                                                                                                                                                                                                                | index loops                                                                                                            |
| 2   | Navbar menu icons are never tinted                        | `applyToolbarColors` does `icon.mutate().setTint(tint)` and discards the result; `Drawable.mutate()` returns a **copy** whenever the drawable shares a `ConstantState`, which everything from `AppCompatResources` does | tint the mutated drawable and `menuItem.setIcon(tinted)`                                                               |
| 3   | `NullPointerException` on `getActivity()` during teardown | `statusBarInset()`/`navigationBarInset()` call `getActivity().getWindow()` with no null check, while `contentRoot()` right next to them does check                                                                      | `rootWindowInsets()` null-guards and falls back to the platform dimension resource                                     |
| 4   | `ensureToolbar()`/`ensureTabbar()` NPE                    | the `root == null` fallback calls `getActivity().addContentView(...)`, but `contentRoot()` returns null precisely when the activity is gone                                                                             | activity is captured and null-checked; the calls reject with `Activity unavailable`                                    |
| 5   | Tabbar layout never recomputed after rotation             | Capacitor's `BridgeActivity` declares `configChanges="orientation                                                                                                                                                       | …                                                                                                                      | screenSize"`, so the activity is **not** recreated, and nothing re-runs `layoutChrome()`; the tabbar keeps the pixel width computed for the previous orientation | an `OnLayoutChangeListener` on the content root re-runs the layout on a real size change (guarded so `setLayoutParams` cannot re-enter it) |
| 6   | Transition bitmaps accumulate                             | `beginTransition` allocates a full-screen `ARGB_8888` bitmap per transition and, for zoom, a second cropped one; neither the intermediate nor the previous snapshot is released                                         | the uncropped source is recycled once the crop exists, and `removeTransitionSnapshot()` detaches, clears and recycles  |
| 7   | A stale transition could tear down a newer one            | the completion callback captured no identity, so a late `withEndAction` removed whatever snapshot was current                                                                                                           | `removeTransitionSnapshot(root, expected)` only acts on the snapshot the caller owns; pending animations are cancelled |
| 8   | `GlassBackdropView` observer leak                         | listeners are removed via `source.getViewTreeObserver()`, but a `ViewTreeObserver` is per-window: after a detach/attach the instance differs and removal silently no-ops                                                | the registered observer is retained and unregistered from that instance, plus register/unregister on attach/detach     |
| 9   | Glass refresh throttle can stall                          | `System.currentTimeMillis()` is wall-clock and can jump backwards                                                                                                                                                       | `SystemClock.uptimeMillis()`                                                                                           |
| 10  | Native views and listeners outlive the plugin             | no `handleOnDestroy()`; chrome is added to `android.R.id.content` and never removed                                                                                                                                     | `handleOnDestroy()` detaches listeners, removes the chrome, releases the glass sources and clears state                |
| 11  | `selectableItemBackground` can throw                      | `resolveAttribute` result unused; `resourceId` 0 reaches `AppCompatResources.getDrawable`                                                                                                                               | resolution is checked; a themeless host simply gets no ripple                                                          |
| 12  | Badge shows the literal text `null`                       | `tab.has("badge")` is true for an explicit JSON `null`, and `String.valueOf(JSONObject.NULL)` is `"null"` (iOS had the same via `String(describing: NSNull())`)                                                         | `!tab.isNull("badge")` on Android and an `NSNull` check on iOS                                                         |
| 13  | Orientation notifications may never arrive                | `UIDevice.orientationDidChangeNotification` is only posted while the device is generating them, which UIKit does not guarantee                                                                                          | `beginGeneratingDeviceOrientationNotifications()` in `load()`, balanced in `deinit`                                    |
| 14  | Circular module graph in JS                               | `index.ts` re-exported `components.ts`, which reached back with `import('./index')`                                                                                                                                     | `registry.ts` owns `registerPlugin` and both import it statically                                                      |
| 15  | Custom-element attribute storms                           | one native call per attribute, with promises able to settle out of order                                                                                                                                                | syncs are coalesced into a microtask and serialized; a rejected call no longer surfaces as an unhandled rejection      |
| 16  | Dead branch in `getNativeNavigationRect`                  | both arms of the `DOMRect` check built the identical object                                                                                                                                                             | single return                                                                                                          |

Also modernised without behaviour change: `UIScreen.main.scale` →
`UIGraphicsImageRendererFormat.preferred()` (deprecated API, wrong under
multi-scene), and the redundant `#available(iOS 11)` / `Build.VERSION_CODES.LOLLIPOP`
guards were dropped since the floors are 14 and 23.

## 4. Upstream behaviour deliberately preserved

- **Web tabbar default height is 59, not 49.** `NativeNavigationWeb.setTabbar`
  always materialises a `style` object while merging, so the
  `DEFAULT_TABBAR_HEIGHT` (49) shortcut in `currentTabbarHeight()` is
  unreachable and the 10 pt floating gap is always added. The constant is dead
  code, but the returned value is observable API, so it is left alone and covered
  by a test that documents it.
- **`load()` forces edge-to-edge on Android** for the whole activity, even when
  the plugin is later disabled. Changing it would break the layout maths that the
  rest of the implementation depends on.
- **`applyTabbarColors` mutates the sticky `tintColor` field**, so a tint set once
  persists into later calls that omit `colors`. Also observable.
- **`parseColor` and `parseColorOrNull` use different fallbacks** for the dynamic
  colour tokens on API < 31. Unifying them would change resolved colours.

## 5. Tooling changes

| Upstream                 | Here                              | Why                                                                                                                                                                                 |
| ------------------------ | --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| bun + npm scripts        | pnpm                              | requested; `packageManager` is pinned                                                                                                                                               |
| ESLint + Prettier        | Oxlint + Oxfmt                    | requested; `.oxlintrc.json` enables the typescript/unicorn/import/promise plugins at `correctness`+`suspicious` = error                                                             |
| Rollup (+ `tsc` for ESM) | tsdown                            | requested; emits `dist/esm` (ESM + `.d.ts`), `dist/plugin.cjs`, and the IIFE `dist/plugin.js` with the same `capacitorNativeNavigationBar` / `capacitorExports` globals as upstream |
| —                        | publint + `@arethetypeswrong/cli` | package metadata and dual-format type resolution are linted in `verify:web`                                                                                                         |
| `@capacitor/docgen`      | removed                           | it drives the TypeScript compiler API and pins old tooling; the README documents the API directly instead                                                                           |
| no JS tests              | vitest + happy-dom                | 31 tests over the web implementation, custom elements and the zoom helpers                                                                                                          |
| 1 Swift test             | 16 Swift tests                    | tab-bar geometry, colour parsing, overlay lifting, SVG parsing, transition helpers                                                                                                  |
| 1 placeholder Java test  | 8 Java tests                      | tabbar geometry and SVG number parsing                                                                                                                                              |

The ES2017 build target is deliberate: Capacitor's minimum Android System WebView
is version 55 (`Bridge.MINIMUM_ANDROID_WEBVIEW_VERSION`, same in 7 and 8), which
predates optional chaining and nullish coalescing.

## 6. Verification performed

| Check                                                                                       | Result                                                         |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `pnpm install`                                                                              | ok (pnpm 11.9.0)                                               |
| `oxfmt --check .`                                                                           | ok, 20 files                                                   |
| `oxlint --deny-warnings`                                                                    | ok                                                             |
| `tsc --noEmit` against `@capacitor/core` **7.6.8**                                          | ok                                                             |
| `tsc --noEmit` against `@capacitor/core` **8.5.0**                                          | ok                                                             |
| `vitest run`                                                                                | 31/31                                                          |
| `tsdown` production build                                                                   | ok, ESM + CJS + IIFE + `.d.ts`                                 |
| `check-wiring`                                                                              | ok                                                             |
| `publint --strict`                                                                          | ok (one non-blocking `sideEffects` suggestion, see §2.7)       |
| `attw --pack .`                                                                             | no problems: node10, node16 from CJS, node16 from ESM, bundler |
| standalone `./gradlew clean build test`                                                     | ok, 8/8 Java tests                                             |
| `xcodebuild -scheme CapacitorNativeNavigationBar`                                           | ok                                                             |
| `xcodebuild test` on an iOS 26 simulator                                                    | 16/16                                                          |
| Capacitor **7.6.8** app, Android (AGP 8.7.2, Gradle 8.11.1, minSdk 23)                      | plugin module + full app assemble ok                           |
| Capacitor **8.5.0** app, Android (AGP 8.13.0, Gradle 8.14.3, minSdk 24, installed via pnpm) | full app assemble ok                                           |
| Capacitor **7.6.8** app, iOS via CocoaPods (target 14.0)                                    | pod install + app build ok                                     |
| Capacitor **7.6.8** app, iOS via SPM (`exact: 7.6.8`)                                       | resolve + app build ok                                         |
| Capacitor **8.5.0** app, iOS via SPM (`exact: 8.5.0`)                                       | resolve + app build ok                                         |

Runtime verification ran the same scripted scenario in all four native app
builds — plugin registration, `getPluginVersion`, `configure`, `setNavbar`,
`setTabbar` (floating and curve), CSS variable injection, `beginTransition` /
`finishTransition`, three back-to-back transitions, hide/show cycles — and every
run reported `RESULT PASS` with `safeAreaChanged`, `transitionStart` and
`transitionEnd` delivered from native. Capacitor 7 and Capacitor 8 produced
identical inset values on both platforms.

Android additionally covered rotation (landscape ⇄ portrait re-emitted
`safeAreaChanged` from the new layout listener) and a background/foreground round
trip, with no `FATAL EXCEPTION`, `NoSuchMethodError` or `NoClassDefFoundError` in
logcat.

## 7. Known limitations

- The iOS 26 Liquid Glass paths were exercised on an iOS 26 simulator only; the
  pre-26 blur fallback compiles and is behind `if #available` but was not run on
  an iOS 14/15 device.
- Android instrumentation tests are not included; the Java unit tests cover the
  pure geometry/parsing helpers, and view behaviour is covered by the emulator
  runs described above.
- The Android emulator used for runtime verification is API 36. The API-23
  `NoSuchMethodError` in §2.3 was established from the Android API levels of
  `Collection.stream` / `List.removeIf` and the merged manifest's
  `minSdkVersion="23"`, not by running an API 23 image.
- `beginTransition` without a matching `finishTransition` still leaves the WebView
  at `alpha 0.01` (upstream behaviour); there is no watchdog.

[upstream]: https://github.com/Cap-go/capacitor-native-navigation
