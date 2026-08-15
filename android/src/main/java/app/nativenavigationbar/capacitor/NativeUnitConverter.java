/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

package app.nativenavigationbar.capacitor;

/** Pure conversions between Android physical pixels and WebView CSS pixels/dp. */
final class NativeUnitConverter {

    private NativeUnitConverter() {}

    static float normalizedDensity(float density) {
        return Float.isFinite(density) && density > 0f ? density : 1f;
    }

    static int physicalPxToCssPx(int physicalPx, float density) {
        return Math.round(physicalPx / normalizedDensity(density));
    }

    static float dpToPhysicalPx(double dp, float density) {
        if (!Double.isFinite(dp)) {
            return 0f;
        }
        double physicalPx = dp * normalizedDensity(density);
        if (!Double.isFinite(physicalPx) || Math.abs(physicalPx) > Float.MAX_VALUE) {
            return 0f;
        }
        return (float) physicalPx;
    }

    static int relativeScreenPosition(int descendantScreenPosition, int ancestorScreenPosition) {
        return descendantScreenPosition - ancestorScreenPosition;
    }
}
