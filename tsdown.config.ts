import { defineConfig } from "tsdown";

/*
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
  target: "es2017",
  platform: "neutral",
  deps: { neverBundle: ["@capacitor/core"] },
  clean: true,
});
