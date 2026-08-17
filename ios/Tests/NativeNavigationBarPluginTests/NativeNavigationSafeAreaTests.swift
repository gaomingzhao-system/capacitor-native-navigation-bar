/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

import XCTest
@testable import NativeNavigationBarPlugin

final class NativeNavigationSafeAreaTests: XCTestCase {
    func testSystemLiquidGlassExcludesBottomSafeArea() {
        XCTAssertEqual(
            nativeNavigationSystemTabBarInsetHeight(
                frameHeight: 83,
                safeAreaBottom: 34,
                excludesSafeArea: true
            ),
            49
        )
    }

    func testSystemLiquidGlassUsesMinimumHeightBeforeLayout() {
        XCTAssertEqual(
            nativeNavigationSystemTabBarInsetHeight(
                frameHeight: 0,
                safeAreaBottom: 34,
                excludesSafeArea: true
            ),
            49
        )
    }

    func testNonLiquidGlassKeepsExistingBottomSafeArea() {
        XCTAssertEqual(
            nativeNavigationSystemTabBarInsetHeight(
                frameHeight: 83,
                safeAreaBottom: 34,
                excludesSafeArea: false
            ),
            83
        )
    }

    func testSystemLiquidGlassPreservesCustomBarContentHeight() {
        XCTAssertEqual(
            nativeNavigationSystemTabBarInsetHeight(
                frameHeight: 100,
                safeAreaBottom: 34,
                excludesSafeArea: true
            ),
            66
        )
    }
}
