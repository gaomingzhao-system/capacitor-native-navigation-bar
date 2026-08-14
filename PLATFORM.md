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

Build target: **ES2017** for the runtime bundle — unrelated to the Node.js
version used to build the package, and required by Capacitor's minimum
supported Android System WebView (version 55, which predates optional
chaining and nullish coalescing).

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
| Xcode                 | 15 or newer                                                                 |
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

| Requirement           | Value                                                                                 |
| --------------------- | ------------------------------------------------------------------------------------- |
| `minSdkVersion`       | 24 / Android 7.0 (this plugin's own floor; Capacitor 7's own floor is 23 — see below) |
| `compileSdkVersion`   | inherited from app; fallback 35 (Capacitor 7's default)                               |
| `targetSdkVersion`    | inherited from app; fallback 35                                                       |
| JDK                   | 21                                                                                    |
| Android Gradle Plugin | 8.7.2 (standalone build only; the app's own AGP wins when embedded)                   |
| Tested on             | API 36 emulator, minSdk raised to 24                                                  |

Unlike `compileSdkVersion`/`targetSdkVersion` (which follow
`project.hasProperty('…') ? rootProject.ext.… : fallback`, i.e. the host app's
value silently wins if it declares one), `minSdkVersion` in this module's
`build.gradle` is a **hard-coded `24`**, not conditional on the app. This was
a deliberate correction made after verifying the conditional pattern
empirically: it lets an embedding app's lower value win with _no build
error at all_ (Gradle simply compiles this module at the app's value), which
would silently reintroduce the exact API-24-without-desugaring crash this
plugin fixed (see confirmed defects below) for any Capacitor 7 app that
didn't happen to already declare `minSdkVersion = 24`. A hand-written
`<uses-sdk android:minSdkVersion="24">` in this module's own
`AndroidManifest.xml` doesn't survive either — AGP regenerates the module's
merged manifest from `defaultConfig.minSdkVersion` before merging it upward,
overwriting a manually-declared tag with the same (app-inherited) value.

With the hard-coded value, an app still on the Capacitor 7 template default of
`minSdkVersion = 23` in `variables.gradle` now genuinely fails to build:
`uses-sdk:minSdkVersion 23 cannot be smaller than version 24 declared in
library` — verified by building this exact scenario both ways. Once the floor
is genuinely, enforceably 24, the plugin uses `List.removeIf`/`Stream` directly
(both need API 24+) instead of a hand-rolled loop.

### OS-level feature availability (Android)

| Feature                                      | Minimum API | Fallback                     |
| -------------------------------------------- | ----------- | ---------------------------- |
| `liquidGlass` — `RenderEffect` blur backdrop | API 31 (12) | Translucent surface          |
| Dynamic Material You color palette           | API 31 (12) | Static color                 |
| Edge-to-edge `WindowInsetsController`        | API 30 (11) | `View.setSystemUiVisibility` |

`load()` calls `Window.setDecorFitsSystemWindows(false)` for the whole activity
so the native bars can draw into system bar areas.

## Confirmed defects fixed in this release

- **Android `minSdkVersion` floor was silently unenforceable.** The initial
  implementation of the API-24 floor followed this file's usual
  `project.hasProperty('minSdkVersion') ? rootProject.ext.minSdkVersion : 24`
  pattern — correct for `compileSdkVersion`/`targetSdkVersion`, where
  following the host app is the point, but wrong here: verified by building a
  real Capacitor 7 app (template default `minSdkVersion = 23`) with it, which
  succeeded with **no error at all**, silently compiling this module at 23.
  Combined with restoring `List.removeIf`/`Stream.anyMatch()` (correct only at
  API 24+) as part of the same floor change, this would have reintroduced the
  exact `NoSuchMethodError` crash on real API-23 devices that an earlier
  release fixed — for any app that didn't happen to already declare
  `minSdkVersion = 24`, i.e. most Capacitor 7 apps. Fixed by hard-coding
  `minSdkVersion 24` (see § Android above); reverified against both an
  unraised (23, now correctly fails) and a raised (24, succeeds) app.
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
   `beginTransition` runs — `max(requestedDuration, defaultTransitionDuration)
   - 4s`— that force-restores the WebView and fires a`transitionEnd`event
(duration`0`) if the same transition is still active when it fires. The
watchdog is cancelled as soon as `finishTransition` completes normally, so
     it never fires during a legitimate, merely slow, transition.
2. **The app is backgrounded mid-transition** (`UIApplication.didEnterBackgroundNotification`
   on iOS, `handleOnPause()` on Android). Nothing the user is watching matters
   once the app isn't visible, so both platforms force-complete any active
   transition immediately rather than waiting for the watchdog delay.

This is a defensive recovery mechanism, not a new public API — no options or
return types changed.

## Verified build matrix

| Scenario                                                                         | Result                                                                          |
| -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `pnpm install` on Node.js 22.23.2                                                | ✅                                                                              |
| `pnpm run lint` (oxfmt, oxlint, `tsc` on TypeScript 7.0.2, wiring check)         | ✅                                                                              |
| `pnpm run test` (31 Vitest tests) on Node.js 22.23.2                             | ✅                                                                              |
| `pnpm run build` — ESM-only `dist/` via tsdown + TypeScript 7.0.2                | ✅                                                                              |
| `pnpm run check:package` (`publint --strict`, `attw --profile esm-only`)         | ✅                                                                              |
| Packed tarball contains no `.cjs`/`.cts`/`.d.cts`/IIFE artifacts                 | ✅                                                                              |
| ESM `import` from the packed tarball, Node.js 22.23.2                            | ✅                                                                              |
| `.d.ts` resolves under `moduleResolution` `bundler`, `node16`, `nodenext`        | ✅                                                                              |
| `xcodebuild -scheme CapacitorNativeNavigationBar` (iOS build, target 15.0)       | ✅                                                                              |
| `xcodebuild test` on iOS 26 simulator (16 Swift tests)                           | ✅                                                                              |
| `./gradlew clean build test` standalone (8 Java tests, minSdk 24)                | ✅                                                                              |
| Capacitor 7.6.8 app — Android, `minSdkVersion` left at the template default (23) | ❌ (correctly) manifest merger error, as documented above                       |
| Capacitor 7.6.8 app — Android, `minSdkVersion` raised to 24                      | ✅                                                                              |
| Capacitor 7.6.8 app — iOS via CocoaPods, deployment target left at 14.0          | ✅ builds (see the CocoaPods-vs-SPM nuance above — this is expected, not a gap) |
| Capacitor 7.6.8 app — iOS via CocoaPods, deployment target raised to 15.0        | ✅                                                                              |
| Capacitor 7.6.8 app — iOS via SPM, deployment target left at 14.0                | ❌ (correctly) `requires minimum platform version 15.0` build error             |
| Capacitor 7.6.8 app — iOS via SPM, deployment target raised to 15.0              | ✅                                                                              |

## Known limitations

- The iOS 26 Liquid Glass paths were exercised on an iOS 26 simulator only. The
  iOS 15–25 blur fallback compiles and is gated behind `if #available` but was
  not verified on a physical device in that OS range.
- Android instrumentation tests are not included. View behavior is covered by
  the emulator runs in the matrix above; Java unit tests cover pure geometry
  and parsing helpers. The transition-watchdog and background-recovery paths
  were verified by running the app end to end (see README), not by a unit test
  — both need a live `Bridge`/`Activity` (Android) or `CAPBridge` (iOS) that
  the current test targets don't construct.
- This CI workflow (`.github/workflows/ci.yml`) was authored to run the exact
  commands verified locally in this repository, but could not itself be
  executed by GitHub Actions infrastructure from this environment.
