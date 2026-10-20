import 'package:pepper/pepper.dart';
import 'package:test/test.dart';

import 'in_memory_cache_contract.dart';

void main() {
  runInMemoryCacheContract(
    'LruCache',
    (capacity, onEviction) =>
        LruCache<String, int>(capacity: capacity, onEviction: onEviction),
  );

  group('LruCache eviction order', () {
    test('evicts the least recently used entry', () {
      final cache = LruCache<String, int>(capacity: 3);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);
      cache.get('a');
      cache.set('d', 4);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('c'), isTrue);
      expect(cache.containsKey('d'), isTrue);
    });

    test('get refreshes recency', () {
      final cache = LruCache<String, int>(capacity: 2);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.get('a');
      cache.set('c', 3);
      expect(cache.containsKey('b'), isFalse);
    });

    test('peek does not refresh recency', () {
      final cache = LruCache<String, int>(capacity: 2);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.peek('a');
      cache.set('c', 3);
      expect(cache.containsKey('a'), isFalse);
    });

    test('set on an existing key refreshes recency', () {
      final cache = LruCache<String, int>(capacity: 2);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('a', 10);
      cache.set('c', 3);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.get('a'), 10);
    });

    test('tracks recency across many accesses', () {
      final cache = LruCache<String, int>(capacity: 3);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);
      cache.get('a');
      cache.get('b');
      cache.set('d', 4);
      expect(cache.containsKey('c'), isFalse);
      cache.get('a');
      cache.set('e', 5);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('d'), isTrue);
      expect(cache.containsKey('e'), isTrue);
    });
  });
}
