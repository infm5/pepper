import 'package:pepper/pepper.dart';
import 'package:test/test.dart';

import 'in_memory_cache_contract.dart';

void main() {
  runInMemoryCacheContract(
    'LfuCache',
    (capacity, onEviction) =>
        LfuCache<String, int>(capacity: capacity, onEviction: onEviction),
  );

  group('LfuCache eviction order', () {
    test('evicts the least frequently used entry', () {
      final cache = LfuCache<String, int>(capacity: 3);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);
      cache.get('a');
      cache.set('d', 4);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.containsKey('c'), isTrue);
      expect(cache.containsKey('a'), isTrue);
    });

    test('breaks frequency ties by recency', () {
      final cache = LfuCache<String, int>(capacity: 3);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);
      cache.get('b');
      cache.set('d', 4);
      expect(cache.containsKey('a'), isFalse);
      cache.set('e', 5);
      expect(cache.containsKey('c'), isFalse);
      expect(cache.containsKey('b'), isTrue);
      expect(cache.containsKey('d'), isTrue);
    });

    test('peek does not increment frequency', () {
      final cache = LfuCache<String, int>(capacity: 2);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.peek('a');
      cache.set('c', 3);
      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isTrue);
    });

    test('set on an existing key increments frequency', () {
      final cache = LfuCache<String, int>(capacity: 2);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('a', 10);
      cache.set('c', 3);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.get('a'), 10);
    });

    test('frequency dominates recency', () {
      final cache = LfuCache<String, int>(capacity: 2);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.get('a');
      cache.get('a');
      cache.get('a');
      cache.set('c', 3);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.containsKey('a'), isTrue);
    });

    test('tracks the minimum frequency when the lowest bucket empties', () {
      final cache = LfuCache<String, int>(capacity: 2);
      cache.set('a', 1);
      cache.get('a');
      cache.set('b', 2);
      cache.set('c', 3);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.containsKey('a'), isTrue);
    });

    test('keeps evicting correctly after deletes', () {
      final cache = LfuCache<String, int>(capacity: 3);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);
      cache.get('a');
      cache.get('a');
      cache.delete('b');
      cache.set('d', 4);
      cache.set('e', 5);
      expect(cache.containsKey('c'), isFalse);
      expect(cache.containsKey('d'), isTrue);
      expect(cache.containsKey('a'), isTrue);
    });

    test('recomputes the minimum after deleting the only low entry', () {
      final cache = LfuCache<String, int>(capacity: 3);
      cache.set('a', 1);
      cache.get('a');
      cache.set('b', 2);
      cache.get('b');
      cache.get('b');
      cache.set('c', 3);
      cache.get('c');
      cache.get('c');
      cache.get('c');
      cache.delete('a');
      cache.set('d', 4);
      expect(cache.containsKey('d'), isTrue);
      expect(cache.length, 3);
    });
  });
}
