/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

package app.nativenavigationbar.capacitor;

import android.graphics.drawable.Drawable;

final class NativeTabItem {

    final String id;
    final String title;
    final Drawable icon;
    final Drawable selectedIcon;
    final String badge;
    final boolean enabled;
    final boolean detachedTrailing;
    final int sourceIndex;

    NativeTabItem(
        String id,
        String title,
        Drawable icon,
        Drawable selectedIcon,
        String badge,
        boolean enabled,
        boolean detachedTrailing,
        int sourceIndex
    ) {
        this.id = id;
        this.title = title;
        this.icon = icon;
        this.selectedIcon = selectedIcon;
        this.badge = badge;
        this.enabled = enabled;
        this.detachedTrailing = detachedTrailing;
        this.sourceIndex = sourceIndex;
    }
}
