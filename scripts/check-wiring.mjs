#!/usr/bin/env node
/**
 * Capacitor plugin wiring check.
 *
 * A Capacitor plugin only loads if a handful of names agree, and the failure
 * modes are silent (the bridge simply reports the plugin as unimplemented, or
 * `cap sync` writes a Podfile/Package.swift entry nothing can resolve). This
 * asserts them from the actual files:
 *
 *  1. registerPlugin('X') in src === jsName in Swift === @CapacitorPlugin(name)
 *     in Java.
 *  2. The iOS identifiers equal the Capacitor CLI's normalised package name
 *     (cli/src/plugin.ts `fixName`), because the generated Podfile emits
 *     `pod '<fixName>'` and the generated Package.swift emits
 *     `.product(name: '<fixName>', package: '<fixName>')`.
 *  3. The podspec basename, Package(name:) and .library(name:) all match that
 *     same identifier.
 *  4. package.json still declares the `capacitor` manifest the CLI looks for,
 *     and `files` ships the native sources and manifests.
 *  5. The iOS platform floor, Android minSdk fallback, and capacitor-swift-pm
 *     range match this release's declared policy (Capacitor 7 only, iOS 15+,
 *     Android API 24+) so a stale edit to one file cannot silently drift from
 *     the others.
 */

import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (relativePath) => readFileSync(join(root, relativePath), "utf8");

const failures = [];
const check = (label, actual, expected) => {
  if (actual !== expected) {
    failures.push(
      `${label}: expected ${JSON.stringify(expected)}, found ${JSON.stringify(actual)}`,
    );
  }
};
const match = (source, pattern, label) => {
  const found = source.match(pattern);
  if (!found) {
    failures.push(`${label}: pattern ${pattern} not found`);
    return undefined;
  }
  return found[1];
};

/** Mirrors `fixName` in the Capacitor CLI (identical in v7 and v8). */
const fixName = (name) => {
  const normalized = name
    .replace(/\//g, "_")
    .replace(/-/g, "_")
    .replace(/@/g, "")
    .replace(/_\w/g, (segment) => segment[1].toUpperCase());
  return normalized.charAt(0).toUpperCase() + normalized.slice(1);
};

const pkg = JSON.parse(read("package.json"));
const iosName = fixName(pkg.name);

// 1. Bridge name agreement.
const jsBridgeName = match(
  read("src/registry.ts"),
  /registerPlugin<[^>]*>\(\s*"([^"]+)"/,
  "src/registry.ts",
);
const swiftJsName = match(
  read("ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift"),
  /public let jsName = "([^"]+)"/,
  "iOS jsName",
);
const javaName = match(
  read("android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java"),
  /@CapacitorPlugin\(name = "([^"]+)"\)/,
  "Android @CapacitorPlugin",
);
check("iOS jsName vs registerPlugin", swiftJsName, jsBridgeName);
check("Android plugin name vs registerPlugin", javaName, jsBridgeName);

// 2 + 3. iOS packaging identifiers.
const podspec = read(`${iosName}.podspec`);
check("podspec s.name", match(podspec, /s\.name = '([^']+)'/, "podspec s.name"), iosName);
const packageSwift = read("Package.swift");
check(
  "Package(name:)",
  match(packageSwift, /let package = Package\(\s*name: "([^"]+)"/, "Package name"),
  iosName,
);
check(
  "library product name",
  match(packageSwift, /\.library\(\s*name: "([^"]+)"/, "library name"),
  iosName,
);

// 4. Capacitor manifest + published files.
check("capacitor.ios.src", pkg.capacitor?.ios?.src, "ios");
check("capacitor.android.src", pkg.capacitor?.android?.src, "android");
for (const required of [
  "android/build.gradle",
  "android/src/main/",
  "dist/",
  "ios/Sources",
  "Package.swift",
  `${iosName}.podspec`,
]) {
  if (!pkg.files?.includes(required)) {
    failures.push(`package.json files is missing ${JSON.stringify(required)}`);
  }
}

// 5. This release's declared floors: iOS 15.0, Android minSdk 24, Capacitor 7
// only. These are this plugin's own policy, not Capacitor 7's own minimums
// (14.0 / 23) — consuming apps on the Capacitor 7 template defaults must raise
// their own floors accordingly (documented in README.md).
check(
  "podspec deployment target",
  match(podspec, /s\.ios\.deployment_target = '([^']+)'/, "podspec target"),
  "15.0",
);
check(
  "Package.swift platform",
  match(packageSwift, /platforms: \[\.iOS\(\.v(\d+)\)\]/, "spm platform"),
  "15",
);
// Deliberately a fixed literal, not `rootProject.ext.minSdkVersion`-conditional
// like every other version in this file: that pattern lets an embedding app's
// lower value silently win with no build error (verified empirically), which
// defeats the point of declaring a floor higher than Capacitor 7's own. A
// hard-coded value is what makes the manifest merger actually enforce it.
check(
  "android minSdk (hard floor, not inherited from the host app)",
  match(read("android/build.gradle"), /^\s*minSdkVersion (\d+)$/m, "android minSdk"),
  "24",
);
const swiftPmLowerBound = match(
  packageSwift,
  /capacitor-swift-pm\.git",\s*from:\s*"([^"]+)"/,
  "capacitor-swift-pm lower bound",
);
check("capacitor-swift-pm lower bound", swiftPmLowerBound, "7.0.0");
check("peerDependencies is Capacitor-7-only", pkg.peerDependencies?.["@capacitor/core"], "^7.0.0");

if (failures.length > 0) {
  console.error("Capacitor plugin wiring check failed:");
  for (const failure of failures) {
    console.error(`  - ${failure}`);
  }
  process.exit(1);
}

console.log(`Capacitor plugin wiring OK (bridge "${jsBridgeName}", iOS package "${iosName}").`);
