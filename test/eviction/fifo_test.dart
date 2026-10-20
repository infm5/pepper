import 'package:pepper/pepper.dart';
import 'package:test/test.dart';

import 'in_memory_cache_contract.dart';

void main() {
  runInMemoryCacheContract(
    'FifoCache',
    (capacity, onEviction) =>
        FifoCache<String, int>(capacity: capacity, onEviction: onEviction),
  );

  group('FifoCache eviction order', () {
    test('evicts in insertion order', () {
      final cache = FifoCache<String, int>(capacity: 3);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);
      cache.set('d', 4);
      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isTrue);
      expect(cache.containsKey('c'), isTrue);
      expect(cache.containsKey('d'), isTrue);
    });

    test('get and peek do not reorder', () {
      final cache = FifoCache<String, int>(capacity: 2);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.get('a');
      cache.peek('a');
      cache.set('c', 3);
      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isTrue);
    });

    test('updating an existing key keeps its position', () {
      final cache = FifoCache<String, int>(capacity: 2);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('a', 10);
      cache.set('c', 3);
      expect(cache.containsKey('a'), isFalse);
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
    });
  });
}
