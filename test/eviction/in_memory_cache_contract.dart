import 'package:pepper/pepper.dart';
import 'package:test/test.dart';

/// Verifies the behaviour every [InMemoryCache] implementation must provide.
///
/// [create] builds a fresh cache with the given [capacity] and optional
/// eviction callback.
void runInMemoryCacheContract(
  String name,
  InMemoryCache<String, int> Function(
    int capacity,
    void Function(String key, int value)? onEviction,
  )
  create,
) {
  group('$name contract', () {
    test('exposes its algorithm, capacity and length', () {
      final cache = create(4, null);
      expect(cache.algorithm, isNotEmpty);
      expect(cache.capacity, 4);
      expect(cache.length, 0);
    });

    test('stores and retrieves values', () {
      final cache = create(4, null);
      expect(cache.set('a', 1), isNull);
      expect(cache.get('a'), 1);
      expect(cache.peek('a'), 1);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.length, 1);
    });

    test('returns the previous value from set', () {
      final cache = create(4, null);
      cache.set('a', 1);
      expect(cache.set('a', 2), 1);
      expect(cache.get('a'), 2);
      expect(cache.length, 1);
    });

    test('delete returns the removed value and forgets the key', () {
      final cache = create(4, null);
      cache.set('a', 1);
      expect(cache.delete('a'), 1);
      expect(cache.get('a'), isNull);
      expect(cache.containsKey('a'), isFalse);
      expect(cache.delete('a'), isNull);
      expect(cache.length, 0);
    });

    test('purge removes every entry', () {
      final cache = create(4, null);
      for (var i = 0; i < 4; i++) {
        cache.set('k$i', i);
      }
      cache.purge();
      expect(cache.length, 0);
      expect(cache.containsKey('k0'), isFalse);
      expect(cache.containsKey('k3'), isFalse);
    });

    test('forEach visits every entry', () {
      final cache = create(4, null);
      cache.set('a', 1);
      cache.set('b', 2);
      final seen = <String, int>{};
      cache.forEach((key, value) {
        seen[key] = value;
      });
      expect(seen, {'a': 1, 'b': 2});
    });

    test('peek does not create entries', () {
      final cache = create(4, null);
      expect(cache.peek('a'), isNull);
      expect(cache.get('a'), isNull);
      expect(cache.length, 0);
    });

    test('rejects capacities below 1', () {
      expect(() => create(0, null), throwsArgumentError);
    });

    for (var capacity = 1; capacity <= 8; capacity++) {
      test('never exceeds capacity $capacity', () {
        final cache = create(capacity, null);
        for (var i = 0; i < capacity * 5; i++) {
          cache.set('k$i', i);
          expect(cache.length, lessThanOrEqualTo(capacity));
        }
        expect(cache.length, capacity);
      });
    }

    test('reports every capacity eviction exactly once', () {
      final evicted = <String, int>{};
      final cache = create(2, (key, value) {
        expect(evicted.containsKey(key), isFalse, reason: 'duplicate $key');
        evicted[key] = value;
      });
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);
      cache.set('d', 4);
      expect(evicted, hasLength(2));
      expect(evicted.values, unorderedEquals([1, 2]));
    });

    test('rejects mutations from the eviction callback', () {
      late InMemoryCache<String, int> cache;
      cache = create(1, (key, value) {
        expect(() => cache.set('reentrant', 1), throwsStateError);
        expect(() => cache.delete(key), throwsStateError);
        expect(() => cache.purge(), throwsStateError);
      });
      cache.set('a', 1);
      cache.set('b', 2);
      expect(cache.length, 1);
      expect(cache.get('b'), 2);
    });

    test('does not report explicit removals', () {
      var evictions = 0;
      final cache = create(2, (key, value) {
        evictions++;
      });
      cache.set('a', 1);
      cache.delete('a');
      cache.set('b', 2);
      cache.purge();
      expect(evictions, 0);
    });

    test('updating an existing key never evicts', () {
      var evictions = 0;
      final cache = create(1, (key, value) {
        evictions++;
      });
      cache.set('a', 1);
      cache.set('a', 2);
      expect(evictions, 0);
      expect(cache.get('a'), 2);
      expect(cache.length, 1);
    });
  });
}
