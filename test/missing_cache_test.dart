import 'package:pepper/pepper.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('shared missing cache', () {
    late HotCache<String, int> cache;

    setUp(() {
      cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 3,
        missingCache: const MissingCacheConfig.shared(),
      );
    });

    test('setMissing stores a negative entry', () {
      cache.setMissing('a');
      expect(cache.get('a'), isNull);
      expect(cache.lookup('a'), isA<Missing<int>>());
      expect(cache.missingLength, 1);
      expect(cache.length, 0);
    });

    test('negative entries are invisible to iteration', () {
      cache.set('a', 1);
      cache.setMissing('b');
      expect(cache.keys(), ['a']);
      expect(cache.values(), [1]);
      expect(cache.all(), {'a': 1});
      expect(cache.containsKey('b'), isFalse);
      var visited = 0;
      cache.forEach((key, value) {
        visited++;
        return true;
      });
      expect(visited, 1);
    });

    test('storing a value clears the negative entry', () {
      cache.setMissing('a');
      cache.set('a', 1);
      expect(cache.lookup('a'), isA<Present<int>>());
      expect(cache.missingLength, 0);
      expect(cache.length, 1);
    });

    test('marking a stored key as missing clears the value', () {
      cache.set('a', 1);
      cache.setMissing('a');
      expect(cache.lookup('a'), isA<Missing<int>>());
      expect(cache.length, 0);
      expect(cache.missingLength, 1);
    });

    test('setMissingMany marks every key', () {
      cache.setMissingMany(['a', 'b']);
      expect(cache.missingLength, 2);
    });

    test('delete removes negative entries', () {
      cache.setMissing('a');
      expect(cache.delete('a'), isTrue);
      expect(cache.missingLength, 0);
    });

    test('purge clears negative entries', () {
      cache.setMissing('a');
      cache.purge();
      expect(cache.missingLength, 0);
    });

    test('negative entries share the main capacity', () {
      cache.setMissing('a');
      cache.setMissing('b');
      cache.setMissing('c');
      cache.setMissing('d');
      expect(cache.missingLength, 3);
      expect(cache.lookup('a'), isA<Absent<int>>());
      expect(cache.lookup('d'), isA<Missing<int>>());
    });

    test('negative entries respect the cache ttl', () {
      final time = FakeTime();
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 3,
        ttl: const Duration(minutes: 1),
        timeSource: time,
        missingCache: const MissingCacheConfig.shared(),
      );
      cache.setMissing('a');
      time.advance(const Duration(minutes: 1));
      expect(cache.lookup('a'), isA<Absent<int>>());
      expect(cache.missingLength, 1);
      expect(cache.get('a'), isNull);
      expect(cache.missingLength, 0);
    });

    test('setMissingWithTTL overrides the cache ttl', () {
      final time = FakeTime();
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 3,
        ttl: const Duration(minutes: 1),
        timeSource: time,
        missingCache: const MissingCacheConfig.shared(),
      );
      cache.setMissingWithTTL('a', const Duration(seconds: 10));
      time.advance(const Duration(seconds: 10));
      expect(cache.lookup('a'), isA<Absent<int>>());
    });

    test('purgeExpired removes expired negative entries', () {
      final time = FakeTime();
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 3,
        ttl: const Duration(minutes: 1),
        timeSource: time,
        missingCache: const MissingCacheConfig.shared(),
      );
      cache.setMissing('a');
      time.advance(const Duration(minutes: 1));
      expect(cache.purgeExpired(), 1);
      expect(cache.missingLength, 0);
    });
  });

  group('dedicated missing cache', () {
    late HotCache<String, int> cache;

    setUp(() {
      cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 2,
        missingCache: const MissingCacheConfig.dedicated(
          algorithm: EvictionAlgorithm.lfu,
          capacity: 2,
        ),
      );
    });

    test('negative entries live outside the main capacity', () {
      cache.set('a', 1);
      cache.set('b', 2);
      cache.setMissing('x');
      cache.setMissing('y');
      cache.setMissing('z');
      expect(cache.length, 2);
      expect(cache.missingLength, 2);
      expect(cache.get('a'), 1);
      expect(cache.get('b'), 2);
    });

    test('negative entries are evicted independently of values', () {
      cache.setMissing('x');
      cache.setMissing('y');
      cache.setMissing('z');
      expect(cache.missingLength, 2);
      expect(cache.lookup('x'), isA<Absent<int>>());
    });

    test('storing a value clears the dedicated negative entry', () {
      cache.setMissing('a');
      cache.set('a', 1);
      expect(cache.length, 1);
      expect(cache.missingLength, 0);
      expect(cache.get('a'), 1);
    });

    test('marking a stored key as missing clears the value', () {
      cache.set('a', 1);
      cache.setMissing('a');
      expect(cache.length, 0);
      expect(cache.missingLength, 1);
      expect(cache.get('a'), isNull);
    });

    test('delete removes entries from both caches', () {
      cache.set('a', 1);
      cache.setMissing('a');
      expect(cache.delete('a'), isTrue);
      expect(cache.length, 0);
      expect(cache.missingLength, 0);
    });

    test('missing lookups on absent keys report nothing', () {
      expect(cache.get('unknown'), isNull);
      expect(cache.peek('unknown'), isNull);
      expect(cache.lookup('unknown'), isA<Absent<int>>());
      expect(cache.missingLength, 0);
    });

    test('expired negative entries are removed on access', () {
      final time = FakeTime();
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 2,
        ttl: const Duration(seconds: 1),
        timeSource: time,
        missingCache: const MissingCacheConfig.dedicated(
          algorithm: EvictionAlgorithm.lru,
          capacity: 2,
        ),
      );
      cache.setMissing('x');
      time.advance(const Duration(seconds: 1));
      expect(cache.get('x'), isNull);
      expect(cache.missingLength, 0);
    });

    test('replacing a negative entry keeps the counters exact', () {
      cache.setMissing('a');
      cache.setMissing('a');
      expect(cache.missingLength, 1);
      cache.setMissingWithTTL('a', const Duration(seconds: 10));
      expect(cache.missingLength, 1);
    });

    test('purgeExpired cleans expired negative entries', () {
      final time = FakeTime();
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 2,
        ttl: const Duration(seconds: 1),
        timeSource: time,
        missingCache: const MissingCacheConfig.dedicated(
          algorithm: EvictionAlgorithm.lru,
          capacity: 2,
        ),
      );
      cache.setMissing('x');
      cache.setMissing('y');
      time.advance(const Duration(seconds: 1));
      expect(cache.purgeExpired(), 2);
      expect(cache.missingLength, 0);
    });

    test('purge clears both caches', () {
      cache.set('a', 1);
      cache.setMissing('x');
      cache.purge();
      expect(cache.length, 0);
      expect(cache.missingLength, 0);
    });
  });
}
