/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

package app.nativenavigationbar.capacitor;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class NativeUnitConverterTest {

    @Test
    public void exportsPhysicalPixelsAsCssPixelsAtCommonDensities() {
        assertEquals(56, NativeUnitConverter.physicalPxToCssPx(56, 1f));
        assertEquals(56, NativeUnitConverter.physicalPxToCssPx(112, 2f));
        assertEquals(56, NativeUnitConverter.physicalPxToCssPx(168, 3f));
    }

    @Test
    public void convertsCssPixelRectComponentsBackToPhysicalPixels() {
        assertEquals(24f, NativeUnitConverter.dpToPhysicalPx(24, 1f), 0.001f);
        assertEquals(48f, NativeUnitConverter.dpToPhysicalPx(24, 2f), 0.001f);
        assertEquals(72f, NativeUnitConverter.dpToPhysicalPx(24, 3f), 0.001f);
    }

    @Test
    public void invalidDensityFallsBackToOne() {
        assertEquals(24, NativeUnitConverter.physicalPxToCssPx(24, 0f));
        assertEquals(24, NativeUnitConverter.physicalPxToCssPx(24, Float.NaN));
        assertEquals(24f, NativeUnitConverter.dpToPhysicalPx(24, Float.POSITIVE_INFINITY), 0.001f);
        assertEquals(0f, NativeUnitConverter.dpToPhysicalPx(Double.MAX_VALUE, 3f), 0.001f);
    }

    @Test
    public void computesNestedViewCoordinatesRelativeToTheContentRoot() {
        assertEquals(84, NativeUnitConverter.relativeScreenPosition(124, 40));
        assertEquals(-12, NativeUnitConverter.relativeScreenPosition(28, 40));
    }
}
