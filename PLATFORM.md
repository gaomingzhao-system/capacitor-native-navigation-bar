# Platform Support

Detailed platform requirements, OS-level feature availability, and build
configuration for `capacitor-native-navigation-bar`.

## Capacitor version matrix

| Capacitor | Supported | Typechecked against     |
| --------- | --------- | ----------------------- |
| 7.x       | ✅        | `@capacitor/core` 7.6.8 |
| 8.x       | ❌        | not in this release     |

`peerDependencies`: `@capacitor/core: ^7.0.0` (i.e. `>=7.0.0 <8.0.0`).
Capacitor 8 support is planned as a separate future release, not a range
this package spans.

## Module format

This package is **ESM only**:

| Entry point       | Format    | Resolution                            |
| ----------------- | --------- | ------------------------------------- |
| `dist/index.js`   | ESM       | `main` / `module` / `exports.default` |
| `dist/index.d.ts` | ESM types | `exports.types`                       |

There is no CommonJS build, no `.cjs`/`.cts`/`.d.cts` output, and no IIFE/UMD
CDN bundle (`unpkg` field removed). A `require("capacitor-native-navigation-bar")`
from a CommonJS file will fail as expected for a pure-ESM package; use a
dynamic `import()` instead.

`sideEffects` is intentionally **not** declared in `package.json`.
`registerPlugin()` in `src/registry.ts` runs at module scope and populates
`Capacitor.Plugins.NativeNavigation`; declaring `sideEffects: false` without
restructuring that registration would let an aggressive bundler tree-shake it
out of an app that never directly references the `NativeNavigation` import
binding. `publint` flags the missing field as a tree-shaking suggestion; it is
accepted deliberately, not an oversight.

Build target: **ES2020** for the runtime bundle. This matches the plugin's iOS
15 / Android 11 runtime floors while keeping the published JavaScript usable
without depending on newer ES2021 APIs.

## Node.js

| Requirement | Value                                               |
| ----------- | --------------------------------------------------- |
| Minimum     | 22.13.0                                             |
| Verified on | 22.23.2 and 24.19.0 (current active LTS, "Krypton") |

Node 22 LTS ("Jod") itself started at 22.11.0, but the pinned `packageManager`
(`pnpm@11.9.0`) refuses to run below **22.13.0** (`ERR_PNPM_UNSUPPORTED_ENGINE`
/ a hard `This version of pnpm requires at least Node.js v22.13` check) —
confirmed by actually running `pnpm` against a real 22.11.0 install in this
repository's dev environment. The floor here is 22.13.0, the lowest version
that is actually required, per the "if a dependency requires a later patch,
document why" policy.

`.node-version` pins the floor for local tooling (`nvm`, `fnm`, `volta`,
`actions/setup-node`'s `node-version-file`). `@types/node` is pinned to the
`22.x` line so published declarations don't imply Node APIs newer than the
declared floor.

## TypeScript

| Requirement | Value                                                           |
| ----------- | --------------------------------------------------------------- |
| Compiler    | TypeScript 7.x (native compiler, not a JS-API-compatible build) |
| Verified on | 7.0.2 (`latest` npm dist-tag at time of writing)                |

See [README.md § TypeScript 7](./README.md#typescript-7) for what changed in
the compiler itself and how the build tooling (`tsdown` / `rolldown-plugin-dts`)
adapts to it.

## iOS

| Requirement           | Value                                                                       |
| --------------------- | --------------------------------------------------------------------------- |
| Deployment target     | 15.0 (this plugin's own floor; Capacitor 7's own floor is 14.0 — see below) |
| Xcode                 | 16 or newer (Capacitor 7 requirement)                                       |
| CocoaPods             | ✅ (auto-added by `cap sync ios`)                                           |
| Swift Package Manager | ✅ (`capacitor-swift-pm` pinned `from: "7.0.0"`)                            |
| Tested on             | iOS 26 simulator                                                            |

Because this plugin's deployment target (15.0) is higher than Capacitor 7's
own (14.0), an app still on the Capacitor 7 template default should raise its
own Podfile `platform :ios` line and Xcode project deployment target to 15.0
before installing this plugin — see the main [README.md](./README.md).

This is enforced differently by each dependency manager (verified by building
both ways):

- **Swift Package Manager hard-fails** the build: `The package product
'CapacitorNativeNavigationBar' requires minimum platform version 15.0 for
the iOS platform, but this target supports 14.0`.
- **CocoaPods does not fail** — `pod install` and `xcodebuild` both succeed
  with the pod's own target at 15.0 while the app stays at 14.0 (Xcode allows
  a dependency's deployment target to exceed its umbrella app's). Raising it
  is still the right move: otherwise the app's own Info.plist/App Store
  metadata claims iOS 14 support while linking code whose `if #available`
  guards assume iOS 15 is always present below them.

### OS-level feature availability (iOS)

| Feature                                 | Minimum OS | Fallback on older OS                |
| --------------------------------------- | ---------- | ----------------------------------- |
| Liquid Glass `UITabBarController`       | iOS 26     | Custom capsule with `UIGlassEffect` |
| `UIGlassEffect` custom capsule          | iOS 26     | `UIBlurEffect` material             |
| `UITabBar.setTabBarHidden(_:animated:)` | iOS 18     | Manual alpha/layout hide            |

All of the above are guarded with `if #available(iOS …)` and compile cleanly
at the iOS 15 deployment floor. (Scroll-edge tabbar appearance and large-title
navbar style, both iOS 15 and iOS 11 features respectively, are now
unconditional — the floor already guarantees them.)

## Android

| Requirement           | Value                                                                         |
| --------------------- | ----------------------------------------------------------------------------- |
| `minSdkVersion`       | 30 / Android 11 (this plugin's own hard floor; Capacitor 7's own floor is 23) |
| `compileSdkVersion`   | inherited from app; standalone fallback 36                                    |
| `targetSdkVersion`    | inherited from app; standalone fallback 36                                    |
| JDK / Java bytecode   | 21                                                                            |
| Gradle                | 8.14.3                                                                        |
| Android Gradle Plugin | 8.13.2 (standalone build; an embedding app provides its root build toolchain) |
| AndroidX              | AppCompat 1.8.0, Core 1.18.0, Test JUnit 1.3.0, Espresso 3.7.0                |

Unlike `compileSdkVersion`/`targetSdkVersion` (which follow
`project.hasProperty('…') ? rootProject.ext.… : fallback`, i.e. the host app's
value silently wins if it declares one), `minSdkVersion` in this module's
`build.gradle` is a **hard-coded `30`**, not conditional on the app. This makes
the documented Android 11 floor enforceable instead of silently accepting an
embedding app's lower value. A hand-written
`<uses-sdk android:minSdkVersion="30">` in this module's own
`AndroidManifest.xml` doesn't survive either — AGP regenerates the module's
merged manifest from `defaultConfig.minSdkVersion` before merging it upward,
overwriting a manually-declared tag with the same (app-inherited) value.

With the hard-coded value, an app still on the Capacitor 7 template default of
`minSdkVersion = 23` in `variables.gradle` now genuinely fails to build:
`uses-sdk:minSdkVersion 23 cannot be smaller than version 30 declared in
library`. Consuming apps must set their own floor to 30 before syncing.

The default AndroidX set also makes **`compileSdkVersion = 36` and Android
Gradle Plugin 8.9.1 or newer consumer requirements**. Core 1.18.0 is the newest
stable Core release whose published AAR metadata accepts compileSdk 36 and AGP
8.9.1; Core 1.19.0 requires compileSdk 37 and AGP 9.1, so it is intentionally
not used by this SDK 36 baseline. The standalone build pins AGP 8.13.2 and
Gradle 8.14.3. `targetSdkVersion` remains controlled by the consuming app.

### OS-level feature availability (Android)

| Feature                                      | Minimum API | Fallback on Android 11 |
| -------------------------------------------- | ----------- | ---------------------- |
| `liquidGlass` — `RenderEffect` blur backdrop | API 31 (12) | Translucent surface    |
| Dynamic Material You color palette           | API 31 (12) | Static color           |
| Edge-to-edge / typed `WindowInsets`          | API 30 (11) | Baseline API           |

`load()` calls `Window.setDecorFitsSystemWindows(false)` for the whole activity
so the native bars can draw into system bar areas.

## Confirmed defects fixed in this release

- **Android unit mismatch.** Native layout values and `WindowInsets` are
  physical pixels. They are now converted to dp/CSS pixels before crossing the
  JavaScript bridge, while zoom rectangles and radii travel in the opposite
  direction before native cropping and animation. This keeps insets and zoom
  geometry correct at every display density.
- **Transition races.** Each platform owns one active transition session.
  Starting a replacement safely recovers the old session, a mismatched finish
  id is rejected, the watchdog is re-armed for the finish duration, and stale
  animation callbacks cannot clean up a newer snapshot or emit duplicate end
  events.
- **Patch-state and event parity.** Native `configure`, `setNavbar`, and
  `setTabbar` now preserve omitted state like the Web implementation. Shared
  color/glass defaults and every documented window event are applied on both
  native platforms.
- **Android 11 / Java 21 baseline.** The hard `minSdkVersion 30` and Java 21
  source/target settings now match this release's documented support policy.
- **iOS CocoaPods deployment-target mismatch was assumed to fail the build; it
  does not.** Documentation from an earlier release claimed CocoaPods refuses
  to install a pod whose deployment target exceeds the app's. Verified by
  actually building a Capacitor 7 app whose Podfile was left at 14.0 against
  this plugin's 15.0 podspec: `pod install` and `xcodebuild` both succeed.
  Swift Package Manager, tested the same way, does hard-fail. Documentation
  now describes each dependency manager's real, verified behavior instead of
  an assumption.

## Transition lifecycle safety net

`beginTransition` hides the live WebView behind a snapshot (`alpha 0.01`)
until `finishTransition` restores it. Two situations can otherwise leave the
WebView effectively invisible indefinitely:

1. **The app never calls `finishTransition`** (a routing bug, an exception
   thrown between the two calls). Both platforms arm a watchdog timer when
   `beginTransition` runs. Its delay is the active animation duration plus a
   four-second grace period. `finishTransition` re-arms it using the finish
   duration, then completion cancels it. If it does fire, it restores the
   WebView and emits `transitionEnd` with duration `0` exactly once.
2. **The app is backgrounded mid-transition** (`UIApplication.didEnterBackgroundNotification`
   on iOS, `handleOnPause()` on Android). Nothing the user is watching matters
   once the app isn't visible, so both platforms force-complete any active
   transition immediately rather than waiting for the watchdog delay.

This is a defensive recovery mechanism, not a new public API — no options or
return types changed. An explicit finish id that does not match the active
session is rejected without disturbing that session.

## Release verification

Every pull request must pass the repository's three CI jobs before release:

| Job     | Release gate                                                                                        |
| ------- | --------------------------------------------------------------------------------------------------- |
| Web     | formatting, lint, TypeScript check, wiring policy, Vitest, ES2020 build, `publint`, and `attw`      |
| iOS     | Swift Package Manager generic-device build plus XCTest on the newest available iPhone simulator     |
| Android | standalone `./gradlew clean build test` with JDK 21, SDK 36, AGP 8.13.2, and the Java/JUnit sources |

The CI matrix validates the package and standalone native modules. It does not
replace integration testing inside every consuming app. In particular, test a
host after raising its Android min/compile SDK and AGP values, and test both
CocoaPods and Swift Package Manager if the app distributes through both paths.

## Known limitations

- The iOS 26 Liquid Glass paths need final validation on physical hardware. The
  iOS 15–25 blur fallback is gated behind `if #available`, but the CI simulator
  job does not provide full device-level visual validation for every supported
  OS release.
- Android instrumentation tests are not included. Java unit tests cover pure
  unit conversion, geometry, and parsing helpers.
  Full transition-session and lifecycle behavior still needs a live
  `Bridge`/`Activity` (Android) or `CAPBridge` (iOS), which the current unit
  targets do not construct.
- CocoaPods host integration is not exercised by CI; the iOS CI job builds and
  tests the Swift Package Manager product.
- On iOS 26, system-tab hosting temporarily reparents WebView overlay views.
  Complex host-provided Auto Layout constraints should be tested in the
  consuming app when switching between system and custom tabbar shapes.
