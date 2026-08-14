// swift-tools-version: 5.9
import PackageDescription

// The iOS platform floor is 14.0, which is Capacitor 7's deployment target
// (ios/Capacitor.podspec at tag 7.x). Capacitor 8 raised its own floor to 15.0,
// but a plugin package may not require a *higher* minimum than the app that
// consumes it, so declaring 14.0 here is what makes this package installable
// into both a Capacitor 7 app and a Capacitor 8 app. Everything that needs a
// newer iOS is guarded with `if #available` at runtime.
//
// The capacitor-swift-pm range spans two majors on purpose. `cap sync` writes
// `.package(url: "…/capacitor-swift-pm.git", exact: "<@capacitor/ios version>")`
// into the app's generated Package.swift, so a plugin that pinned
// `from: "8.0.0"` could not resolve inside a Capacitor 7 app, and vice versa.
let package = Package(
    name: "CapacitorNativeNavigationBar",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "CapacitorNativeNavigationBar",
            targets: ["NativeNavigationBarPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", "7.0.0"..<"10.0.0")
    ],
    targets: [
        .target(
            name: "NativeNavigationBarPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/NativeNavigationBarPlugin"),
        .testTarget(
            name: "NativeNavigationBarPluginTests",
            dependencies: ["NativeNavigationBarPlugin"],
            path: "ios/Tests/NativeNavigationBarPluginTests")
    ]
)
