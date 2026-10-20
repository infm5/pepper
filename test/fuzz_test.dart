import 'dart:math';

import 'package:pepper/pepper.dart';
import 'package:test/test.dart';

/// Randomized tests comparing every eviction algorithm with a reference
/// model built from plain Dart collections.
void main() {
  Set<int> keysOf(InMemoryCache<int, int> cache) {
    final keys = <int>{};
    cache.forEach((key, value) {
      keys.add(key);
    });
    return keys;
  }

  group('fuzz', () {
    test('LruCache matches a reference recency model', () {
      final random = Random(7);
      for (var round = 0; round < 10; round++) {
        final capacity = 1 + random.nextInt(8);
        final cache = LruCache<int, int>(capacity: capacity);
        final reference = <int, int>{};
        for (var op = 0; op < 400; op++) {
          final key = random.nextInt(24);
          switch (random.nextInt(4)) {
            case 0:
              final value = random.nextInt(1000);
              final previous = reference.remove(key);
              reference[key] = value;
              expect(cache.set(key, value), previous);
              if (reference.length > capacity) {
                reference.remove(reference.keys.first);
              }
            case 1:
              final expected = reference.remove(key);
              if (expected != null) {
                reference[key] = expected;
              }
              expect(cache.get(key), expected);
            case 2:
              expect(cache.peek(key), reference[key]);
            case 3:
              expect(cache.delete(key), reference.remove(key));
          }
          expect(cache.length, reference.length, reason: 'op $op');
        }
        expect(keysOf(cache), unorderedEquals(reference.keys));
      }
    });

    test('FifoCache matches a reference insertion-order model', () {
      final random = Random(17);
      for (var round = 0; round < 10; round++) {
        final capacity = 1 + random.nextInt(8);
        final cache = FifoCache<int, int>(capacity: capacity);
        final reference = <int, int>{};
        for (var op = 0; op < 400; op++) {
          final key = random.nextInt(24);
          switch (random.nextInt(4)) {
            case 0:
              final value = random.nextInt(1000);
              final previous = reference[key];
              if (previous == null && reference.length >= capacity) {
                reference.remove(reference.keys.first);
              }
              reference[key] = value;
              expect(cache.set(key, value), previous);
            case 1:
              expect(cache.get(key), reference[key]);
            case 2:
              expect(cache.peek(key), reference[key]);
            case 3:
              expect(cache.delete(key), reference.remove(key));
          }
          expect(cache.length, reference.length, reason: 'op $op');
        }
        expect(keysOf(cache), unorderedEquals(reference.keys));
      }
    });

    test('LfuCache matches a reference frequency model', () {
      final random = Random(23);
      for (var round = 0; round < 10; round++) {
        final capacity = 1 + random.nextInt(8);
        final cache = LfuCache<int, int>(capacity: capacity);
        final values = <int, int>{};
        final frequencies = <int, int>{};
        final recency = <int, int>{};
        var sequence = 0;

        int? victim() {
          int? result;
          for (final key in frequencies.keys) {
            if (result == null ||
                frequencies[key]! < frequencies[result]! ||
                (frequencies[key] == frequencies[result] &&
                    recency[key]! < recency[result]!)) {
              result = key;
            }
          }
          return result;
        }

        for (var op = 0; op < 400; op++) {
          final key = random.nextInt(24);
          switch (random.nextInt(4)) {
            case 0:
              final value = random.nextInt(1000);
              if (frequencies.containsKey(key)) {
                expect(cache.set(key, value), values[key]);
                values[key] = value;
                frequencies[key] = frequencies[key]! + 1;
                recency[key] = sequence++;
              } else {
                if (frequencies.length >= capacity) {
                  final evicted = victim()!;
                  values.remove(evicted);
                  frequencies.remove(evicted);
                  recency.remove(evicted);
                }
                expect(cache.set(key, value), isNull);
                values[key] = value;
                frequencies[key] = 0;
                recency[key] = sequence++;
              }
            case 1:
              if (frequencies.containsKey(key)) {
                expect(cache.get(key), values[key]);
                frequencies[key] = frequencies[key]! + 1;
                recency[key] = sequence++;
              } else {
                expect(cache.get(key), isNull);
              }
            case 2:
              expect(cache.peek(key), values[key]);
            case 3:
              expect(cache.delete(key), values.remove(key));
              frequencies.remove(key);
              recency.remove(key);
          }
          expect(cache.length, frequencies.length, reason: 'op $op');
        }
        expect(keysOf(cache), unorderedEquals(frequencies.keys));
      }
    });

    test('HotCache counters stay exact without eviction pressure', () {
      final random = Random(11);
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 1000,
        missingCache: const MissingCacheConfig.shared(),
      );
      final live = <String>{};
      final missing = <String>{};
      for (var i = 0; i < 2000; i++) {
        final key = 'k${random.nextInt(50)}';
        switch (random.nextInt(6)) {
          case 0:
          case 1:
            cache.set(key, i);
            live.add(key);
            missing.remove(key);
          case 2:
            cache.setMissing(key);
            missing.add(key);
            live.remove(key);
          case 3:
            cache.delete(key);
            live.remove(key);
            missing.remove(key);
          case 4:
            cache.get(key);
          case 5:
            cache.purge();
            live.clear();
            missing.clear();
        }
        expect(cache.length, live.length, reason: 'op $i');
        expect(cache.missingLength, missing.length, reason: 'op $i');
      }
      expect(cache.keys().toSet(), live);
    });

    test('HotCache matches a reference LRU model under eviction pressure', () {
      final random = Random(13);
      const capacity = 8;
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: capacity,
      );
      final reference = <String, int>{};
      for (var i = 0; i < 1500; i++) {
        final key = 'k${random.nextInt(30)}';
        switch (random.nextInt(3)) {
          case 0:
            cache.set(key, i);
            reference.remove(key);
            reference[key] = i;
            if (reference.length > capacity) {
              reference.remove(reference.keys.first);
            }
          case 1:
            final expected = reference.remove(key);
            if (expected != null) {
              reference[key] = expected;
            }
            expect(cache.get(key), expected);
          case 2:
            expect(cache.delete(key), reference.remove(key) != null);
        }
        expect(cache.length, reference.length, reason: 'op $i');
      }
      expect(cache.keys().toSet(), reference.keys.toSet());
    });
  });
}
