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
    func testSystemSafeAreaIsConvertedToNegativeAdditionalInset() {
        XCTAssertEqual(
            nativeNavigationSystemTabAdditionalSafeAreaBottom(systemSafeAreaBottom: 34),
            -34
        )
        XCTAssertEqual(
            nativeNavigationSystemTabAdditionalSafeAreaBottom(systemSafeAreaBottom: 0),
            0
        )
    }

    func testInvalidOrNegativeSafeAreaDoesNotCreatePositiveInset() {
        XCTAssertEqual(
            nativeNavigationSystemTabAdditionalSafeAreaBottom(systemSafeAreaBottom: -12),
            0
        )
        XCTAssertEqual(
            nativeNavigationSystemTabAdditionalSafeAreaBottom(systemSafeAreaBottom: .nan),
            0
        )
    }

    @MainActor
    func testAdditionalInsetPreservesOtherEdges() {
        let controller = UIViewController()
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)

        nativeNavigationApplySystemTabAdditionalSafeArea(
            systemSafeAreaBottom: 34,
            to: controller
        )

        XCTAssertEqual(controller.additionalSafeAreaInsets.top, 1)
        XCTAssertEqual(controller.additionalSafeAreaInsets.left, 2)
        XCTAssertEqual(controller.additionalSafeAreaInsets.bottom, -34)
        XCTAssertEqual(controller.additionalSafeAreaInsets.right, 4)
    }

    @MainActor
    func testWKWebViewHostingInstallsEdgeToEdgeSystemTabHandling() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("System Liquid Glass is available on iOS 26 or newer")
        }

        let tabController = NativeNavigationTabController()
        let contentController = NativeNavigationTabContentController()
        contentController.tabBarItem = UITabBarItem(title: "Home", image: nil, tag: 0)
        tabController.setViewControllers([contentController], animated: false)

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertTrue(contentController.host(webView: webView))

        XCTAssertEqual(contentController.edgesForExtendedLayout, .all)
        XCTAssertTrue(contentController.extendedLayoutIncludesOpaqueBars)
        XCTAssertFalse(contentController.view.insetsLayoutMarginsFromSafeArea)
        XCTAssertFalse(webView.insetsLayoutMarginsFromSafeArea)
        XCTAssertTrue(webView.superview === contentController.view)
        XCTAssertTrue(contentController.view.subviews.contains(where: {
            $0 is NativeNavigationSystemTabSafeAreaObserverView
        }))
    }
}
