# Platform Support

Platform, toolchain, runtime-safety, and release requirements for
`capacitor-native-navigation-bar` **7.2.0**.

## Compatibility matrix

| Area              | Supported baseline                   |
| ----------------- | ------------------------------------ |
| Capacitor         | 7.x only (`@capacitor/core: ^7.0.0`) |
| Package format    | ESM only                             |
| JavaScript target | ES2020                               |
| Node.js           | 22.13.0 or newer                     |
| Package manager   | pnpm 11.9.0                          |
| iOS               | iOS 15.0 or newer                    |
| Android           | Android 11 / API 30 or newer         |

Capacitor 8 is intentionally outside this release line. A future Capacitor 8
release must use a separate major version and toolchain validation matrix.

## npm release line

The first public npm release is `7.2.0`. The plugin major follows the supported
Capacitor major, so all releases from this branch must remain on the `7.x`
line.

The package is public and ESM-only. `prepublishOnly` runs the complete Web
verification gate (`lint`, tests, build, `publint`, and `attw`) rather than only
building the bundle.

## iOS

| Requirement            | Value       |
| ---------------------- | ----------- |
| Deployment target      | 15.0        |
| Xcode                  | 16 or newer |
| Swift Package Manager  | Supported   |
| CocoaPods              | Supported   |
| Swift language version | 5.9         |

The plugin deployment target is higher than the Capacitor 7 template default.
Consuming applications must raise their Podfile and Xcode project deployment
target to iOS 15.0.

Swift Package Manager rejects a consuming target below iOS 15. CocoaPods may
still build when the application target remains lower, but that configuration
misstates the app's real runtime support and must not be used for release.

APIs newer than iOS 15 remain behind runtime availability checks. The iOS 26
Liquid Glass paths require device-level visual validation in addition to the
simulator tests.

## Android

| Requirement           | Value                              |
| --------------------- | ---------------------------------- |
| `minSdkVersion`       | 30                                 |
| `compileSdkVersion`   | Host value; standalone fallback 36 |
| `targetSdkVersion`    | Host value; standalone fallback 36 |
| JDK / Java bytecode   | 21                                 |
| Android Gradle Plugin | Host 8.10.0+; standalone 8.13.2    |
| Gradle wrapper        | 8.14.3                             |
| AppCompat             | 1.7.1                              |
| AndroidX Core         | 1.18.0                             |
| AndroidX Test JUnit   | 1.3.0                              |
| Espresso              | 3.7.0                              |

`minSdkVersion 30` is a hard library floor. It is deliberately not inherited
from the host application because doing so would allow an API-23 application
to compile the library below its supported runtime level. A consumer below API
30 must fail at manifest merge time.

AppCompat `1.7.1` is the stable fallback used by this release. Do not replace it
with an unreleased `1.8.0` coordinate. Host applications may override the
fallback versions through their root Gradle properties, but the standalone
Android CI build must always resolve and pass without host overrides.

The plugin calls `Window.setDecorFitsSystemWindows(false)` so native navigation
chrome can draw edge-to-edge. This applies to the entire host Activity.

### Android feature availability

| Feature                                    | Minimum API | Fallback                          |
| ------------------------------------------ | ----------- | --------------------------------- |
| Typed system-bar and display-cutout insets | 30          | Baseline requirement              |
| `RenderEffect` glass blur                  | 31          | Translucent surface on Android 11 |
| Dynamic Material You colors                | 31          | Static configured colors          |

## JavaScript/native state parity

`configure`, `setNavbar`, and `setTabbar` use patch semantics. Omitted values
retain their previous state. Runtime `null` and `undefined` values are removed
by the public JavaScript facade before crossing the bridge, which keeps Web,
iOS, and Android behavior aligned even when untyped JavaScript supplies values
outside the TypeScript declarations.

The facade observes `tabSelect` and immediately synchronizes the selected tab id
back into the native tabbar state. A later color, badge, style, or global
configuration patch therefore cannot revert an iOS user-selected tab to an old
`selectedId`.

## Insets and CSS variables

When `contentInsetMode` is `css`, the plugin writes:

```text
--cap-native-navigation-top
--cap-native-navigation-right
--cap-native-navigation-bottom
--cap-native-navigation-left
--cap-native-navbar-height
--cap-native-tabbar-height
```

The reported `bottom` and `tabbarHeight` values represent content-avoidance
insets for the WebView, not raw operating-system safe-area measurements or
necessarily the full physical frame of the native bar.

| Platform path                               | Safe-area treatment    | Reported bottom/tabbarHeight                             |
| ------------------------------------------- | ---------------------- | -------------------------------------------------------- |
| iOS 26 system Liquid Glass floating tab bar | bottom safe areaを除外 | `max(frameHeight, 49 + safeAreaBottom) - safeAreaBottom` |
| iOS 26 custom/curve/non-glass tab bar       | bottom safe areaを含む | `tabbarHeight + safeAreaBottom + bottomGap`              |
| iOS 15–25 custom tab bar                    | bottom safe areaを含む | `tabbarHeight + safeAreaBottom + bottomGap`              |
| Android                                     | 既存挙動のまま         | system navigation insetとnative chromeをCSS pxへ変換     |
| Web fallback                                | OS safe areaなし       | Web fallbackのbar height                                 |

Important notes regarding inset calculations:

- `bottom` and `tabbarHeight` are content-avoidance values for layout purposes.
- On the iOS 26 system Liquid Glass path, the reported inset may not match the full raw UITabBar frame because the system-owned safe area is excluded to prevent duplicate spacing.
- If the system tab bar frame is initially 0 during first layout, a minimum height of 49pt is maintained (`49 + safeAreaBottom - safeAreaBottom = 49pt`).
- The `safeAreaChanged` event payload and CSS variables use the identical inset computation result.
- This safe-area exclusion exception applies exclusively to the system Liquid Glass tab-bar path.
- Inset calculations for `top`, `left`, and `right` remain unchanged.

Android physical pixels are converted to CSS pixels before values cross the
bridge. Zoom-transition rectangles travel in the opposite direction, from
viewport CSS pixels/native dp into physical native coordinates.

Switching to `contentInsetMode: "none"` removes variables written by an earlier
CSS configuration.

## Transition lifecycle

Each platform owns exactly one active transition session.

- Beginning a replacement completes and cleans up the previous session.
- An explicit finish id must match the active transition.
- Durations must be finite and between 0 and 60,000 milliseconds.
- Stale completion callbacks cannot clean up a newer snapshot.
- A watchdog restores the WebView if `finishTransition` is never called.
- Backgrounding the app completes the active transition immediately.

The recovery event uses duration `0` and is emitted exactly once.

## SVG and allocation limits

Inline SVG input is bounded before native allocation:

- decoded SVG: at most 256 KiB
- XML elements: at most 2,048
- XML depth: at most 64
- icon dimensions: bounded by the native renderer
- transition and snapshot dimensions: bounded before bitmap allocation

The JavaScript facade checks direct, base64, and percent-encoded SVG payloads
before they reach iOS or Android. Native renderers retain their own checks as a
second line of defense.

Remote URLs and arbitrary filesystem paths are not fetched as icons.

## Release verification

Every pull request must pass all jobs in `.github/workflows/ci.yml`:

1. Web formatting, lint, TypeScript, unit tests, build, and package checks.
2. Swift Package Manager build and Swift tests on a current iOS simulator.
3. Standalone Android Gradle build, lint, and JUnit tests using JDK 21.

npm publication must use `.github/workflows/release.yml` from `main`. The
workflow repeats all three release gates, verifies the requested version and
that the package repository matches the GitHub Actions provenance source,
rejects a version already present on npm, and publishes only after all gates
succeed.

Repository setup required before the first release:

- add an npm automation/access token as the `NPM_TOKEN` Actions secret
- keep the release workflow on `main`
- run the workflow with expected version `7.2.0` and npm tag `latest`

`npm publish` also executes `prepublishOnly`, so Web/package verification is
repeated immediately before publication.

## Known limitations

- iOS 26 Liquid Glass rendering and bottom safe-area spacing still require final
  physical-device visual validation.
- CocoaPods host integration is not built by CI; the iOS gate exercises Swift
  Package Manager. Test CocoaPods in at least one real consuming app before the
  first release.
- Android instrumentation tests are not included. Pure helpers are covered by
  JUnit, while Activity/Bridge lifecycle behavior requires a consuming-app or
  instrumentation test.
- System-tab hosting on iOS temporarily reparents the WebView and selected
  overlays. Applications with custom Auto Layout constraints must test system
  and custom tabbar shape switching in their own host.
