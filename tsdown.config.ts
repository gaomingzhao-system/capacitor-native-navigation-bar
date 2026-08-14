import { defineConfig } from "tsdown";

const DEPS = { neverBundle: ["@capacitor/core"] };

/*
 * Three artifacts, matching what Capacitor apps and CDNs expect from a plugin
 * package:
 *
 *  - `dist/esm/**`  ESM + .d.ts. Code splitting stays on so the lazy
 *                   `import('./web')` in `src/registry.ts` remains a real
 *                   dynamic import: bundlers keep the web fallback out of the
 *                   initial chunk and native builds never evaluate it.
 *  - `dist/plugin.cjs`  single-file CommonJS for `require()` consumers.
 *  - `dist/plugin.js`   IIFE global build for `<script>`/unpkg usage. It keeps
 *                       upstream's `@capacitor/core` -> `capacitorExports`
 *                       global mapping; the exported global follows this
 *                       package's name, so it is `capacitorNativeNavigationBar`
 *                       rather than upstream's `capacitorNativeNavigation`.
 */
export default defineConfig([
  {
    entry: ["src/index.ts"],
    outDir: "dist/esm",
    format: ["esm"],
    dts: true,
    sourcemap: true,
    target: "es2017",
    platform: "neutral",
    deps: DEPS,
    clean: false,
  },
  {
    // Named entry so the CJS bundle and its declarations are both called
    // "plugin" without an entryFileNames override (which the dts emit ignores).
    entry: { plugin: "src/index.ts" },
    outDir: "dist",
    format: ["cjs"],
    // `"type": "module"` makes every .d.ts an ESM declaration file. A CommonJS
    // consumer resolving the `require` condition would then get ESM types
    // backing a CJS runtime file (TS1479), so the CJS bundle ships its own
    // `.d.cts` and package.json points the `require` condition at it.
    dts: true,
    sourcemap: true,
    target: "es2017",
    platform: "neutral",
    deps: DEPS,
    clean: false,
    outputOptions: {
      codeSplitting: false,
    },
  },
  {
    entry: { plugin: "src/index.ts" },
    outDir: "dist",
    format: ["iife"],
    dts: false,
    sourcemap: true,
    target: "es2017",
    platform: "browser",
    deps: DEPS,
    clean: false,
    outputOptions: {
      entryFileNames: "plugin.js",
      codeSplitting: false,
      name: "capacitorNativeNavigationBar",
      globals: {
        "@capacitor/core": "capacitorExports",
      },
    },
  },
]);
