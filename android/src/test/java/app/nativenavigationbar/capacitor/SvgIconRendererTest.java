/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

package app.nativenavigationbar.capacitor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.List;
import org.junit.Test;

/** Covers the pure parsing helpers of the SVG icon renderer (no Android canvas). */
public class SvgIconRendererTest {

    @Test
    public void parsesLeadingLengthsAndIgnoresUnits() {
        assertEquals(24f, SvgIconRenderer.length("24"), 0.0001f);
        assertEquals(1.5f, SvgIconRenderer.length(" 1.5px "), 0.0001f);
        assertEquals(-3f, SvgIconRenderer.length("-3em"), 0.0001f);
    }

    @Test
    public void returnsNullForMissingOrNonNumericLengths() {
        assertNull(SvgIconRenderer.length(null));
        assertNull(SvgIconRenderer.length("   "));
        assertNull(SvgIconRenderer.length("auto"));
    }

    @Test
    public void extractsEveryNumberFromAPointList() {
        List<Float> numbers = SvgIconRenderer.numbers("0,0 10.5,-2 3e1,4");

        assertEquals(6, numbers.size());
        assertEquals(0f, numbers.get(0), 0.0001f);
        assertEquals(10.5f, numbers.get(2), 0.0001f);
        assertEquals(-2f, numbers.get(3), 0.0001f);
        assertEquals(30f, numbers.get(4), 0.0001f);
    }

    @Test
    public void returnsAnEmptyListForNullInput() {
        assertEquals(0, SvgIconRenderer.numbers(null).size());
    }

    @Test
    public void rejectsNonFiniteLengths() {
        assertNull(SvgIconRenderer.length("1e999"));
        assertEquals(0, SvgIconRenderer.numbers("1e999").size());
    }

    @Test
    public void rejectsDoctypeEntityAndOversizedSvgInput() {
        assertTrue(SvgIconRenderer.isSafeSvg("<svg><path d='M0 0'/></svg>"));
        assertFalse(SvgIconRenderer.isSafeSvg("<!DOCTYPE svg><svg/>"));
        assertFalse(SvgIconRenderer.isSafeSvg("<svg><!ENTITY x 'x'></svg>"));
        assertFalse(SvgIconRenderer.isSafeSvg("<svg><path></svg>"));
        assertFalse(SvgIconRenderer.isSafeSvg("x".repeat(SvgIconRenderer.MAX_SVG_CHARACTERS + 1)));
    }
}
