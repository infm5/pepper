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
