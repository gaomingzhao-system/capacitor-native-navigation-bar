/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

package app.nativenavigationbar.capacitor;

import org.json.JSONObject;

/** Parsed `glass` option block shared by the navbar and the tabbar. */
final class GlassOptions {

    private static final String EFFECT_NONE = "none";
    private static final String EFFECT_LIQUID_GLASS = "liquidGlass";
    private static final double DEFAULT_BLUR_RADIUS_DP = 18d;
    private static final double MAX_BLUR_RADIUS_DP = 256d;
    private static final double DEFAULT_SURFACE_ALPHA = 0.62d;

    final String effect;
    final double blurRadiusDp;
    final double surfaceAlpha;

    GlassOptions(String effect, double blurRadiusDp, double surfaceAlpha) {
        this.effect = effect;
        this.blurRadiusDp = Math.max(0d, Math.min(MAX_BLUR_RADIUS_DP, blurRadiusDp));
        this.surfaceAlpha = Math.max(0d, Math.min(1d, surfaceAlpha));
    }

    static GlassOptions defaults() {
        return new GlassOptions(EFFECT_NONE, DEFAULT_BLUR_RADIUS_DP, DEFAULT_SURFACE_ALPHA);
    }

    static GlassOptions from(JSONObject raw, GlassOptions fallback) {
        GlassOptions base = fallback == null ? defaults() : fallback;
        if (raw == null) {
            return base;
        }

        String effect = raw.optString("effect", base.effect);
        if (!EFFECT_NONE.equals(effect) && !EFFECT_LIQUID_GLASS.equals(effect)) {
            effect = base.effect;
        }
        double blurRadiusDp = raw.has("blurRadius") ? raw.optDouble("blurRadius", base.blurRadiusDp) : base.blurRadiusDp;
        double surfaceAlpha = raw.has("surfaceAlpha") ? raw.optDouble("surfaceAlpha", base.surfaceAlpha) : base.surfaceAlpha;
        if (!Double.isFinite(blurRadiusDp) || blurRadiusDp < 0d) {
            blurRadiusDp = base.blurRadiusDp;
        }
        if (!Double.isFinite(surfaceAlpha) || surfaceAlpha < 0d || surfaceAlpha > 1d) {
            surfaceAlpha = base.surfaceAlpha;
        }
        return new GlassOptions(effect, blurRadiusDp, surfaceAlpha);
    }

    boolean isLiquidGlass() {
        return EFFECT_LIQUID_GLASS.equals(effect);
    }
}
