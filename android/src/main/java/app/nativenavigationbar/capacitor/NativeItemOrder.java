/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

package app.nativenavigationbar.capacitor;

import java.util.List;
import java.util.function.Predicate;

/** Pure list ordering used to keep the detached native tab in the trailing slot. */
final class NativeItemOrder {

    private NativeItemOrder() {}

    static <T> void moveLastMatchingToEnd(List<T> items, Predicate<T> predicate) {
        for (int index = items.size() - 1; index >= 0; index--) {
            T item = items.get(index);
            if (predicate.test(item)) {
                if (index != items.size() - 1) {
                    items.remove(index);
                    items.add(item);
                }
                return;
            }
        }
    }
}
