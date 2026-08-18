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

    @MainActor
    func testWKWebViewHostingInstallsSystemTabSafeAreaCompensation() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("System Liquid Glass is available on iOS 26 or newer")
        }

        let tabController = NativeNavigationTabController()
        let contentController = NativeNavigationTabContentController()
        contentController.tabBarItem = UITabBarItem(title: "Home", image: nil, tag: 0)
        tabController.setViewControllers([contentController], animated: false)

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertTrue(contentController.host(webView: webView))

        XCTAssertTrue(webView.superview === contentController.view)
        XCTAssertEqual(
            contentController.view.subviews.filter {
                $0 is NativeNavigationSystemTabSafeAreaObserverView
            }.count,
            1
        )

        XCTAssertTrue(contentController.host(webView: webView))
        XCTAssertEqual(
            contentController.view.subviews.filter {
                $0 is NativeNavigationSystemTabSafeAreaObserverView
            }.count,
            1
        )
    }
}
