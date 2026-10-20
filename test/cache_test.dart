import 'package:pepper/pepper.dart';
import 'package:test/test.dart';

void main() {
  group('HotCache construction', () {
    test('rejects capacities below 1', () {
      expect(
        () => HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a non-positive ttl', () {
      expect(
        () => HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 1,
          ttl: Duration.zero,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a non-positive jitter', () {
      expect(
        () => HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 1,
          jitter: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a janitor without ttl or interval', () {
      expect(
        () => HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 1,
          janitor: true,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a non-positive janitor interval', () {
      expect(
        () => HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 1,
          janitor: true,
          janitorInterval: Duration.zero,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a dedicated missing cache with capacity below 1', () {
      expect(
        () => HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 1,
          missingCache: const MissingCacheConfig.dedicated(
            algorithm: EvictionAlgorithm.lru,
            capacity: 0,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('exposes its configuration', () {
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lfu,
        capacity: 10,
      );
      expect(cache.algorithm, EvictionAlgorithm.lfu);
      expect(cache.capacity, 10);
      expect(cache.length, 0);
      expect(cache.missingLength, 0);
    });
  });

  group('HotCache sync access', () {
    late HotCache<String, int> cache;

    setUp(() {
      cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 3,
      );
    });

    test('set and get round-trip', () {
      cache.set('a', 1);
      expect(cache.get('a'), 1);
      expect(cache.length, 1);
    });

    test('get returns null for unknown keys', () {
      expect(cache.get('unknown'), isNull);
      expect(cache.length, 0);
    });

    test('lookup distinguishes present and absent keys', () {
      cache.set('a', 1);
      final present = cache.lookup('a');
      expect(present, isA<Present<int>>());
      expect((present as Present<int>).value, 1);
      expect(cache.lookup('b'), isA<Absent<int>>());
    });

    test('peek does not update recency', () {
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);
      cache.peek('a');
      cache.set('d', 4);
      expect(cache.containsKey('a'), isFalse);
    });

    test('get updates recency', () {
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);
      cache.get('a');
      cache.set('d', 4);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('b'), isFalse);
    });

    test('containsKey reports stored values', () {
      cache.set('a', 1);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('b'), isFalse);
    });

    test('setMany stores every entry', () {
      cache.setMany({'a': 1, 'b': 2});
      expect(cache.get('a'), 1);
      expect(cache.get('b'), 2);
      expect(cache.length, 2);
    });

    test('setMany respects capacity', () {
      cache.setMany({'a': 1, 'b': 2, 'c': 3, 'd': 4, 'e': 5});
      expect(cache.length, 3);
    });

    test('getAll returns found values only', () {
      cache.set('a', 1);
      cache.set('c', 3);
      expect(cache.getAll(['a', 'b', 'c']), {'a': 1, 'c': 3});
    });

    test('delete removes entries and reports presence', () {
      cache.set('a', 1);
      expect(cache.delete('a'), isTrue);
      expect(cache.delete('a'), isFalse);
      expect(cache.get('a'), isNull);
      expect(cache.length, 0);
    });

    test('deleteMany counts removed entries', () {
      cache.set('a', 1);
      cache.set('b', 2);
      expect(cache.deleteMany(['a', 'b', 'c']), 2);
      expect(cache.length, 0);
    });

    test('purge clears the cache', () {
      cache.setMany({'a': 1, 'b': 2});
      cache.purge();
      expect(cache.length, 0);
      expect(cache.get('a'), isNull);
      expect(cache.keys(), isEmpty);
    });

    test('keys returns stored keys', () {
      cache.setMany({'a': 1, 'b': 2});
      expect(cache.keys(), unorderedEquals(['a', 'b']));
    });

    test('values returns stored values', () {
      cache.setMany({'a': 1, 'b': 2});
      expect(cache.values(), unorderedEquals([1, 2]));
    });

    test('all returns a snapshot', () {
      cache.setMany({'a': 1, 'b': 2});
      expect(cache.all(), {'a': 1, 'b': 2});
    });

    test('forEach visits entries and supports early exit', () {
      cache.setMany({'a': 1, 'b': 2, 'c': 3});
      final seen = <String>[];
      cache.forEach((key, value) {
        seen.add(key);
        return seen.length < 2;
      });
      expect(seen, hasLength(2));
    });

    test('forEach tolerates mutation from the callback', () {
      cache.setMany({'a': 1, 'b': 2});
      final seen = <String>[];
      cache.forEach((key, value) {
        seen.add(key);
        cache.delete(key);
        return true;
      });
      expect(seen, unorderedEquals(['a', 'b']));
      expect(cache.length, 0);
    });

    test('setMissing requires a missing cache', () {
      expect(() => cache.setMissing('a'), throwsStateError);
      expect(() => cache.setMissingMany(['a']), throwsStateError);
      expect(
        () => cache.setMissingWithTTL('a', const Duration(seconds: 1)),
        throwsStateError,
      );
    });

    test('reports capacity evictions through the callback', () {
      final events = <(EvictionReason, String, int)>[];
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 2,
        onEviction: (reason, key, value) => events.add((reason, key, value)),
      );
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);
      expect(events, [(EvictionReason.capacity, 'a', 1)]);
    });

    test('explicit removals do not fire the callback', () {
      final events = <EvictionReason>[];
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 2,
        onEviction: (reason, key, value) => events.add(reason),
      );
      cache.set('a', 1);
      cache.delete('a');
      cache.set('b', 2);
      cache.purge();
      expect(events, isEmpty);
    });

    test('rejects cache mutations from the eviction callback', () {
      final failures = <Object>[];
      late HotCache<String, int> cache;
      cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 1,
        missingCache: const MissingCacheConfig.shared(),
        onEviction: (reason, key, value) {
          for (final mutation in <void Function()>[
            () => cache.set('x', 1),
            () => cache.setMissing('x'),
            () => cache.delete('x'),
            () => cache.purge(),
            () => cache.purgeExpired(),
          ]) {
            try {
              mutation();
            } catch (error) {
              failures.add(error);
            }
          }
        },
      );
      cache.set('a', 1);
      cache.set('b', 2);
      expect(failures, hasLength(5));
      expect(failures, everyElement(isA<StateError>()));
      expect(cache.length, 1);
      expect(cache.get('b'), 2);
    });

    test('rejects warm-up started from the eviction callback', () async {
      Future<void>? pending;
      late HotCache<String, int> cache;
      cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 1,
        onEviction: (reason, key, value) {
          pending = cache.warmUp(
            () async => const WarmUpData<String, int>(values: {'x': 1}),
          );
        },
      );
      cache.set('a', 1);
      cache.set('b', 2);
      await expectLater(pending, throwsStateError);
    });

    test('allows reads from the eviction callback', () {
      final observed = <Object>[];
      late HotCache<String, int> cache;
      cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 1,
        onEviction: (reason, key, value) {
          observed.add(cache.length);
          observed.add(cache.containsKey(key));
          observed.add(cache.lookup(key));
        },
      );
      cache.set('a', 1);
      cache.set('b', 2);
      expect(observed, [0, false, isA<Absent<int>>()]);
    });

    test('length stays at capacity under pressure', () {
      for (var i = 0; i < 100; i++) {
        cache.set('k$i', i);
      }
      expect(cache.length, 3);
    });

    test('replacing values does not leak counts', () {
      cache.set('a', 1);
      cache.set('a', 2);
      cache.set('a', 3);
      expect(cache.length, 1);
      expect(cache.get('a'), 3);
    });

    test('supports the fifo algorithm', () {
      final fifo = HotCache<String, int>(
        algorithm: EvictionAlgorithm.fifo,
        capacity: 2,
      );
      fifo.set('a', 1);
      fifo.set('b', 2);
      fifo.set('c', 3);
      expect(fifo.algorithm, EvictionAlgorithm.fifo);
      expect(fifo.containsKey('a'), isFalse);
      expect(fifo.containsKey('b'), isTrue);
    });

    test('supports the lfu algorithm', () {
      final lfu = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lfu,
        capacity: 2,
      );
      lfu.set('a', 1);
      lfu.set('b', 2);
      lfu.get('a');
      lfu.set('c', 3);
      expect(lfu.algorithm, EvictionAlgorithm.lfu);
      expect(lfu.containsKey('b'), isFalse);
      expect(lfu.containsKey('a'), isTrue);
    });
  });
}
