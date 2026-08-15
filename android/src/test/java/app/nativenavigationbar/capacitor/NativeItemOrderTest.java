/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

package app.nativenavigationbar.capacitor;

import static org.junit.Assert.assertEquals;

import java.util.ArrayList;
import java.util.List;
import org.junit.Test;

public class NativeItemOrderTest {

    @Test
    public void movesADetachedRoleAheadOfNormalTabsToTheTrailingSlot() {
        List<String> items = new ArrayList<>(List.of("search", "home"));

        NativeItemOrder.moveLastMatchingToEnd(items, "search"::equals);

        assertEquals(List.of("home", "search"), items);
    }

    @Test
    public void preservesOrderWhenTheDetachedRoleIsAlreadyTrailing() {
        List<String> items = new ArrayList<>(List.of("home", "search"));

        NativeItemOrder.moveLastMatchingToEnd(items, "search"::equals);

        assertEquals(List.of("home", "search"), items);
    }
}
