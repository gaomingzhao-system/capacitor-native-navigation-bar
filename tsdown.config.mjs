import { defineConfig } from "tsdown";

/*
 * Plain .mjs, not .ts: this file has no TypeScript-only syntax, so nothing is
 * gained by naming it .ts. tsdown's "auto" config loader picks how to import
 * *any* config file (regardless of its extension) based on
 * `process.features.typescript`, Node's native type-stripping flag — when
 * that's off, "auto" falls back to the optional peer dependency `unrun`,
 * which this repo does not install. That's what broke CI: the pinned Node
 * version (22.13.0, this repo's documented floor) has type-stripping
 * disabled; only later 22.x patches enable it by default (confirmed: `node -e
 * "console.log(process.features.typescript)"` prints `false` on 22.13.0 and
 * `strip` on 22.23.2). Renaming to .mjs alone does not avoid this — the
 * loader choice is not per-file. The actual fix is forcing the loader with
 * `tsdown --config-loader native` in the `build` script: since this file has
 * no TypeScript syntax, a plain native `import()` (which needs no stripping
 * support at all) always works, on every Node version this package supports.
 *
 * ESM-only output. `dist/index.js` + `dist/index.d.ts` is the single published
 * entry point; code splitting stays on so the lazy `import('./web')` in
 * `src/registry.ts` remains a real dynamic import — bundlers keep the web
 * fallback out of the initial chunk, and native (iOS/Android) builds never
 * evaluate it at all.
 *
 * `@capacitor/core` is left unbundled (`deps.neverBundle`) because it is a
 * peer dependency the host app already provides; bundling it would duplicate
 * the module and break `instanceof`/singleton assumptions Capacitor relies on
 * (e.g. a single `Capacitor.Plugins` registry).
 */
export default defineConfig({
  entry: ["src/index.ts"],
  outDir: "dist",
  format: ["esm"],
  dts: true,
  sourcemap: true,
  target: "es2020",
  platform: "neutral",
  deps: { neverBundle: ["@capacitor/core"] },
  clean: true,
});
