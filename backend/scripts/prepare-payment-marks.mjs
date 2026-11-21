import { access, copyFile, mkdir } from "node:fs/promises";

// Next-only development uses the same URLs and source artwork as Flutter web.
const source = new URL("../../app/assets/payments/", import.meta.url);
const target = new URL("../public/app/assets/assets/payments/", import.meta.url);
await mkdir(target, { recursive: true });
for (const name of ["yape.png", "plin.png"]) {
  const output = new URL(name, target);
  try {
    await copyFile(new URL(name, source), output);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    // With only backend/ mounted, the Vercel Flutter step supplies the assets.
    await access(output);
  }
}
