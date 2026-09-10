/**
 * Bundles the board into a single dist/session-board.mjs, so a machine only
 * needs `node` to run it — no node_modules, no install, no network. The bundle
 * is committed for exactly that reason.
 */
import { build } from "esbuild";

await build({
  entryPoints: ["src/session-board.tsx"],
  outfile: "dist/session-board.mjs",
  bundle: true,
  minify: true,
  platform: "node",
  format: "esm",
  target: "node20",
  logLevel: "warning",
  // Ink imports react-devtools-core statically but only calls it when DEV=true.
  // Left alone it becomes an unresolvable runtime import of an optional dev
  // dependency; the stub keeps the bundle self-contained.
  alias: { "react-devtools-core": "./src/react-devtools-stub.ts" },
  // CJS dependencies deep in Ink's tree call require() at runtime. An ESM
  // bundle has no require, and esbuild's stand-in only throws — so hand it a
  // real one built from this module's own URL.
  banner: {
    js: [
      'import { createRequire as __nodeCreateRequire } from "node:module";',
      "const require = __nodeCreateRequire(import.meta.url);",
    ].join("\n"),
  },
});
