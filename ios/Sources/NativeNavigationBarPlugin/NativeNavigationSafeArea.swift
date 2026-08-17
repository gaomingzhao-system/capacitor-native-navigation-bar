/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

import CoreGraphics

func nativeNavigationSystemTabBarInsetHeight(
    frameHeight: CGFloat,
    safeAreaBottom: CGFloat,
    excludesSafeArea: Bool
) -> CGFloat {
    let nativeHeight = max(frameHeight, 49 + safeAreaBottom)
    guard excludesSafeArea else {
        return nativeHeight
    }
    return max(0, nativeHeight - safeAreaBottom)
}
