/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

import UIKit
import XCTest
@testable import NativeNavigationBarPlugin

class NativeNavigationTests: XCTestCase {
    func testGetPluginVersion() {
        let implementation = NativeNavigation()
        let result = implementation.getPluginVersion()

        XCTAssertEqual("native", result)
    }

    func testTabContentControllerHostsWebView() {
        let webView = UIView()
        let originalContainer = UIView()
        let controller = NativeNavigationTabContentController()
        _ = controller.view

        originalContainer.addSubview(webView)

        XCTAssertTrue(controller.host(webView: webView))
        XCTAssertEqual(webView.superview, controller.view)
        XCTAssertEqual(webView.frame, controller.view.bounds)
    }

    func testTabContentControllerKeepsSnapshotPlaceholderWhenWebViewMoves() {
        let webView = UIView()
        let firstController = NativeNavigationTabContentController()
        let secondController = NativeNavigationTabContentController()
        _ = firstController.view
        _ = secondController.view

        firstController.view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        secondController.view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        webView.backgroundColor = .systemBackground

        XCTAssertTrue(firstController.host(webView: webView))
        XCTAssertEqual(firstController.view.subviews.count, 1)

        firstController.clearHostedWebView(ifMatching: webView, preservingSnapshot: true)
        XCTAssertEqual(firstController.view.subviews.count, 2)

        XCTAssertTrue(secondController.host(webView: webView))
        XCTAssertEqual(webView.superview, secondController.view)
        XCTAssertEqual(firstController.view.subviews.count, 1)
        XCTAssertFalse(firstController.view.subviews.contains(webView))

        XCTAssertTrue(firstController.host(webView: webView))
        XCTAssertEqual(webView.superview, firstController.view)
        XCTAssertEqual(firstController.view.subviews.count, 1)
        XCTAssertTrue(firstController.view.subviews.first === webView)
    }

    func testLiftWebViewOverlaySubviewsMovesSplashOverlayAboveContainerContent() {
        let webView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let container = UIView(frame: webView.frame)
        let tabControllerView = UIView(frame: webView.frame)
        let scrollView = UIScrollView(frame: webView.bounds)
        let splashOverlay = UIView(frame: webView.bounds)
        var liftedOverlays: [NativeNavigationWeakView] = []

        container.addSubview(webView)
        container.addSubview(tabControllerView)
        webView.addSubview(scrollView)
        webView.addSubview(splashOverlay)

        nativeNavigationLiftWebViewOverlaySubviews(
            from: webView,
            to: container,
            tracking: &liftedOverlays,
            excluding: [tabControllerView]
        )

        XCTAssertEqual(scrollView.superview, webView)
        XCTAssertEqual(splashOverlay.superview, container)
        XCTAssertTrue(container.subviews.last === splashOverlay)
        XCTAssertEqual(liftedOverlays.count, 1)
        XCTAssertTrue(liftedOverlays.first?.value === splashOverlay)
    }

    func testTabContentControllerRejectsLayerCycle() {
        let webView = UIView()
        let controller = NativeNavigationTabContentController()
        _ = controller.view

        webView.addSubview(controller.view)

        XCTAssertFalse(controller.host(webView: webView))
        XCTAssertNil(webView.superview)
        XCTAssertEqual(controller.view.superview, webView)
    }

    func testStationaryTransitionsCrossfadeSnapshotsAway() {
        XCTAssertTrue(nativeNavigationUsesStationaryTransitionCrossfade(direction: "tab"))
        XCTAssertTrue(nativeNavigationUsesStationaryTransitionCrossfade(direction: "root"))
        XCTAssertTrue(nativeNavigationUsesStationaryTransitionCrossfade(direction: "none"))
        XCTAssertFalse(nativeNavigationUsesStationaryTransitionCrossfade(direction: "forward"))
        XCTAssertFalse(nativeNavigationUsesStationaryTransitionCrossfade(direction: "back"))
    }

    // MARK: - Regression coverage added by this port

    func testHexColorParsingSupportsRgbAndArgb() {
        let opaque = UIColor(nativeNavigationHexString: "#FF8800")
        XCTAssertNotNil(opaque)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        opaque?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 1, accuracy: 0.01)
        XCTAssertEqual(green, 0x88 / 255, accuracy: 0.01)
        XCTAssertEqual(blue, 0, accuracy: 0.01)
        XCTAssertEqual(alpha, 1, accuracy: 0.01)

        let translucent = UIColor(nativeNavigationHexString: "80FF8800")
        translucent?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(alpha, 0x80 / 255, accuracy: 0.01)

        XCTAssertNil(UIColor(nativeNavigationHexString: "not-a-color"))
        XCTAssertNil(UIColor(nativeNavigationHexString: "#FFF"))
    }

    func testFloatingTabBarLaysOutDetachedTrailingActionAsCircle() {
        let bar = NativeNavigationFloatingTabBar(frame: CGRect(x: 0, y: 0, width: 400, height: 64))
        var style = NativeNavigationTabbarStyleConfig()
        style.shape = .floating
        style.height = 64

        bar.configure(
            items: [
                makeItem(id: "home", index: 0),
                makeItem(id: "search", index: 1, detachedTrailing: true)
            ],
            selectedIndex: 0,
            labelVisibilityMode: "labeled",
            icons: true,
            style: style
        )

        XCTAssertTrue(bar.hasDetachedTrailing)
        let trailing = bar.trailingActionBounds(in: bar.bounds)
        XCTAssertEqual(trailing?.width, 64)
        XCTAssertEqual(trailing?.height, 64)
        XCTAssertEqual(trailing?.maxX, 400)
        // The capsule must give up the trailing diameter plus the 10pt gap.
        XCTAssertEqual(bar.capsuleBounds(in: bar.bounds).width, 400 - 64 - 10)
    }

    func testFloatingTabBarWithoutTrailingRoleUsesFullBounds() {
        let bar = NativeNavigationFloatingTabBar(frame: CGRect(x: 0, y: 0, width: 400, height: 64))
        bar.configure(
            items: [makeItem(id: "home", index: 0), makeItem(id: "profile", index: 1)],
            selectedIndex: 0,
            labelVisibilityMode: "labeled",
            icons: true,
            style: NativeNavigationTabbarStyleConfig()
        )

        XCTAssertFalse(bar.hasDetachedTrailing)
        XCTAssertNil(bar.trailingActionBounds(in: bar.bounds))
        XCTAssertEqual(bar.capsuleBounds(in: bar.bounds), bar.bounds)
    }

    func testCurveBackgroundPathCoversTheBarRect() {
        var style = NativeNavigationTabbarStyleConfig()
        style.shape = .curve
        style.height = 76
        style.centerButtonDiameter = 56
        style.centerButtonLift = 28
        style.cornerRadius = 0

        let bounds = CGRect(x: 0, y: 0, width: 320, height: style.totalHeight)
        let path = NativeNavigationTabbarBackgroundPath.path(in: bounds, style: style)

        XCTAssertFalse(path.isEmpty)
        // The notch lifts the outline above the bar top, but never above the view.
        XCTAssertGreaterThanOrEqual(path.bounds.minY, -0.5)
        XCTAssertEqual(path.bounds.maxY, style.totalHeight, accuracy: 0.5)
        XCTAssertEqual(path.bounds.width, 320, accuracy: 0.5)
    }

    func testFloatingBackgroundPathIsACapsule() {
        var style = NativeNavigationTabbarStyleConfig()
        style.shape = .floating
        style.cornerRadius = 32
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 64)

        let path = NativeNavigationTabbarBackgroundPath.path(in: bounds, style: style)
        // Bezier flattening leaves sub-ulp noise on the corner arcs.
        XCTAssertEqual(path.bounds.minX, bounds.minX, accuracy: 0.001)
        XCTAssertEqual(path.bounds.minY, bounds.minY, accuracy: 0.001)
        XCTAssertEqual(path.bounds.width, bounds.width, accuracy: 0.001)
        XCTAssertEqual(path.bounds.height, bounds.height, accuracy: 0.001)
    }

    func testOverlayLiftingSkipsWebKitInternalViews() {
        let webKitView = WKLikeView()
        XCTAssertFalse(nativeNavigationShouldLiftWebViewOverlay(webKitView))
        XCTAssertFalse(nativeNavigationShouldLiftWebViewOverlay(UIScrollView()))

        let overlay = UIView()
        XCTAssertTrue(nativeNavigationShouldLiftWebViewOverlay(overlay))
        XCTAssertFalse(nativeNavigationShouldLiftWebViewOverlay(overlay, excluding: [overlay]))
    }

    func testTransitionSurfaceIsOnlyForcedForTranslucentBackgrounds() {
        XCTAssertTrue(nativeNavigationNeedsTransitionSurface(nil))
        XCTAssertTrue(nativeNavigationNeedsTransitionSurface(UIColor.black.withAlphaComponent(0.5)))
        XCTAssertFalse(nativeNavigationNeedsTransitionSurface(UIColor.black))
    }

    func testFallbackBackgroundPromotesTranslucentColorsToOpaque() {
        let view = UIView()
        view.backgroundColor = UIColor.red.withAlphaComponent(0.25)
        let color = nativeNavigationFallbackBackground(for: view)

        var alpha: CGFloat = 0
        color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        XCTAssertEqual(alpha, 1, accuracy: 0.001)
    }

    func testSVGRendererProducesAnImageForSupportedShapes() {
        let svg = """
        <svg viewBox="0 0 24 24"><path d="M4 4 L20 4 L20 20 Z"/><circle cx="12" cy="12" r="3"/></svg>
        """
        let image = SVGIconRenderer.render(svg: svg, size: CGSize(width: 24, height: 24))
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size, CGSize(width: 24, height: 24))
    }

    func testSVGPathParserHandlesRelativeCommandsAndClose() {
        let path = SVGPathParser("m 2 2 l 10 0 l 0 10 z").parse()
        XCTAssertFalse(path.isEmpty)
        XCTAssertEqual(path.bounds.minX, 2, accuracy: 0.001)
        XCTAssertEqual(path.bounds.minY, 2, accuracy: 0.001)
        XCTAssertEqual(path.bounds.maxX, 12, accuracy: 0.001)
        XCTAssertEqual(path.bounds.maxY, 12, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makeItem(
        id: String,
        index: Int,
        detachedTrailing: Bool = false
    ) -> NativeNavigationFloatingTabItem {
        NativeNavigationFloatingTabItem(
            id: id,
            title: id,
            accessibilityTitle: id,
            image: nil,
            selectedImage: nil,
            badge: nil,
            enabled: true,
            isDetachedTrailing: detachedTrailing,
            sourceIndex: index
        )
    }
}

/// Stands in for the private `WKContentView`/`WKScrollView` classes the overlay
/// lifter must leave inside the WebView.
private final class WKLikeView: UIView {}
