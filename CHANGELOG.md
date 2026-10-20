# Changelog

## 0.1.0

Initial release: the core of the cache.

- `InMemoryCache` contract with three eviction algorithms: LRU, LFU, FIFO.
- `HotCache` facade with synchronous access (`get`, `set`, `peek`, `lookup`,
  `containsKey`, `delete`, `purge`, batch operations and iteration) and
  asynchronous load-through (`getOrLoad`, `getOrLoadMany`, `warmUp`).
- Time-to-live: cache-wide and per-entry, lazy expiry, jitter with bounded
  additive semantics on every write path, an optional janitor and
  `purgeExpired()`.
- Loaders: ordered chains, in-flight deduplication, microtask batching of
  same-turn keys, `CacheLoadException` for single loads and `LoadResult` with
  partial results for batches.
- Negative caching: shared or dedicated missing cache, populated by
  `setMissing*` and by loaders that do not return a key.
- Eviction callbacks with reasons, copy-on-read/copy-on-write hooks, and a
  pluggable `CacheMetrics` sink with a `SimpleCacheMetrics` implementation.
- Zero runtime dependencies; 212 tests with 100% line coverage and
  benchmark suites comparing algorithms on microbenchmarks and traces.
