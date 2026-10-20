# Example

The complete runnable example lives at
[`example/pepper_example.dart`](https://github.com/infm5/pepper/blob/master/example/pepper_example.dart).
It exercises synchronous access, single-flight load-through, batch loading,
negative caching and the janitor lifecycle.

## The code

```dart
import 'package:pepper/pepper.dart';

const _database = {1: 'ada', 2: 'grace', 3: 'alan', 4: 'edsger'};
var _loaderCalls = 0;

Future<void> main() async {
  final cache = HotCache<int, String>(
    algorithm: EvictionAlgorithm.lru,
    capacity: 1_000,
    ttl: const Duration(minutes: 5),
    jitter: const Duration(seconds: 10),
    janitor: true,
    missingCache: const MissingCacheConfig.shared(),
    loaders: [_loadUsers],
    onEviction: (reason, key, value) {
      print('evicted $key ($value) because of $reason');
    },
  );

  // Synchronous access.
  cache.set(1, 'ada');
  print(cache.get(1)); // ada
  print(cache.lookup(1)); // Present(ada)
  print(cache.lookup(42)); // Absent()

  // Load-through: concurrent misses for the same key share one loader call.
  final users = await Future.wait([cache.getOrLoad(2), cache.getOrLoad(2)]);
  print(users); // [grace, grace]
  print('loader calls so far: $_loaderCalls'); // 1

  // Batch load-through: unresolved keys are negative-cached.
  final result = await cache.getOrLoadMany({3, 4, 99});
  print(result.values); // {3: alan, 4: edsger}
  print(result.missing); // {99}

  // The negative entry short-circuits the next load.
  print(await cache.getOrLoad(99)); // null
  print('loader calls so far: $_loaderCalls'); // 2

  print('stored: ${cache.length}, negative: ${cache.missingLength}');

  cache.dispose();
}

Future<Map<int, String>> _loadUsers(Set<int> keys) async {
  _loaderCalls++;
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return {
    for (final key in keys)
      if (_database.containsKey(key)) key: _database[key]!,
  };
}
```

## Output

```text
ada
Present(ada)
Absent()
[grace, grace]
loader calls so far: 1
{3: alan, 4: edsger}
{99}
null
loader calls so far: 2
stored: 4, negative: 1
```

## What each part demonstrates

### Construction

```dart
HotCache<int, String>(
  algorithm: EvictionAlgorithm.lru,
  capacity: 1_000,
  ttl: const Duration(minutes: 5),
  jitter: const Duration(seconds: 10),
  janitor: true,
  missingCache: const MissingCacheConfig.shared(),
  loaders: [_loadUsers],
  onEviction: (reason, key, value) { ... },
)
```

- **LRU** with a 1,000-entry bound.
- **5-minute TTL** with up to **10 seconds of jitter**, so entries written
  together do not expire together.
- **Janitor** sweeps expired entries every 5 minutes (the default interval is
  the TTL). `dispose()` cancels it.
- **Shared negative cache** so misses can be remembered.
- **One loader** for users.
- **Eviction callback** for capacity and TTL evictions. This example stores
  only a handful of keys, so no eviction fires; the callback is there to show
  the shape.

### Synchronous access

```dart
cache.set(1, 'ada');
cache.get(1);        // ada
cache.lookup(1);     // Present(ada)
cache.lookup(42);    // Absent()
```

`get` returns `null` for absent, expired and negative keys. `lookup` tells
those states apart with the sealed `Present` / `Missing` / `Absent` hierarchy.

### Single-flight

```dart
final users = await Future.wait([cache.getOrLoad(2), cache.getOrLoad(2)]);
print(users);                               // [grace, grace]
print('loader calls so far: $_loaderCalls'); // 1
```

Both calls are made in the same event-loop turn for the same key. The first
creates an in-flight entry; the second joins it. One loader invocation serves
both waiters.

### Batch loading and negative caching

```dart
final result = await cache.getOrLoadMany({3, 4, 99});
result.values;   // {3: alan, 4: edsger}
result.missing;  // {99}
```

The loader returns values for 3 and 4. Key 99 is omitted, so the loader chain
reports it as not found and — because negative caching is enabled — stores a
negative entry for it. The loader call count is now 2: one for key 2, one for
the batch `{3, 4, 99}`.

### Negative hit

```dart
print(await cache.getOrLoad(99));          // null
print('loader calls so far: $_loaderCalls); // 2
```

The negative entry short-circuits the load. The loader is not called a third
time. Without a negative cache, the same call would load again.

### Counters

```dart
print('stored: ${cache.length}, negative: ${cache.missingLength}');
// stored: 4, negative: 1
```

Four live values (1, 2, 3, 4) and one negative entry (99). `length` never
includes negative entries; `missingLength` does.

### Cleanup

```dart
cache.dispose();
```

Cancels the janitor timer. Disposing is idempotent and does not invalidate the
cache — it remains usable for synchronous operations.

## Run it yourself

```sh
dart run example/pepper_example.dart
```

## Real-world prototype: Relic Vault

The repository also contains a complete Relic + SQLite application in
[`example/relic_vault`](https://github.com/infm5/pepper/tree/master/example/relic_vault).
It is a read-heavy relic catalog with a small browser UI:

- `GET /api/relics/:id` — cached detail
- `GET /api/relics?ids=1,2,3` — cached batch reads
- `GET /api/relics?q=gold&limit=20` — cached search
- `PUT /api/relics/:id` — update and invalidation
- `GET /api/cache/stats` — hits, misses, evictions, DB queries and RSS

The service keeps a detail cache and a separate search cache. Detail entries
use a dedicated negative cache, so repeated 404s do not reach SQLite. Cache
values are encoded JSON, which means a hit avoids both the database and
serialization. Writes replace the detail entry and purge search results.

Run it from the repository root:

```sh
cd example/relic_vault
dart pub get
dart run bin/seed.dart --db=data/relics.db --count=50000
dart run bin/server.dart --db=data/relics.db
```

The full end-to-end benchmark uses `oha` against the compiled server:

```sh
dart run bench/run.dart --profile=full
```

It compares no cache vs pepper, local SQLite vs simulated remote-database
latency, LRU vs LFU, capacity sweeps, a cold-start stampede and repeated 404s.
The generated report, including methodology and caveats, is at
[`example/relic_vault/bench/results/latest.md`](https://github.com/infm5/pepper/blob/master/example/relic_vault/bench/results/latest.md).

### Reference run

On an Apple M5 with 16 GB, Dart 3.12.2 and Relic 1.2.0 (100,000-URL trace,
64 connections, three 20-second runs, 5-minute cache TTL):

| Workload | No cache | pepper LRU, 10k |
|---|---:|---:|
| local SQLite | 1,116 req/s · p99 111 ms · 1.00 DB q/req | 21,562 req/s · p99 14.3 ms · 0.18 DB q/req |
| 2 ms backend | 1,109 req/s · p99 113 ms · 1.00 DB q/req | 20,450 req/s · p99 21.1 ms · 0.18 DB q/req |

The detail cache hit **82%** and the search cache **97%**. A 1,000-request cold
burst issued **1** SQLite query with pepper versus **1,000** without; the same
held for the 404 burst via negative caching. Capacity matters: 28% hit rate at
100 entries, 53% at 1k, 82% at 10k and 95% at 50k. LFU reached 83.8% versus
LRU's 82.1%, but was slightly slower (19.6k versus 20.5k req/s) on this
workload.

The mixed trace includes an intentionally expensive `LIKE` search, so the
no-cache baseline is dominated by those scans. Absolute numbers are
machine-specific; the report contains the full matrix and caveats.
