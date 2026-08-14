/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

import type { NativeNavigationPlugin } from "./definitions";

export const createNativeNavigationWeb = (): Promise<NativeNavigationPlugin> =>
  import("./web").then((m) => new m.NativeNavigationWeb());
