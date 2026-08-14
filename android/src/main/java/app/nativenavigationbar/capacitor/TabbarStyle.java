/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

package app.nativenavigationbar.capacitor;

import android.graphics.Color;

/** Immutable snapshot of the tabbar layout options, in dp. */
final class TabbarStyle {

    static final String SHAPE_FLOATING = "floating";
    static final String SHAPE_CURVE = "curve";

    final String shape;
    final int height;
    final int horizontalMargin;
    final int maxWidth;
    final int bottomGap;
    final int cornerRadius;
    final String centerItemId;
    final int centerButtonDiameter;
    final int centerButtonLift;
    final int centerButtonColor;
    final int centerButtonIconColor;

    TabbarStyle(
        String shape,
        int height,
        int horizontalMargin,
        int maxWidth,
        int bottomGap,
        int cornerRadius,
        String centerItemId,
        int centerButtonDiameter,
        int centerButtonLift,
        int centerButtonColor,
        int centerButtonIconColor
    ) {
        this.shape = shape;
        this.height = height;
        this.horizontalMargin = horizontalMargin;
        this.maxWidth = maxWidth;
        this.bottomGap = bottomGap;
        this.cornerRadius = cornerRadius;
        this.centerItemId = centerItemId;
        this.centerButtonDiameter = centerButtonDiameter;
        this.centerButtonLift = centerButtonLift;
        this.centerButtonColor = centerButtonColor;
        this.centerButtonIconColor = centerButtonIconColor;
    }

    static TabbarStyle defaults(int tintColor) {
        return new TabbarStyle(SHAPE_FLOATING, 64, 24, 430, 10, 32, null, 56, 28, tintColor, Color.WHITE);
    }

    boolean isCurve() {
        return SHAPE_CURVE.equals(shape);
    }

    int barTop() {
        return isCurve() ? centerButtonLift : 0;
    }

    int totalHeight() {
        return height + barTop();
    }
}
