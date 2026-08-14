# Platform Support

Detailed platform requirements, OS-level feature availability, and build
configuration for `capacitor-native-navigation-bar`.

## Capacitor version matrix

| Capacitor | Supported | Typechecked against            |
| --------- | --------- | ------------------------------ |
| 7.x       | ✅         | `@capacitor/core` 7.6.8        |
| 8.x       | ✅         | `@capacitor/core` 8.5.0        |
| 9.x       | planned   | —                              |

`peerDependencies`: `@capacitor/core: >=7.0.0 <10.0.0`

## iOS

| Requirement                     | Value                                     |
| ------------------------------- | ----------------------------------------- |
| Deployment target               | iOS 14.0                                  |
| Xcode                           | 15 or newer                               |
| CocoaPods                       | ✅ (auto-added by `cap sync ios`)          |
| Swift Package Manager           | ✅ (range `"7.0.0"..<"10.0.0"`)            |
| Tested on                       | iOS 26 simulator                          |

### OS-level feature availability (iOS)

| Feature                                    | Minimum OS    | Fallback on older OS                    |
| ------------------------------------------ | ------------- | --------------------------------------- |
| Liquid Glass `UITabBarController`          | iOS 26        | Custom capsule with `UIGlassEffect`     |
| `UIGlassEffect` custom capsule             | iOS 26        | `UIBlurEffect` material                 |
| Scroll-edge tabbar appearance              | iOS 15        | No-op (ignored)                         |
| `UITabBar.setTabBarHidden(_:animated:)`    | iOS 18        | Manual alpha/layout hide                |
| Large title navbar style                   | iOS 11        | Standard title                          |

All newer OS paths are guarded with `if #available(iOS …)` and compile cleanly
at the iOS 14 deployment floor.

## Android

| Requirement                     | Value                                     |
| ------------------------------- | ----------------------------------------- |
| `minSdkVersion`                 | 23 (Android 6.0)                          |
| `compileSdkVersion`             | inherited from app; fallback 35           |
| `targetSdkVersion`              | inherited from app; fallback 35           |
| JDK                             | 21                                        |
| Android Gradle Plugin           | 8.7.2 (standalone); app AGP wins in app   |
| Tested on                       | API 36 emulator, AGP 8.7.2 and 8.13.0    |

### OS-level feature availability (Android)

| Feature                                           | Minimum API | Fallback                            |
| ------------------------------------------------- | ----------- | ----------------------------------- |
| `liquidGlass` — `RenderEffect` blur backdrop      | API 31 (12) | Translucent surface                 |
| Dynamic Material You color palette                | API 31 (12) | Static color                        |
| Edge-to-edge `WindowInsetsController`             | API 30 (11) | `View.setSystemUiVisibility`        |
| `WindowInsetsCompat` safe area measurement        | API 23      | ✅ always available via AndroidX     |

`load()` calls `Window.setDecorFitsSystemWindows(false)` for the whole activity
so the native bars can draw into system bar areas.

## Package format

| Entry point               | Format       | Module resolution    |
| ------------------------- | ------------ | -------------------- |
| `dist/esm/index.js`       | ESM          | `import` condition   |
| `dist/esm/index.d.ts`     | ESM types    | `import` condition   |
| `dist/plugin.cjs`         | CommonJS     | `require` condition  |
| `dist/plugin.d.cts`       | CJS types    | `require` condition  |
| `dist/plugin.js`          | IIFE / UMD   | CDN / `unpkg` field  |

Build target: **ES2017** — compatible with Capacitor's minimum Android System
WebView (version 55).

`sideEffects` is intentionally not declared: `registerPlugin()` runs at module
scope and populates `Capacitor.Plugins.NativeNavigation`; tree-shaking must not
remove the registration.

## Verified build matrix

| Scenario                                                              | Result |
| --------------------------------------------------------------------- | ------ |
| `tsc --noEmit` against `@capacitor/core` 7.6.8                        | ✅      |
| `tsc --noEmit` against `@capacitor/core` 8.5.0                        | ✅      |
| `vitest run` (31 JS tests)                                            | ✅      |
| `xcodebuild -scheme CapacitorNativeNavigationBar` (iOS build)         | ✅      |
| `xcodebuild test` on iOS 26 simulator (16 Swift tests)                | ✅      |
| `./gradlew clean build test` standalone (8 Java tests)                | ✅      |
| Capacitor 7.6.8 app — Android, AGP 8.7.2, minSdk 23                  | ✅      |
| Capacitor 8.5.0 app — Android, AGP 8.13.0, minSdk 24                 | ✅      |
| Capacitor 7.6.8 app — iOS via CocoaPods (target 14.0)                 | ✅      |
| Capacitor 7.6.8 app — iOS via SPM (`exact: 7.6.8`)                   | ✅      |
| Capacitor 8.5.0 app — iOS via SPM (`exact: 8.5.0`)                   | ✅      |
| `publint --strict`                                                    | ✅      |
| `attw --pack .` (node10, node16 CJS, node16 ESM, bundler)            | ✅      |

## Known limitations

- The iOS 26 Liquid Glass paths were exercised on an iOS 26 simulator only. The
  pre-26 blur fallback compiles and is gated behind `if #available` but was not
  verified on a physical iOS 14/15 device.
- Android instrumentation tests are not included. View behavior is covered by the
  emulator runs in the matrix above; Java unit tests cover pure geometry and
  parsing helpers.
- The API-23 `Collection.stream` / `List.removeIf` crash (both absent below
  API 24 without desugaring) was established from API-level documentation and the
  merged `minSdkVersion`, not from running an API 23 emulator image.
- `beginTransition` without a matching `finishTransition` leaves the WebView at
  `alpha 0.01` (no watchdog timeout).
