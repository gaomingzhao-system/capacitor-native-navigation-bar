/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

import { registerPlugin } from "@capacitor/core";

import type { NativeNavigationPlugin } from "./definitions";
import { createNativeNavigationWeb } from "./plugin";

/*
 * The registration lives in its own module so that both the public entry point
 * and the custom elements can import the proxy statically. Upstream had
 * `components.ts` reach back into the entry point with a dynamic
 * `import('./index')`, which made the two modules mutually dependent.
 *
 * The bridge name is intentionally still `NativeNavigation`: it is the wire
 * identity shared with the iOS `jsName` and the Android `@CapacitorPlugin(name)`,
 * and keeping it means existing calls and event names work unchanged.
 */
export const NativeNavigation = registerPlugin<NativeNavigationPlugin>("NativeNavigation", {
  web: createNativeNavigationWeb,
});
