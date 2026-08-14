// swift-tools-version: 5.9
import PackageDescription

// This plugin supports Capacitor 7 only. Capacitor 7's own iOS deployment
// target is 14.0, but this package intentionally raises its floor to 15.0 for
// modern-OS support — a plugin's declared minimum may exceed what Capacitor
// itself requires, as long as the *consuming app* also targets iOS 15.0+.
// Apps that still ship the Capacitor 7 template default (`platform :ios,
// '14.0'` in the Podfile, or an Xcode project deployment target of 14.0) must
// raise it to 15.0 before this plugin will build — see README.md.
//
// `capacitor-swift-pm` is pinned to the Capacitor 7 major only (`from:
// "7.0.0"`, i.e. `>=7.0.0 <8.0.0`) since Capacitor 8 support is out of scope
// for this release. `cap sync` writes
// `.package(url: "…/capacitor-swift-pm.git", exact: "<@capacitor/ios version>")`
// into the app's generated Package.swift, so this range must include every
// Capacitor 7.x patch/minor release.
let package = Package(
    name: "CapacitorNativeNavigationBar",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapacitorNativeNavigationBar",
            targets: ["NativeNavigationBarPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "7.0.0")
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
