/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

package app.nativenavigationbar.capacitor;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class NativeVisibilityStateTest {

    @Test
    public void staysHiddenBeforeTheFirstStateCall() {
        assertFalse(NativeVisibilityState.isVisible(false, true, null));
    }

    @Test
    public void firstPatchDefaultsToVisibleWhenHiddenIsOmitted() {
        assertTrue(NativeVisibilityState.isVisible(true, true, null));
    }

    @Test
    public void explicitHiddenStateSurvivesLaterPatches() {
        assertFalse(NativeVisibilityState.isVisible(true, true, Boolean.TRUE));
    }

    @Test
    public void disabledStateCanBeRestoredWhenReenabled() {
        assertFalse(NativeVisibilityState.isVisible(true, false, Boolean.FALSE));
        assertTrue(NativeVisibilityState.isVisible(true, true, Boolean.FALSE));
    }
}
