/**
 * Stands in for `react-devtools-core` at bundle time.
 *
 * Ink imports it statically but only calls it when DEV=true, so leaving the real
 * import in the bundle would make node fail to resolve an optional dev-only
 * dependency on every launch. Aliased in by the esbuild `build` script.
 */
export default {
  connectToDevTools() {},
};
