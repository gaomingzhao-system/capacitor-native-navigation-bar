/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

package app.nativenavigationbar.capacitor;

/** Pure visibility policy shared by navbar and tabbar state application. */
final class NativeVisibilityState {

    private NativeVisibilityState() {}

    static boolean isVisible(boolean initialized, boolean enabled, Object hiddenValue) {
        return initialized && enabled && !Boolean.TRUE.equals(hiddenValue);
    }
}
