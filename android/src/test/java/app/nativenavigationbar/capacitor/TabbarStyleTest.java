/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

package app.nativenavigationbar.capacitor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class TabbarStyleTest {

    @Test
    public void defaultsDescribeTheFloatingCapsule() {
        TabbarStyle style = TabbarStyle.defaults(0x11223344);

        assertFalse(style.isCurve());
        assertEquals(64, style.height);
        assertEquals(24, style.horizontalMargin);
        assertEquals(430, style.maxWidth);
        assertEquals(10, style.bottomGap);
        assertEquals(32, style.cornerRadius);
        assertEquals(0x11223344, style.centerButtonColor);
    }

    @Test
    public void floatingBarsHaveNoLiftedTopArea() {
        TabbarStyle style = TabbarStyle.defaults(0);

        assertEquals(0, style.barTop());
        assertEquals(64, style.totalHeight());
    }

    @Test
    public void curveBarsReserveTheCenterButtonLiftAboveTheBar() {
        TabbarStyle style = new TabbarStyle(TabbarStyle.SHAPE_CURVE, 76, 0, 0, 0, 0, null, 56, 28, 0, 0);

        assertTrue(style.isCurve());
        assertEquals(28, style.barTop());
        assertEquals(104, style.totalHeight());
    }

    @Test
    public void unknownShapesFallBackToFloatingGeometry() {
        TabbarStyle style = new TabbarStyle("bogus", 50, 0, 0, 0, 0, null, 56, 28, 0, 0);

        assertFalse(style.isCurve());
        assertEquals(0, style.barTop());
        assertEquals(50, style.totalHeight());
    }
}
