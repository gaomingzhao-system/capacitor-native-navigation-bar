/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { registerPlugin } from "@capacitor/core";

import type { NativeNavigationPlugin } from "./definitions";
import { createNativeNavigationWeb } from "./plugin";

/*
 * Plugin registration lives in its own module so that both the public entry
 * point (index.ts) and the custom-element layer (components.ts) can import the
 * proxy statically, avoiding a circular module graph.
 *
 * The bridge name `NativeNavigation` is the wire identity shared with the iOS
 * `jsName` and the Android `@CapacitorPlugin(name)` annotation.
 */
export const NativeNavigation = registerPlugin<NativeNavigationPlugin>("NativeNavigation", {
  web: createNativeNavigationWeb,
});
