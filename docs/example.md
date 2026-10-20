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
