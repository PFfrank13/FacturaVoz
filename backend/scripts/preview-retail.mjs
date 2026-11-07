// Isolated UI harness. Never imported by Next.js or deployed routes.
import { createServer } from "vite";
import { fileURLToPath } from "node:url";
import path from "node:path";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const qa = path.join(root, "tests/retail-preview");
const server = await createServer({
  configFile: false, root: qa,
  server: { host: "127.0.0.1", port: 3101, strictPort: true, fs: { allow: [root] } },
  resolve: { alias: [
    { find: "@/app/erp/receiving", replacement: path.join(qa, "receiving.ts") },
    { find: "@/app/erp/checkout", replacement: path.join(qa, "checkout.ts") },
    { find: "next/link", replacement: path.join(qa, "link.tsx") },
    { find: "@", replacement: path.join(root, "src") },
  ] },
  esbuild: { jsx: "automatic" },
  css: { postcss: { plugins: [] } },
});
await server.listen(); server.printUrls();
