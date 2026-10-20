import 'dart:math';

import 'package:pepper/pepper.dart';
import 'package:test/test.dart';

/// Sustained-load checks that every structure stays bounded and exact.
void main() {
  group('stress', () {
    test('facade stays bounded under sustained mixed load', () {
      final random = Random(5);
      final cache = HotCache<int, int>(
        algorithm: EvictionAlgorithm.lfu,
        capacity: 1000,
        missingCache: const MissingCacheConfig.shared(),
      );
      for (var i = 0; i < 1000000; i++) {
        final key = random.nextInt(20000);
        switch (random.nextInt(4)) {
          case 0:
            cache.set(key, i);
          case 1:
            cache.get(key);
          case 2:
            cache.setMissing(key);
          case 3:
            cache.delete(key);
        }
      }
      expect(cache.length + cache.missingLength, lessThanOrEqualTo(1000));
      expect(cache.keys().length, cache.length);
    });

    test('low-level caches stay bounded under sustained load', () {
      final random = Random(6);
      final caches = <InMemoryCache<int, int>>[
        LruCache<int, int>(capacity: 512),
        LfuCache<int, int>(capacity: 512),
        FifoCache<int, int>(capacity: 512),
      ];
      for (var i = 0; i < 500000; i++) {
        final key = random.nextInt(5000);
        for (final cache in caches) {
          if (random.nextBool()) {
            cache.set(key, i);
          } else {
            cache.get(key);
          }
        }
      }
      for (final cache in caches) {
        expect(cache.length, 512, reason: cache.algorithm);
      }
    });

    test('load-through stays exact under concurrent pressure', () async {
      var loads = 0;
      final cache = HotCache<int, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 100,
        missingCache: const MissingCacheConfig.shared(),
        loaders: [
          (keys) async {
            loads++;
            await Future<void>.delayed(Duration.zero);
            return {
              for (final key in keys)
                if (key % 10 != 0) key: key,
            };
          },
        ],
      );

      final futures = <Future<Object?>>[];
      for (var round = 0; round < 1000; round++) {
        futures.add(cache.getOrLoad(round % 50));
      }
      await Future.wait(futures);
      expect(loads, 1);
      expect(cache.length + cache.missingLength, lessThanOrEqualTo(100));

      for (var round = 0; round < 1000; round++) {
        await cache.getOrLoad(round % 50);
      }
      expect(loads, 1);
    });
  });
}
