import { defineConfig } from "vitest/config";
export default defineConfig({
  resolve: { alias: { "@": new URL("./src", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1") } },
  oxc: { jsx: { runtime: "automatic" } },
  test: { include: ["tests/**/*.test.ts"] },
});
