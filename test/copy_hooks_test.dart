import 'package:pepper/pepper.dart';
import 'package:test/test.dart';

void main() {
  group('copyOnWrite', () {
    test('stores an isolated copy on set', () {
      final cache = HotCache<String, List<int>>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        copyOnWrite: (value) => List<int>.of(value),
      );
      final original = [1];
      cache.set('a', original);
      original.add(2);
      expect(cache.peek('a'), [1]);
    });

    test('applies to setMany', () {
      final cache = HotCache<String, List<int>>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        copyOnWrite: (value) => List<int>.of(value),
      );
      final original = [1];
      cache.setMany({'a': original});
      original.add(2);
      expect(cache.peek('a'), [1]);
    });

    test('applies to loaded values', () async {
      final returned = [1];
      final cache = HotCache<String, List<int>>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        copyOnWrite: (value) => List<int>.of(value),
        loaders: [
          (keys) async => {'a': returned},
        ],
      );
      await cache.getOrLoad('a');
      returned.add(2);
      expect(cache.peek('a'), [1]);
    });
  });

  group('copyOnRead', () {
    test('returns isolated copies from get', () {
      final cache = HotCache<String, List<int>>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        copyOnRead: (value) => List<int>.of(value),
      );
      cache.set('a', [1]);
      cache.get('a')!.add(2);
      expect(cache.get('a'), [1]);
    });

    test('applies to peek, getAll, values, all, lookup and forEach', () {
      final cache = HotCache<String, List<int>>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        copyOnRead: (value) => List<int>.of(value),
      );
      cache.set('a', [1]);

      cache.peek('a')!.add(99);
      expect(cache.peek('a'), [1]);

      cache.getAll(['a'])['a']!.add(99);
      expect(cache.peek('a'), [1]);

      cache.values().single.add(99);
      expect(cache.peek('a'), [1]);

      cache.all()['a']!.add(99);
      expect(cache.peek('a'), [1]);

      final present = cache.lookup('a') as Present<List<int>>;
      present.value.add(99);
      expect(cache.peek('a'), [1]);

      cache.forEach((key, value) {
        value.add(99);
        return true;
      });
      expect(cache.peek('a'), [1]);
    });

    test('applies to loaded values', () async {
      final cache = HotCache<String, List<int>>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        copyOnRead: (value) => List<int>.of(value),
        loaders: [
          (keys) async => {
            for (final key in keys) key: [1],
          },
        ],
      );
      final loaded = await cache.getOrLoad('a');
      loaded!.add(2);
      expect(cache.peek('a'), [1]);
    });

    test('applies to getOrLoadMany values', () async {
      final cache = HotCache<String, List<int>>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        copyOnRead: (value) => List<int>.of(value),
        loaders: [
          (keys) async => {
            for (final key in keys) key: [1],
          },
        ],
      );
      final result = await cache.getOrLoadMany({'a'});
      result.values['a']!.add(2);
      expect(cache.peek('a'), [1]);
    });

    test('applies to getAll hits', () {
      final cache = HotCache<String, List<int>>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        copyOnRead: (value) => List<int>.of(value),
      );
      cache.set('a', [1]);
      cache.getAll(['a'])['a']!.add(2);
      expect(cache.peek('a'), [1]);
    });
  });

  group('copy hooks combined', () {
    test('isolate values in both directions', () {
      final cache = HotCache<String, List<int>>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        copyOnWrite: (value) => List<int>.of(value),
        copyOnRead: (value) => List<int>.of(value),
      );
      final original = [1];
      cache.set('a', original);
      original.add(2);

      final read = cache.get('a')!;
      read.add(3);
      expect(cache.get('a'), [1]);
    });
  });
}
