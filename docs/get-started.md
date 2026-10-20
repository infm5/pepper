# Get Started

This page covers installation, how a `HotCache` is put together, a quickstart,
and the behavior of TTL, load-through, negative caching and configuration.

## Installation

### Requirements

- **Dart 3.12.2 or newer** — the package's SDK constraint is `^3.12.2`.
- A **Dart VM** server: Serverpod, shelf, `dart:io`, or any other server-side
  Dart runtime. There is no Flutter dependency.
- **Zero runtime dependencies.**

### Add the dependency

Once the first pub.dev release is out:

```sh
dart pub add pepper
```

::: tip Or from the Github Repo 

```yaml
dependencies:
  pepper:
    git:
      url: https://github.com/infm5/pepper.git
```
:::

### Import

```dart
import 'package:pepper/pepper.dart';
```

## How it works

### The shape of a cache

`HotCache<K, V>` is a facade over four collaborating pieces:

```text
HotCache<K, V>
├── InMemoryCache<K, CacheEntry<V>>       LRU | LFU | FIFO
├── InMemoryCache<K, CacheEntry<V>>?      dedicated negative cache
├── LoadBatcher<K, V>?                    single-flight + same-turn batching
├── CacheMetrics?                         events and counters
└── TimeSource                            monotonic microseconds
```

The low-level `InMemoryCache` stores opaque `CacheEntry<V>` values and knows
nothing about time, loaders or negative caching. Those concerns live in the
facade. You can also use `LruCache`, `LfuCache` or `FifoCache` directly when
you only need an eviction policy.

### Entries and expiry

Every stored item is one of two sealed entry types:

```text
CacheEntry<V>
├── ValueEntry<V>     a value + expiryMicros
└── MissingEntry<V>   a negative entry + expiryMicros
```

`expiryMicros == 0` means **no expiry**. A non-zero value is an absolute
deadline on the monotonic clock. The public lookup result is a separate sealed
hierarchy:

```text
CacheLookup<V>
├── Present<V>   a value is stored
├── Missing<V>   the key is known to be missing
└── Absent<V>    nothing is known about the key
```

### Reads

```text
get(key)
  → InMemoryCache.get(key)         touches recency / frequency
  → missing entry?                 return null
  → expired?                       remove it, report TTL, return null
  → copyOnRead?                    return a copy
  → return the value
```

`peek`, `containsKey` and `lookup` do **not** touch recency or frequency.
`peek` ignores expiry; `containsKey` and `lookup` respect it. `get` is the
operation that updates the eviction policy's bookkeeping.

### Writes and eviction

```text
set(key, value)
  → wrap in a ValueEntry with expiry = now + ttl + jitter
  → cache full?                    evict one victim (algorithm-specific)
  → insert and update counters
```

Eviction happens **before** the insert, so `length` never exceeds `capacity`,
even transiently. The victim is chosen entirely by the algorithm; see
[Eviction Techniques](/eviction/).

### Load-through and singleflight

```text
getOrLoad(key)
  → value hit?                     return it
  → negative hit?                  return null
  → no loaders?                    return null
  → LoadBatcher.load(key)
      → same key already in flight? join that future
      → otherwise add to the pending batch and schedule a microtask
  → microtask flush: call the loader chain once for all pending keys
  → write loaded values and unresolved keys back to the cache
  → return the value (or null, or throw CacheLoadException)
```

The batcher is a `Map<K, Completer<LoadOutcome<V>>>` plus a pending `Set<K>`.
The first caller schedules a microtask; every key requested before that
microtask runs is passed to the loader chain in one call. Callers arriving
while a batch is in flight join the existing future instead of starting
another.

### Time and isolates

Expiry is computed from a `TimeSource` backed by `Stopwatch` in microseconds,
never from `DateTime.now`, so wall-clock changes cannot skew it. The clock is
injectable for deterministic tests. A cache without TTL and without a
per-entry expiry never reads the clock at all.

A Dart isolate executes synchronous code without interleaving, so `get`,
`set`, `delete` and the rest need no locks and have none. Only `getOrLoad`,
`getOrLoadMany` and `warmUp` are asynchronous.

### Complexity

| Operation | Cost |
|---|---|
| `get`, `set`, `peek`, `containsKey`, `lookup`, `delete` | **O(1)** expected — one hash lookup, plus O(1) list or bucket work |
| Eviction | **O(1)** — the victim is the tail/head of a linked list or the oldest entry in the minimum-frequency bucket |
| LFU `delete` when the minimum bucket empties | **O(F)** worst case, where `F` is the number of distinct live frequencies (≤ `length`) |
| `keys`, `values`, `all`, `forEach`, `purgeExpired` | **O(n)** |
| `getOrLoad` hit | O(1) + one future |
| `getOrLoad` miss | loader latency + O(batch size) |
| `warmUp` | O(values + missing) |

## Quickstart

### A basic cache

```dart
import 'package:pepper/pepper.dart';

final cache = HotCache<String, int>(
  algorithm: EvictionAlgorithm.lru,
  capacity: 1_000,
);

cache.set('a', 1);
cache.setMany({'b': 2, 'c': 3});

print(cache.get('a'));        // 1
print(cache.getAll(['a', 'x'])); // {a: 1}
print(cache.length);          // 3
```

### TTL, jitter and a janitor

```dart
final cache = HotCache<String, int>(
  algorithm: EvictionAlgorithm.lru,
  capacity: 1_000,
  ttl: const Duration(minutes: 5),
  jitter: const Duration(seconds: 30),
  janitor: true, // sweeps expired entries every 5 minutes
);

cache.set('session', 1);
cache.setWithTTL('one-off', 2, const Duration(seconds: 10));

cache.dispose(); // always cancel the janitor when the cache is no longer used
```

### Telling absence from a negative entry

```dart
switch (cache.lookup('user:42')) {
  case Present(:final value):
    print('found $value');
  case Missing():
    print('known to be missing');
  case Absent():
    print('not cached');
}
```

### Loading a miss

```dart
final cache = HotCache<int, User>(
  algorithm: EvictionAlgorithm.lru,
  capacity: 10_000,
  ttl: const Duration(minutes: 5),
  missingCache: const MissingCacheConfig.shared(),
  loaders: [loadUsers],
);

Future<Map<int, User>> loadUsers(Set<int> ids) async {
  final rows = await db.usersByIds(ids);
  return {for (final row in rows) row.id: row};
}

final user = await cache.getOrLoad(42);
```

Concurrent `getOrLoad(42)` calls share one loader invocation, and keys
requested in the same event-loop turn are batched into one call.

### Metrics

```dart
final metrics = SimpleCacheMetrics();
final cache = HotCache<String, int>(
  algorithm: EvictionAlgorithm.lru,
  capacity: 1_000,
  metrics: metrics,
);

cache.get('a');
print(metrics.hitRate);
print(metrics.evictions(EvictionReason.capacity));
```

## Configuration

### Constructor

```dart
HotCache({
  required EvictionAlgorithm algorithm,
  required int capacity,
  Duration? ttl,
  Duration? jitter,
  bool janitor = false,
  Duration? janitorInterval,
  MissingCacheConfig? missingCache,
  List<Loader<K, V>> loaders = const [],
  EvictionCallback<K, V>? onEviction,
  V Function(V value)? copyOnWrite,
  V Function(V value)? copyOnRead,
  CacheMetrics? metrics,
  TimeSource? timeSource,
  Random? random,
})
```

| Parameter | Default | Meaning |
|---|---|---|
| `algorithm` | required | `lru`, `lfu` or `fifo` |
| `capacity` | required | Maximum number of **entries** (not bytes); at least 1 |
| `ttl` | `null` | Default lifetime for every entry; `null` means no expiry |
| `jitter` | `null` | Additive uniform delay in `[0, jitter)` on every write with a TTL |
| `janitor` | `false` | Start a `Timer.periodic` that calls `purgeExpired()` |
| `janitorInterval` | equals `ttl` | Janitor period; required when `janitor` is true and `ttl` is null |
| `missingCache` | `null` | Enable negative caching: `.shared()` or `.dedicated(...)` |
| `loaders` | `[]` | Ordered loader chain used by `getOrLoad`/`getOrLoadMany` |
| `onEviction` | `null` | Synchronous callback for capacity and TTL evictions |
| `copyOnWrite` | `null` | Copy a value before storing it |
| `copyOnRead` | `null` | Copy a value before returning it |
| `metrics` | `null` | `CacheMetrics` sink |
| `timeSource` | `MonotonicTimeSource.shared` | Injectable clock (tests/custom environments) |
| `random` | `Random()` | Injectable randomness for jitter |

### Validation

| Situation | Result |
|---|---|
| `capacity < 1` | `ArgumentError` |
| `ttl <= 0`, `jitter <= 0`, `janitorInterval <= 0` | `ArgumentError` |
| `janitor: true` without `ttl` and without `janitorInterval` | `ArgumentError` |
| `MissingCacheConfig.dedicated(capacity: 0)` | `ArgumentError` |
| `setWithTTL` / `setMissingWithTTL` with a non-positive duration | `ArgumentError` |
| `setMissing*` without a configured missing cache | `StateError` |
| `warmUp` with missing keys and no missing cache | `StateError`; nothing is stored |

::: tip Why is there no default TTL?
TTL is a freshness decision, not a memory-safety one — capacity already bounds
memory. A library-chosen default would silently trade stale reads against
premature evictions, and no single value is right for sessions, profiles,
configuration and reference data. Set `ttl` explicitly, and use `setWithTTL`
for exceptions.
:::

### Capacity, TTL and sizing

`capacity` counts entries, not bytes. If you need a memory bound, size it from
your value size:

```text
capacity ≈ memory budget / (key + value + ~100 bytes of bookkeeping)
```

TTL and capacity are independent. An entry leaves when **either** the eviction
policy needs room or its deadline passes, whichever comes first.

In steady state, every new-key insertion at capacity evicts exactly one entry,
so the average entry lifetime follows Little's Law:

```text
mean lifetime ≈ capacity / new-key insertions per second
```

| Capacity | Insertions/s | Mean lifetime |
|---:|---:|---:|
| 1,000 | 1 | ~16.7 min |
| 1,000 | 10 | ~100 s |
| 1,000 | 50 | ~20 s |
| 1,000 | 90 | ~11 s |
| 1,000 | 100 | ~10 s |
| 10,000 | 10 | ~16.7 min |
| 100 | 90 | ~1.1 s |

Requests per second alone do not determine lifetime: only requests that store
a **new** key do. A hit never evicts. At 100 req/s with a 90% miss rate and a
1,000-entry cache, an untouched entry reaches the LRU tail after roughly
1,000 / 90 ≈ 11 seconds and is evicted on the next miss.

::: warning Multi-isolate servers
Each Dart isolate has its own cache and its own memory. A Serverpod deployment
with 8 isolates and `capacity: 100_000` holds up to 800,000 entries
process-wide. Size per isolate, not for the whole process.
:::

## TTL

### API

```dart
final cache = HotCache<String, int>(
  algorithm: EvictionAlgorithm.lru,
  capacity: 1_000,
  ttl: const Duration(minutes: 5),
  jitter: const Duration(seconds: 30),
  janitor: true,
);

cache.setWithTTL('short', 1, const Duration(seconds: 10));
cache.setMissingWithTTL('missing', const Duration(seconds: 10));
cache.purgeExpired(); // eager sweep; returns how many entries were removed
cache.dispose();      // stops the janitor; idempotent
```

### Expiry semantics

- The deadline is computed **at write time** as `now + ttl + jitter`.
- `expiryMicros == 0` means the entry never expires.
- `setWithTTL` overrides the cache-wide TTL for one entry. Jitter is still
  added from the cache-wide `jitter` setting.
- Negative entries have TTLs too.
- The janitor is optional. Without it, expiry is applied lazily on `get` and
  `getOrLoad`, and eagerly when you call `purgeExpired()`.

### Jitter

Jitter is an additive uniform delay in `[0, jitter)` applied to **every write
path**: `set`, `setWithTTL`, `setMany`, loader write-back and warm-up. It
spreads expirations out so a batch of entries written together does not expire
together and stampede the loader.

The implementation uses `Random.nextDouble()`, so jitter windows are not
limited by the 32-bit `Random.nextInt` bound. A 30-day jitter window is a
supported, tested case.

### Query behavior

| Operation | Expired entry |
|---|---|
| `get`, `getOrLoad` | Removed; `null`; fires a TTL eviction |
| `getAll` | Omitted |
| `containsKey` | `false` |
| `lookup` | `Absent` (not removed by this call) |
| `peek` | **Returned** — peek deliberately ignores expiry |
| `keys`, `values`, `all`, `forEach` | Hidden |
| `purgeExpired` | Removed; returns the count |

### No stale window yet

TTL here is a hard deadline. Stale-while-revalidate is not implemented: the
first caller after expiry pays the loader latency, and concurrent callers
share that load.

## Load-through

### Loader chains

```dart
typedef Loader<K, V> = Future<Map<K, V>> Function(Set<K> keys);
```

- A loader receives only the keys that are still unresolved.
- It returns a map of found values. Omitted keys are treated as **not found**;
  `null` values are also treated as not found.
- Keys outside the requested set may be returned and are cached too.
- Loaders run in order. The first error aborts the chain and discards the
  batch's results.
- Each loader can be a different source: memory, database, HTTP, and so on.

### Singleflight and batching

| Behavior | Detail |
|---|---|
| Same-key deduplication | Concurrent calls for one key share one future and one loader call |
| Same-turn batching | Keys requested before the flush microtask runs are passed to the loader chain together |
| In-flight joins | Callers arriving while a batch is running join it, even across event-loop turns |
| Write-back before completion | Loaded values and negative entries are stored before waiters resume, so the next call hits the cache |
| Error fan-out | Every waiter receives the error; in-flight entries are removed so a retry can start |
| Failed batch isolation | A failed batch does not poison later loads |

The hot path pays nothing: the batcher is only consulted on a miss.

::: warning Single-flight is per isolate
Each isolate has its own in-flight registry. A deployment with 8 isolates can
run up to 8 concurrent loads for the same key — still one per isolate rather
than one per request. A globally deduplicated load needs an external lock.
:::

### Errors

`getOrLoad` throws a `CacheLoadException` when a loader fails:

```dart
try {
  final user = await cache.getOrLoad(42);
} on CacheLoadException catch (error) {
  print('failed to load ${error.key}: ${error.cause}');
}
```

`getOrLoadMany` never throws for loader failures. It returns a `LoadResult`:

```dart
final result = await cache.getOrLoadMany({1, 2, 3});
result.values;  // cached or loaded values
result.missing; // negative-cache hits and keys the loaders did not return
result.failed;  // keys whose load threw
result.error;   // the first error, if any
result.hasError;
```

### Write-back semantics

A value stored for a key **while its load is in flight** is overwritten when
the load completes. The loader result wins.

### Timeouts

The cache does not impose a timeout on loaders. Give database or HTTP loaders
their own timeout; a hung future pins its keys in the in-flight registry until
it settles.

### Negative caching integration

When negative caching is enabled, every key the loader chain does not return
is stored as a negative entry. The next `getOrLoad` for that key returns
`null` without calling the loaders again, until the negative entry expires or
is removed.

## Negative caching

### Modes

```dart
// Shared: negative entries live in the main cache, with the same algorithm
// and capacity.
missingCache: const MissingCacheConfig.shared()

// Dedicated: separate algorithm and capacity.
missingCache: const MissingCacheConfig.dedicated(
  algorithm: EvictionAlgorithm.lru,
  capacity: 500,
)
```

| Mode | Capacity | Algorithm |
|---|---|---|
| `shared()` | Live + negative entries **share** `capacity`; `length + missingLength ≤ capacity` | Same as the main cache |
| `dedicated(...)` | Independent capacity for negative entries | Its own algorithm |

In shared mode a flood of negative entries can evict live values. If negative
traffic is significant, use a dedicated cache.

### Lookup types

| Operation | Live value | Negative entry | Absent |
|---|---|---|---|
| `lookup` | `Present(value)` | `Missing()` | `Absent()` |
| `get` / `getAll` | value | `null` / omitted | `null` / omitted |
| `containsKey` | `true` | `false` | `false` |
| `peek` | value | `null` | `null` |
| `keys` / `values` / `all` | included | excluded | excluded |

`length` counts live values only; `missingLength` counts negative entries.

### Operations

- `setMissing`, `setMissingWithTTL`, `setMissingMany` create negative entries.
- `set` or `setWithTTL` for the same key clears the negative entry.
- `delete` removes a live entry **and** a negative entry for the key.
- `purge` clears both caches.
- `purgeExpired` sweeps both.
- Negative entries expire on their own TTL and are counted by the metrics.

## Core operations

| Method | Returns | Notes |
|---|---|---|
| `set(key, value)` | `void` | Replaces an existing value; clears a negative entry |
| `setWithTTL(key, value, ttl)` | `void` | Per-entry TTL override |
| `setMany(Map<K, V>)` | `void` | Applies in input order |
| `setMissing(key)` / `setMissingWithTTL` / `setMissingMany` | `void` | Requires negative caching |
| `get(key)` | `V?` | Touches recency/frequency; removes expired entries |
| `getAll(Iterable<K>)` | `Map<K, V>` | Omits absent, expired and negative keys |
| `peek(key)` | `V?` | No touch, no expiry check, `null` for negative |
| `containsKey(key)` | `bool` | Respects expiry; `false` for negative |
| `lookup(key)` | `CacheLookup<V>` | `Present` / `Missing` / `Absent` |
| `keys()`, `values()`, `all()` | `List<K>`, `List<V>`, `Map<K, V>` | Hide expired; order unspecified |
| `forEach(action)` | `void` | Snapshots live entries; return `false` to stop |
| `delete(key)` | `bool` | Removes live and negative entries |
| `deleteMany(Iterable<K>)` | `int` | Count of keys removed |
| `purge()` | `void` | Clears both caches and resets counters |
| `purgeExpired()` | `int` | Removes expired entries from both caches |
| `getOrLoad(key)` | `Future<V?>` | Throws `CacheLoadException` on loader failure |
| `getOrLoadMany(Set<K>)` | `Future<LoadResult<K, V>>` | Partial results; never throws for loader failures |
| `warmUp(loader, {timeout})` | `Future<void>` | Preload values and known-missing keys |
| `dispose()` | `void` | Cancels the janitor; cache remains usable |

**Iteration order is unspecified.** The index is a `HashMap`, so `keys`,
`values`, `all`, `forEach` and `getAll` do not promise an order. Eviction order
and counters are deterministic.

### Copy hooks

`copyOnWrite` copies a value before storing it; `copyOnRead` copies a value
before returning it. Use them for mutable values (lists, maps, mutable
objects) so callers cannot mutate cached state and the cache cannot retain a
caller-owned object.

```dart
final cache = HotCache<String, List<int>>(
  algorithm: EvictionAlgorithm.lru,
  capacity: 100,
  copyOnWrite: (value) => List<int>.of(value),
  copyOnRead: (value) => List<int>.of(value),
);
```

### Warm-up

```dart
await cache.warmUp(
  () async => WarmUpData<int, User>(
    values: await db.recentUsers(),
    missing: await db.knownMissingIds(),
  ),
  timeout: const Duration(seconds: 5),
);
```

- Values and missing keys are applied after the loader completes.
- Missing keys require a configured missing cache, otherwise a `StateError` is
  thrown and **nothing** is stored.
- A timeout throws `TimeoutException`; nothing is stored.
- Warm-up values receive the cache-wide TTL and jitter.

### Reentrancy

Eviction callbacks and metrics sinks run synchronously on the operation that
triggered them.

- Callbacks may **read** from the cache.
- Storing, deleting or purging from an eviction callback throws `StateError`.
  The cache is mid-eviction and must stay consistent.
- An exception thrown by a callback propagates to the caller of the operation,
  after the victim has already been removed.
- `forEach` snapshots the live entries first, so its action may modify the
  cache.

## Metrics and callbacks

### Cache metrics

Extend `CacheMetrics` and override the events you need:

| Event | Fired when |
|---|---|
| `onHit` / `onMiss` | A lookup finds / does not find a value (negative hits count as misses) |
| `onInsert` | An entry is stored, including loaded, negative and warm-up entries |
| `onEviction(reason)` | An entry leaves: capacity, TTL, or an explicit `delete` (`manual`) |
| `onPurge` | `purge()` is called |
| `onLoad` / `onLoadError` | A loader batch succeeds / fails |
| `onLength` / `onMissingLength` | The live / negative count changes |

### SimpleCacheMetrics

`SimpleCacheMetrics` implements the sink with cumulative counters and
convenience getters:

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
```

| Member | Meaning |
|---|---|
| `hits` / `misses` | Value hits and misses (negative hits count as misses) |
| `hitRate` | `hits / (hits + misses)`; `0` before the first lookup |
| `inserts` | Stored entries, including loaded, negative and warm-up entries |
| `totalEvictions` | All recorded evictions: capacity, TTL and manual `delete` |
| `evictions(reason)` | Per-reason count: `capacity`, `ttl`, `manual` |
| `loads` / `loadErrors` | Successful and failed loader batches |
| `purges` | `purge()` calls |
| `length` / `missingLength` | Current live and negative entry counts |

Metrics are recorded by `get`, `getAll`, `getOrLoad` and `getOrLoadMany`.
`peek`, `containsKey` and `lookup` do not record hits or misses. A sink may be
shared by several caches; its callbacks run synchronously, so they must be
cheap and must not call back into the cache.

### Eviction callback

The `onEviction` constructor callback is different from the metrics stream:

- It fires for **capacity** and **TTL** evictions only, with the key and value.
- It does **not** fire for explicit `delete` or `purge`.
- It runs after the victim has been removed and before the replacement is
  inserted.

```dart
final cache = HotCache<String, int>(
  algorithm: EvictionAlgorithm.lru,
  capacity: 100,
  onEviction: (reason, key, value) {
    print('$key=$value left because of $reason');
  },
);
```

### Hit rate and mean residency

- **Hit rate** = `hits / (hits + misses)`.
- **Mean entry lifetime** = `length / eviction rate` (Little's Law). With
  `SimpleCacheMetrics`, use the delta in evictions over a time window:

```dart
final rate = (metrics.totalEvictions - before) / elapsedSeconds;
final meanResidency = cache.length / rate;
```

## Production notes

| Area | Guidance |
|---|---|
| Isolate model | One cache per isolate. Memory, counters and single-flight are per isolate. |
| Janitor | Call `dispose()` when a cache is no longer used; per-request caches will otherwise leak a timer. |
| Loaders | Give database and HTTP loaders a timeout. A hung future pins its keys in the in-flight registry. |
| Callbacks | Eviction callbacks may read the cache but must not mutate it; exceptions propagate after the victim is removed. |
| Sizing | `capacity` counts entries, not bytes. Measure value size and leave headroom; there is no `SizeBytes` in v0.1.0. |
| Adversarial keys | Dart string hashing is deterministic. Keep attacker-controlled input out of keys or pre-hash it with a random seed. |
| Persistence | None. A restart starts empty; `pepper` is an in-process cache. |
| Distributed state | None. Each isolate and process is independent; use Redis or Memcached when state must be shared. |
| Release maturity | v0.1.0 is pre-release. Pin the version and canary it before critical production use. |

## Next steps

- [Eviction Techniques](/eviction/) — how LRU, LFU and FIFO choose a victim.
- [Example](/example) — the complete runnable example.
