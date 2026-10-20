# Introduction

## What is pepper?

`pepper` is an in-memory cache for Dart server applications — Serverpod,
shelf, plain `dart:io` services, or anything else running on the Dart VM. It
pairs three eviction policies with time-to-live expiry, load-through with
in-flight deduplication, negative caching, metrics and copy hooks, all with
**zero runtime dependencies**.

It is inspired by [samber/hot](https://github.com/samber/hot), but it is not a
line-by-line port. The algorithms use Dart's own `HashMap` and intrusive
`LinkedList`, the async paths use futures and microtasks, and every deviation
from upstream is deliberate and documented.

## Why not just a Map?

A plain `Map` never forgets. A cache has to answer four questions at once:

- **What should stay?** — LRU, LFU or FIFO chooses the victim at capacity.
- **When should it go?** — TTL with monotonic deadlines and jitter.
- **Who loads it?** — loader chains with single-flight deduplication and batching.
- **What is happening?** — hit/miss/eviction counters and callbacks.

`pepper` keeps those concerns behind one `HotCache` facade, with a low-level
`InMemoryCache` contract you can also use directly.

## A quick taste

```dart
import 'package:pepper/pepper.dart';

final cache = HotCache<String, User>(
  algorithm: EvictionAlgorithm.lru,
  capacity: 10_000,
  ttl: const Duration(minutes: 5),
);

cache.set('user:1', user);
final User? cached = cache.get('user:1');
```

## What ships in v0.1

| Area | Included |
|---|---|
| **Eviction** | LRU, LFU and FIFO; exact capacity; O(1) victim selection; the low-level `LruCache`, `LfuCache` and `FifoCache` are public too |
| **TTL** | Cache-wide and per-entry lifetimes; additive jitter on every write path; lazy expiry; optional janitor; `purgeExpired()`; TTL on negative entries |
| **Load-through** | Ordered loader chains; per-key single-flight; same-turn batching; `CacheLoadException`; partial `LoadResult` for batches; unresolved keys become negative entries |
| **Negative caching** | `MissingCacheConfig.shared()` and `.dedicated(algorithm, capacity)`; `setMissing*`; `Missing` lookups; independent TTL; `missingLength`; `delete`/`purge` clear both caches |
| **Synchronous API** | `get`, `set`, `peek`, `containsKey`, `lookup`; `getAll`, `setMany`; `delete`, `deleteMany`, `purge`, `purgeExpired`; `keys`, `values`, `all`, `forEach` |
| **Asynchronous API** | `getOrLoad`, `getOrLoadMany`, `warmUp` (values and known-missing keys, with an optional timeout) |
| **Safety** | copy-on-read and copy-on-write hooks; reentrancy guard for eviction callbacks; sealed `CacheLookup`; exact live/missing counters; no locks; monotonic `TimeSource` |
| **Observability** | `CacheMetrics` events, `SimpleCacheMetrics` counters, hit rate, evictions by reason, loader errors, purge events, eviction callbacks |
| **Operations** | `dispose()` for the janitor; injectable `TimeSource` and `Random`; CI with formatting, analysis, tests, coverage and Codecov |
| **Quality** | 212 tests; 100% line coverage (570/570); differential fuzzing against reference models; 1M-operation stress tests; zero runtime dependencies |

## Metrics with SimpleCacheMetrics

```dart
final metrics = SimpleCacheMetrics();
final cache = HotCache<String, int>(
  algorithm: EvictionAlgorithm.lru,
  capacity: 100,
  metrics: metrics,
);

cache.set('a', 1);
cache.get('a');
cache.get('missing');

print(metrics.hits);        // 1
print(metrics.misses);      // 1
print(metrics.hitRate);     // 0.5
print(metrics.inserts);     // 1
print(metrics.length);      // 1
print(metrics.evictions(EvictionReason.capacity)); // 0
```

`SimpleCacheMetrics` also exposes `totalEvictions`, `evictions(reason)`,
`loads`, `loadErrors`, `purges`, `missingLength`, and per-reason counters for
`capacity`, `ttl` and `manual` removals. See
[Get Started → Metrics and callbacks](/get-started#metrics-and-callbacks) for
the full counter table and the difference between the metrics sink and the
`onEviction` callback.

## Performance at a glance

Measured with `dart compile exe bench/bench.dart` on an Apple M-series laptop
(Dart 3.12.2). Each `set+get` row performs both operations per iteration, so
its cost per operation is half the listed number. A miss is a single hash
lookup.

| Benchmark | ns/op | ops/s |
|---|---:|---:|
| `HotCache` get miss | 5.3 | 187,312 K |
| `FifoCache` set+get, resident | 9.2 | 108,391 K |
| `HotCache` get hit, negative cache enabled | 48.4 | 20,672 K |
| `HotCache` get hit, TTL + expiry check | 61.9 | 16,154 K |
| `FifoCache` set+get, evicting | 63.4 | 15,779 K |
| `LruCache` set+get, resident | 73.6 | 13,594 K |
| `HotCache` set, TTL + jitter | 78.0 | 12,822 K |
| `LfuCache` set+get, resident | 99.3 | 10,068 K |
| `LruCache` set+get, evicting | 99.5 | 10,051 K |
| `HotCache` set+get, resident | 113.1 | 8,842 K |
| `LfuCache` set+get, evicting | 114.0 | 8,771 K |
| `HotCache` getOrLoad hit (async) | 128.3 | 7,797 K |

::: tip JIT vs AOT
These are AOT numbers. Running `dart run bench/bench.dart` (JIT) can look
faster on tight synchronous loops and roughly 2× slower on async hits. Use AOT
for the numbers that reflect a deployed server.
:::

Algorithm quality, on deterministic traces:

| Trace | LRU | LFU | FIFO |
|---|---:|---:|---:|
| Zipf(1.0), 100k accesses, 10k keys, capacity 1k | 67.29% hits | **72.58%** | 62.88% |
| Scan resistance, 1k hot keys after a 20k-key scan | 0.0% retained | **99.9%** | 0.0% |

[Eviction Techniques](/eviction/) explains why the scan result is 0% for LRU
and FIFO, and why LFU retains 99.9% rather than 100%.

## Quality baseline

- **212 tests**, no skips, including differential fuzzing against independent
  reference models and 1M-operation stress tests.
- **100% line coverage** (570/570), 148/149 functions, 287/292 branches.
- `dart analyze --fatal-infos` clean; `dart doc` with 0 warnings.
- **Zero runtime dependencies**; only dev dependencies for tests and benchmarks.
- CI runs formatting, analysis, tests, the example, coverage and the Codecov upload.

## Documentation map

| Section | What it covers |
|---|---|
| [Get Started](/get-started) | Installation, architecture, quickstart, TTL, loaders, negative caching, configuration, metrics, production notes |
| [Eviction Techniques](/eviction/) | LRU, LFU and FIFO internals, victim selection, measured behavior, how to add an algorithm |
| [Example](/example) | The complete runnable example with its output and a line-by-line walkthrough |
| [Changelog](/changelog) | Release notes, mirrored from `CHANGELOG.md` |

## Status

**v0.1.0 — not yet on pub.dev.** Until the first release, depend on the
repository:

```yaml
dependencies:
  pepper:
    git:
      url: https://github.com/infm5/pepper.git
```
