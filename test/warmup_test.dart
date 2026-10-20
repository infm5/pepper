import 'dart:async';

import 'package:pepper/pepper.dart';
import 'package:test/test.dart';

void main() {
  group('HotCache warm-up', () {
    test('stores values and negative entries', () async {
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        missingCache: const MissingCacheConfig.shared(),
      );
      await cache.warmUp(
        () async => const WarmUpData<String, int>(
          values: {'a': 1, 'b': 2},
          missing: {'x'},
        ),
      );
      expect(cache.getAll(['a', 'b']), {'a': 1, 'b': 2});
      expect(cache.lookup('x'), isA<Missing<int>>());
      expect(cache.missingLength, 1);
    });

    test(
      'throws when missing keys are given without a missing cache',
      () async {
        final cache = HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 4,
        );
        await expectLater(
          cache.warmUp(
            () async =>
                const WarmUpData<String, int>(values: {'a': 1}, missing: {'x'}),
          ),
          throwsStateError,
        );
        expect(cache.length, 0);
      },
    );

    test('applies a timeout', () async {
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
      );
      await expectLater(
        cache.warmUp(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return const WarmUpData<String, int>(values: {'a': 1});
        }, timeout: const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
      expect(cache.length, 0);
    });

    test('propagates loader errors', () async {
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
      );
      await expectLater(
        cache.warmUp(() async => throw StateError('boom')),
        throwsStateError,
      );
    });

    test('respects capacity', () async {
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 2,
      );
      await cache.warmUp(
        () async =>
            const WarmUpData<String, int>(values: {'a': 1, 'b': 2, 'c': 3}),
      );
      expect(cache.length, 2);
    });

    test('applies copyOnWrite to warmed values', () async {
      final cache = HotCache<String, List<int>>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        copyOnWrite: (value) => List<int>.of(value),
      );
      final source = [1];
      await cache.warmUp(
        () async => WarmUpData<String, List<int>>(values: {'a': source}),
      );
      source.add(2);
      expect(cache.peek('a'), [1]);
    });
  });
}
