import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // The web implementation and the custom elements touch document,
    // customElements and CustomEvent, so the suite needs a DOM.
    environment: "happy-dom",
    include: ["test/**/*.test.ts"],
    restoreMocks: true,
  },
});
