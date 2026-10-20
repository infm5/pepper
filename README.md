# Pepper🌶️: A high-performance, dependency-free in-memory cache for Dart.

LRU · LFU · FIFO · TTL + jitter · load-through · negative caching · metrics

[![CI](https://github.com/infm5/pepper/actions/workflows/ci.yml/badge.svg)](https://github.com/infm5/pepper/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/infm5/pepper/branch/master/graph/badge.svg)](https://codecov.io/gh/infm5/pepper)
[![Dart](https://img.shields.io/badge/dart-%5E3.12.2-blue?logo=dart)](https://dart.dev)
[![Runtime dependencies](https://img.shields.io/badge/runtime%20dependencies-0-brightgreen)](https://github.com/infm5/pepper/blob/master/pubspec.yaml)
[![Platform](https://img.shields.io/badge/platform-Dart%20VM-lightgrey)](https://dart.dev)

Inspired by [samber/hot](https://github.com/samber/hot).

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

## Features

- **Eviction algorithms**: LRU, LFU and FIFO behind one `InMemoryCache`
  interface. SIEVE, TwoQueue, ARC, TinyLFU, W-TinyLFU and S3FIFO are planned.
- **TTL**: cache-wide and per-entry lifetimes, lazy expiry, optional
  background janitor and an explicit `purgeExpired()`.
- **Jitter**: a bounded random delay added to every stored expiry, applied on
  every write path, to spread expirations out and avoid stampedes.
- **Load-through**: `getOrLoad` and `getOrLoadMany` resolve misses through a
  loader chain, deduplicating concurrent loads per key and batching the keys
  requested within the same event-loop turn into a single loader call.
- **Negative caching**: keys a loader does not return are remembered as
  missing, in the main cache or in a dedicated cache with its own algorithm.
- **Operations**: warm-up, copy-on-read/copy-on-write hooks, synchronous
  eviction callbacks, purge/delete, and simple metrics counters.
- **Zero runtime dependencies.**

## Getting started

```sh
dart pub add pepper
```

## Usage

### Synchronous access

```dart
final cache = HotCache<String, int>(
  algorithm: EvictionAlgorithm.lfu,
  capacity: 1_000,
);

cache.set('a', 1);
cache.setMany({'b': 2, 'c': 3});

cache.get('a');            // 1
cache.getAll(['a', 'zzz']); // {a: 1}
cache.lookup('a');         // Present(1)
cache.containsKey('a');    // true
cache.delete('a');         // true
cache.length;              // 2
```

`get` returns `null` for absent, expired and negative-cached keys. Use
`lookup` to tell them apart:

```dart
switch (cache.lookup(key)) {
  case Present(:final value):
    print('found $value');
  case Missing():
    print('known to be missing');
  case Absent():
    print('not cached');
}
```

### Time-to-live

```dart
final cache = HotCache<String, int>(
  algorithm: EvictionAlgorithm.lru,
  capacity: 1_000,
  ttl: const Duration(minutes: 5),
  jitter: const Duration(seconds: 30),
  janitor: true,
);

cache.setWithTTL('session', 1, const Duration(hours: 1));
cache.purgeExpired(); // removes expired entries eagerly
cache.dispose();      // stops the janitor
```

### Load-through

```dart
final cache = HotCache<int, User>(
  algorithm: EvictionAlgorithm.lru,
  capacity: 10_000,
  ttl: const Duration(minutes: 5),
  missingCache: const MissingCacheConfig.shared(),
  loaders: [loadUsersFromDatabase],
);

Future<Map<int, User>> loadUsersFromDatabase(Set<int> keys) async {
  final rows = await database.query('select * from users where id = ?', keys);
  return {for (final row in rows) row.id: row};
}

final user = await cache.getOrLoad(42);           // one loader call
final users = await cache.getOrLoadMany({1, 2});  // one batched call
```

Concurrent misses for the same key share a single load, and keys requested
within the same turn are coalesced into one loader invocation. A loader that
returns no value for a key marks it missing when negative caching is enabled,
so the next lookup short-circuits.

Loader chains run in order, each receiving the keys still missing, and stop
at the first error. `getOrLoad` throws a `CacheLoadException`; `getOrLoadMany`
never throws for loader failures and reports them through `LoadResult`:

```dart
final result = await cache.getOrLoadMany({1, 2, 3});
result.values;  // found or loaded values
result.missing; // unresolved keys
result.failed;  // keys whose load failed
result.error;   // the first failure, if any
```

### Observability

```dart
final metrics = SimpleCacheMetrics();
final cache = HotCache<String, int>(
  algorithm: EvictionAlgorithm.lru,
  capacity: 1_000,
  metrics: metrics,
  onEviction: (reason, key, value) {
    print('$key evicted because of $reason');
  },
);

metrics.hits;
metrics.misses;
metrics.hitRate;
metrics.evictions(EvictionReason.capacity);
```

## Performance

Measured with `dart compile exe bench/bench.dart` on an Apple M-series
laptop (Dart 3.12.2). Each "set+get" row performs both operations per
iteration, so its cost per operation is half the listed number. A miss is a
single hash lookup, hence its sub-10 ns cost.

| Benchmark | ns/op | ops/s |
|---|---:|---:|
| `HotCache` get miss | 5.3 | 187,312 K |
| `FifoCache` set+get, resident | 9.2 | 108,391 K |
| `HotCache` get hit, negative cache enabled | 48.4 | 20,672 K |
| `HotCache` get hit, TTL+expiry check | 61.9 | 16,154 K |
| `FifoCache` set+get, evicting | 63.4 | 15,779 K |
| `LruCache` set+get, resident | 73.6 | 13,594 K |
| `HotCache` set, TTL+jitter | 78.0 | 12,822 K |
| `LfuCache` set+get, resident | 99.3 | 10,068 K |
| `LruCache` set+get, evicting | 99.5 | 10,051 K |
| `HotCache` set+get, resident | 113.1 | 8,842 K |
| `LfuCache` set+get, evicting | 114.0 | 8,771 K |
| `HotCache` getOrLoad hit (async) | 128.3 | 7,797 K |

Workload quality, deterministic traces:

| Trace | LRU | LFU | FIFO |
|---|---:|---:|---:|
| Zipf(1.0), 100k accesses, 10k keys, capacity 1k | 67.29% hits | **72.58%** | 62.88% |
| Scan resistance, 1k hot keys after a 20k-key scan | 0.0% retained | **99.9%** | 0.0% |

The scan-resistance result is the point of frequency-aware eviction: a single
cold scan flushes a pure recency or insertion-order cache, while LFU keeps
every key that was accessed more than once.

Run the benchmarks yourself:

```sh
dart run bench/bench.dart
```

## Design notes

- **One isolate per cache.** A Dart isolate executes synchronous code without
  interleaving, so `get`, `set`, `delete`, and the rest need no locks and the
  hot path has none. Only `getOrLoad`, `getOrLoadMany` and `warmUp` are
  asynchronous.
- **Monotonic time.** Expiry is computed from a `Stopwatch`-backed
  `TimeSource` in microseconds, never from `DateTime.now`, so it cannot be
  skewed by wall-clock adjustments. `TimeSource` is injectable for
  deterministic tests.
- **Dart-native data structures.** Every algorithm pairs a `HashMap` index
  with an intrusive `LinkedList` of `LinkedListEntry` nodes, giving O(1)
  access, reordering and eviction with a single hash lookup per operation.
- **Sealed result types.** `CacheLookup` (`Present`/`Missing`/`Absent`) makes
  the distinction between a value, a negative entry and absence explicit and
  exhaustively checkable.
- **Future-based singleflight.** In-flight loads are tracked as futures; the
  first caller schedules a microtask that batches every key requested in the
  same turn and invokes the loader chain once.

## Production notes

- **One cache per isolate.** Dart isolates do not share memory, so a
  multi-isolate server (for example Serverpod) ends up with one cache per
  isolate and pays for it per isolate. Size `capacity` accordingly.
- **Dispose the janitor.** `dispose()` cancels the background timer; caches
  created per request instead of per service will otherwise leak a timer.
- **Loaders must complete.** An in-flight load is held until its future
  settles, so give database or HTTP loaders a timeout — a hung backend
  otherwise pins its keys in the in-flight registry.
- **Eviction callbacks may only read.** Mutating the cache from a callback
  throws a `StateError`, because the cache is mid-eviction while the callback
  runs (upstream hot deadlocks in the same situation). An exception thrown by
  a callback propagates to the caller of the operation that triggered the
  eviction, after the victim has been removed.
- **Sizing is by entry count.** v1 has no byte-size accounting; `capacity`
  counts entries, not memory.
- **Adversarial keys.** Dart's string hashing is deterministic, so a key
  space an attacker can shape inherits Dart's general hash-collision
  characteristics. Keep attacker-controlled input out of key composition or
  pre-hash it with a random seed.

## Development

```sh
dart pub get
dart analyze --fatal-infos
dart test
dart test --coverage=coverage
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
dart run bench/bench.dart
dart run example/pepper_example.dart
```
