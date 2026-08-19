/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

import UIKit
import WebKit
import XCTest
@testable import NativeNavigationBarPlugin

final class NativeNavigationSystemTabSafeAreaTests: XCTestCase {
    func testSystemTabCompensatesTheInheritedBottomSafeArea() {
        XCTAssertEqual(
            nativeNavigationSystemTabBottomSafeAreaCompensation(
                safeAreaBottom: 83,
                currentCompensation: 0
            ),
            -83
        )
    }

    func testCompensationRemainsStableAfterUIKitRecalculatesTheSafeArea() {
        XCTAssertEqual(
            nativeNavigationSystemTabBottomSafeAreaCompensation(
                safeAreaBottom: 0,
                currentCompensation: -83
            ),
            -83
        )
    }

    func testCompensationTracksSafeAreaChangesWithoutDoubleSubtracting() {
        XCTAssertEqual(
            nativeNavigationSystemTabBottomSafeAreaCompensation(
                safeAreaBottom: 34,
                currentCompensation: -49
            ),
            -83
        )
    }

    func testInvalidOrNegativeSafeAreaDoesNotCreatePositiveInset() {
        XCTAssertEqual(
            nativeNavigationSystemTabBottomSafeAreaCompensation(
                safeAreaBottom: -12,
                currentCompensation: 0
            ),
            0
        )
        XCTAssertEqual(
            nativeNavigationSystemTabBottomSafeAreaCompensation(
                safeAreaBottom: .nan,
                currentCompensation: 0
            ),
            0
        )
    }

    func testSystemTabStandardAppearanceCanBecomeFullyTransparent() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        XCTAssertTrue(nativeNavigationSystemTabAppearanceHasOpaqueBackground(appearance))

        let transparentAppearance = nativeNavigationSystemTabTransparentStandardAppearance(
            from: appearance
        )

        XCTAssertFalse(nativeNavigationSystemTabAppearanceHasOpaqueBackground(transparentAppearance))
        XCTAssertNil(transparentAppearance.backgroundEffect)
        XCTAssertLessThanOrEqual(
            transparentAppearance.backgroundColor?.cgColor.alpha ?? 0,
            0.001
        )
        XCTAssertLessThanOrEqual(
            transparentAppearance.shadowColor?.cgColor.alpha ?? 0,
            0.001
        )
    }

    func testTransparentSystemTabAppearanceDoesNotMutateTheSourceAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        _ = nativeNavigationSystemTabTransparentStandardAppearance(from: appearance)

        XCTAssertTrue(nativeNavigationSystemTabAppearanceHasOpaqueBackground(appearance))
    }

    func testSystemTabContentFrameExtendsOnlyItsBottomEdge() {
        let currentFrame = CGRect(x: 0, y: 0, width: 390, height: 761)
        let systemBounds = CGRect(x: 0, y: 0, width: 390, height: 844)

        XCTAssertEqual(
            nativeNavigationSystemTabExtendedContentFrame(
                currentFrame: currentFrame,
                systemTabBounds: systemBounds
            ),
            CGRect(x: 0, y: 0, width: 390, height: 844)
        )
    }

    func testSystemTabContentFrameNeverShrinksOrUsesInvalidGeometry() {
        let currentFrame = CGRect(x: 0, y: 0, width: 390, height: 844)

        XCTAssertEqual(
            nativeNavigationSystemTabExtendedContentFrame(
                currentFrame: currentFrame,
                systemTabBounds: CGRect(x: 0, y: 0, width: 390, height: 761)
            ),
            currentFrame
        )
        XCTAssertEqual(
            nativeNavigationSystemTabExtendedContentFrame(
                currentFrame: currentFrame,
                systemTabBounds: CGRect(x: 0, y: 0, width: 390, height: CGFloat.nan)
            ),
            currentFrame
        )
    }

    @MainActor
    func testWKWebViewHostingInstallsSystemTabSafeAreaCompensation() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("System Liquid Glass is available on iOS 26 or newer")
        }

        let tabController = NativeNavigationTabController()
        let contentController = NativeNavigationTabContentController()
        contentController.tabBarItem = UITabBarItem(title: "Home", image: nil, tag: 0)
        tabController.setViewControllers([contentController], animated: false)
        tabController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        tabController.view.setNeedsLayout()
        tabController.view.layoutIfNeeded()

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 761))
        XCTAssertTrue(contentController.host(webView: webView))

        XCTAssertEqual(contentController.edgesForExtendedLayout, .all)
        XCTAssertTrue(contentController.extendedLayoutIncludesOpaqueBars)
        XCTAssertFalse(contentController.view.insetsLayoutMarginsFromSafeArea)
        XCTAssertFalse(webView.insetsLayoutMarginsFromSafeArea)
        XCTAssertTrue(webView.superview === contentController.view)

        let observers = contentController.view.subviews.compactMap {
            $0 as? NativeNavigationSystemTabSafeAreaObserverView
        }
        XCTAssertEqual(observers.count, 1)
        XCTAssertTrue(observers[0].hostedWebView === webView)

        if !UIAccessibility.isReduceTransparencyEnabled {
            XCTAssertFalse(
                nativeNavigationSystemTabAppearanceHasOpaqueBackground(
                    tabController.tabBar.standardAppearance
                )
            )
            XCTAssertTrue(tabController.tabBar.isTranslucent)
        }

        XCTAssertTrue(contentController.host(webView: webView))
        XCTAssertEqual(
            contentController.view.subviews.filter {
                $0 is NativeNavigationSystemTabSafeAreaObserverView
            }.count,
            1
        )
    }

    @MainActor
    func testWKWebViewFrameReachesTheSystemTabControllerBottom() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("System Liquid Glass is available on iOS 26 or newer")
        }

        let tabController = NativeNavigationTabController()
        let contentController = NativeNavigationTabContentController()
        contentController.tabBarItem = UITabBarItem(title: "Home", image: nil, tag: 0)
        tabController.setViewControllers([contentController], animated: false)
        tabController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        tabController.view.setNeedsLayout()
        tabController.view.layoutIfNeeded()

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 761))
        XCTAssertTrue(contentController.host(webView: webView))

        guard let contentContainer = contentController.view.superview,
              let observer = contentController.view.subviews.first(where: {
                  $0 is NativeNavigationSystemTabSafeAreaObserverView
              }) as? NativeNavigationSystemTabSafeAreaObserverView else {
            return XCTFail("System tab hosting hierarchy was not installed")
        }

        let systemBounds = tabController.view.convert(
            tabController.view.bounds,
            to: contentContainer
        )
        let shortenedHeight = max(1, systemBounds.height - 83)
        contentController.view.frame = CGRect(
            x: systemBounds.minX,
            y: systemBounds.minY,
            width: systemBounds.width,
            height: shortenedHeight
        )
        webView.frame = contentController.view.bounds

        observer.synchronize()

        XCTAssertEqual(
            contentController.view.frame.maxY,
            systemBounds.maxY,
            accuracy: 0.5
        )
        XCTAssertEqual(webView.frame, contentController.view.bounds)
    }
}
