import { downloadToTemp, cleanupTempFile } from "./src/media.ts";
import { existsSync, statSync } from "fs";

const path = await downloadToTemp("https://httpbin.org/image/png");
console.log("Downloaded to:", path);
console.log("Exists:", existsSync(path));
console.log("Size:", statSync(path).size);

await cleanupTempFile(path);
console.log("After cleanup, exists:", existsSync(path));
