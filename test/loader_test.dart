import 'dart:async';

import 'package:pepper/pepper.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('HotCache load-through', () {
    test('loads missing keys and caches the result', () async {
      final loader = RecordingLoader<String, int>((keys) async {
        return {for (final key in keys) key: key.length};
      });
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [loader.call],
      );

      expect(await cache.getOrLoad('abc'), 3);
      expect(cache.get('abc'), 3);
      expect(loader.callCount, 1);
    });

    test('serves cached values without calling the loader', () async {
      final loader = RecordingLoader<String, int>((keys) async => {'a': 1});
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [loader.call],
      );
      cache.set('a', 42);
      expect(await cache.getOrLoad('a'), 42);
      expect(loader.callCount, 0);
    });

    test('deduplicates concurrent loads for the same key', () async {
      final loader = RecordingLoader<String, int>((keys) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return {for (final key in keys) key: 1};
      });
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [loader.call],
      );

      final results = await Future.wait([
        cache.getOrLoad('a'),
        cache.getOrLoad('a'),
        cache.getOrLoad('a'),
      ]);
      expect(results, [1, 1, 1]);
      expect(loader.callCount, 1);
      expect(loader.calls.single, {'a'});
    });

    test('batches keys requested within the same turn', () async {
      final loader = RecordingLoader<String, int>((keys) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return {for (final key in keys) key: key.length};
      });
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [loader.call],
      );

      final results = await Future.wait([
        cache.getOrLoad('a'),
        cache.getOrLoad('bb'),
        cache.getOrLoad('ccc'),
      ]);
      expect(results, [1, 2, 3]);
      expect(loader.callCount, 1);
      expect(loader.calls.single, {'a', 'bb', 'ccc'});
    });

    test('joins an in-flight batch instead of starting another', () async {
      final completer = Completer<Map<String, int>>();
      final loader = RecordingLoader<String, int>((keys) => completer.future);
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [loader.call],
      );

      final first = cache.getOrLoad('a');
      await Future<void>.delayed(Duration.zero);
      final second = cache.getOrLoad('a');
      completer.complete({'a': 7});
      expect(await first, 7);
      expect(await second, 7);
      expect(loader.callCount, 1);
    });

    test(
      'starts a new batch for keys requested while one is in flight',
      () async {
        final completers = <Completer<Map<String, int>>>[];
        final loader = RecordingLoader<String, int>((keys) {
          final completer = Completer<Map<String, int>>();
          completers.add(completer);
          return completer.future;
        });
        final cache = HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 10,
          loaders: [loader.call],
        );

        final first = cache.getOrLoad('a');
        await Future<void>.delayed(Duration.zero);
        final second = cache.getOrLoad('b');
        await Future<void>.delayed(Duration.zero);
        expect(loader.callCount, 2);
        completers[0].complete({'a': 1});
        completers[1].complete({'b': 2});
        expect(await first, 1);
        expect(await second, 2);
      },
    );

    test('shares in-flight work between single and batch loads', () async {
      final completer = Completer<Map<String, int>>();
      final loader = RecordingLoader<String, int>((keys) => completer.future);
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [loader.call],
      );

      final single = cache.getOrLoad('a');
      final many = cache.getOrLoadMany({'a', 'b'});
      await Future<void>.delayed(Duration.zero);
      expect(loader.callCount, 1);
      expect(loader.calls.single, {'a', 'b'});
      completer.complete({'a': 1, 'b': 2});
      expect(await single, 1);
      expect((await many).values, {'a': 1, 'b': 2});
    });

    test('runs loader chains in order with the remaining keys', () async {
      final calls = <(String, Set<String>)>[];
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [
          (keys) async {
            calls.add(('first', Set.of(keys)));
            return {'a': 1};
          },
          (keys) async {
            calls.add(('second', Set.of(keys)));
            return {'b': 2};
          },
        ],
      );

      final result = await cache.getOrLoadMany({'a', 'b'});
      expect(result.values, {'a': 1, 'b': 2});
      expect(calls, hasLength(2));
      expect(calls[0].$1, 'first');
      expect(calls[0].$2, {'a', 'b'});
      expect(calls[1].$1, 'second');
      expect(calls[1].$2, {'b'});
    });

    test('later loaders overwrite values from earlier loaders', () async {
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [
          (keys) async => {'a': 1},
          (keys) async => {'a': 99, 'b': 2},
        ],
      );

      final result = await cache.getOrLoadMany({'a', 'b'});
      expect(result.values, {'a': 99, 'b': 2});
    });

    test('caches extra keys returned by loaders', () async {
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [
          (keys) async => {'a': 1, 'extra': 99},
        ],
      );

      expect(await cache.getOrLoad('a'), 1);
      expect(cache.get('extra'), 99);
    });

    test('aborts the chain on error and surfaces CacheLoadException', () async {
      var secondCalled = false;
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [
          (keys) async => throw StateError('boom'),
          (keys) async {
            secondCalled = true;
            return {};
          },
        ],
      );

      await expectLater(
        cache.getOrLoad('a'),
        throwsA(
          isA<CacheLoadException<String>>()
              .having((e) => e.key, 'key', 'a')
              .having((e) => e.cause, 'cause', isA<StateError>()),
        ),
      );
      expect(secondCalled, isFalse);
    });

    test('a failed batch does not poison later loads', () async {
      var attempt = 0;
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [
          (keys) async {
            attempt++;
            if (attempt == 1) {
              throw StateError('boom');
            }
            return {'a': 1};
          },
        ],
      );

      await expectLater(
        cache.getOrLoad('a'),
        throwsA(isA<CacheLoadException<String>>()),
      );
      expect(await cache.getOrLoad('a'), 1);
    });

    test('reports loader errors without discarding cached hits', () async {
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [(keys) async => throw StateError('boom')],
      );
      cache.set('hit', 1);

      final result = await cache.getOrLoadMany({'hit', 'miss'});
      expect(result.values, {'hit': 1});
      expect(result.failed, {'miss'});
      expect(result.missing, isEmpty);
      expect(result.error, isA<StateError>());
      expect(result.hasError, isTrue);
      expect(result.stackTrace, isNotNull);
    });

    test('negative-caches keys the loaders do not return', () async {
      final loader = RecordingLoader<String, int>((keys) async => {});
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        missingCache: const MissingCacheConfig.shared(),
        loaders: [loader.call],
      );

      expect(await cache.getOrLoad('a'), isNull);
      expect(cache.lookup('a'), isA<Missing<int>>());
      expect(cache.missingLength, 1);
      expect(await cache.getOrLoad('a'), isNull);
      expect(loader.callCount, 1);
    });

    test('does not negative-cache without a missing cache', () async {
      final loader = RecordingLoader<String, int>((keys) async => {});
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [loader.call],
      );

      await cache.getOrLoad('a');
      await cache.getOrLoad('a');
      expect(loader.callCount, 2);
      expect(cache.missingLength, 0);
    });

    test('treats null loader values as not found', () async {
      final cache = HotCache<String, int?>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        missingCache: const MissingCacheConfig.shared(),
        loaders: [
          (keys) async => {'a': null},
        ],
      );

      expect(await cache.getOrLoad('a'), isNull);
      expect(cache.lookup('a'), isA<Missing<int?>>());
    });

    test('returns null without configured loaders', () async {
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
      );
      expect(await cache.getOrLoad('a'), isNull);
    });

    test('getOrLoadMany reports unresolved keys without loaders', () async {
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
      );
      final result = await cache.getOrLoadMany({'a'});
      expect(result.values, isEmpty);
      expect(result.missing, {'a'});
      expect(result.failed, isEmpty);
      expect(result.hasError, isFalse);
    });

    test('getOrLoadMany returns cached hits without loading them', () async {
      final loader = RecordingLoader<String, int>((keys) async {
        return {for (final key in keys) key: 2};
      });
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [loader.call],
      );
      cache.set('a', 1);

      final result = await cache.getOrLoadMany({'a', 'b'});
      expect(result.values, {'a': 1, 'b': 2});
      expect(loader.calls.single, {'b'});
    });

    test('getOrLoadMany batches the remaining keys once', () async {
      final loader = RecordingLoader<String, int>((keys) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return {for (final key in keys) key: key.length};
      });
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [loader.call],
      );

      final result = await cache.getOrLoadMany({'a', 'bb', 'ccc'});
      expect(result.values, {'a': 1, 'bb': 2, 'ccc': 3});
      expect(loader.callCount, 1);
      expect(loader.calls.single, {'a', 'bb', 'ccc'});
    });

    test(
      'getOrLoadMany reports negative-cached keys without loading',
      () async {
        final loader = RecordingLoader<String, int>((keys) async => {});
        final cache = HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 10,
          missingCache: const MissingCacheConfig.shared(),
          loaders: [loader.call],
        );
        cache.setMissing('a');

        final result = await cache.getOrLoadMany({'a', 'b'});
        expect(result.missing, {'a', 'b'});
        expect(loader.calls.single, {'b'});
      },
    );

    test('loaded values are visible through every read path', () async {
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        loaders: [
          (keys) async => {for (final key in keys) key: 5},
        ],
      );
      await cache.getOrLoad('a');
      expect(cache.get('a'), 5);
      expect(cache.peek('a'), 5);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.getAll(['a']), {'a': 5});
    });

    test('a loader failure leaves the key resolvable again', () async {
      var fail = true;
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 10,
        missingCache: const MissingCacheConfig.shared(),
        loaders: [
          (keys) async {
            if (fail) {
              throw StateError('boom');
            }
            return {'a': 1};
          },
        ],
      );

      await expectLater(
        cache.getOrLoad('a'),
        throwsA(isA<CacheLoadException<String>>()),
      );
      fail = false;
      expect(await cache.getOrLoad('a'), 1);
      expect(cache.missingLength, 0);
    });
  });
}
