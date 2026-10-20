import 'package:pepper/pepper.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('SimpleCacheMetrics', () {
    late SimpleCacheMetrics metrics;
    late HotCache<String, int> cache;

    setUp(() {
      metrics = SimpleCacheMetrics();
      cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 2,
        missingCache: const MissingCacheConfig.shared(),
        metrics: metrics,
      );
    });

    test('hit rate is zero before any lookup', () {
      expect(metrics.hitRate, 0);
    });

    test('counts hits and misses', () {
      cache.set('a', 1);
      cache.get('a');
      cache.get('b');
      cache.getAll(['a', 'zzz']);
      expect(metrics.hits, 2);
      expect(metrics.misses, 2);
      expect(metrics.hitRate, 0.5);
    });

    test('counts inserts including negative entries', () {
      cache.set('a', 1);
      cache.setMissing('x');
      cache.setMany({'b': 2});
      expect(metrics.inserts, 3);
    });

    test('counts capacity evictions', () {
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);
      expect(metrics.evictions(EvictionReason.capacity), 1);
      expect(metrics.totalEvictions, 1);
    });

    test('counts manual evictions', () {
      cache.set('a', 1);
      cache.delete('a');
      expect(metrics.evictions(EvictionReason.manual), 1);
    });

    test('counts ttl evictions', () {
      final time = FakeTime();
      final ttlMetrics = SimpleCacheMetrics();
      final ttlCache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 2,
        ttl: const Duration(seconds: 1),
        timeSource: time,
        metrics: ttlMetrics,
      );
      ttlCache.set('a', 1);
      time.advance(const Duration(seconds: 1));
      ttlCache.get('a');
      expect(ttlMetrics.evictions(EvictionReason.ttl), 1);
    });

    test('tracks length and missing length', () {
      cache.set('a', 1);
      cache.setMissing('x');
      expect(metrics.length, 1);
      expect(metrics.missingLength, 1);
      cache.delete('a');
      expect(metrics.length, 0);
    });

    test('tracks length through evictions', () {
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);
      expect(metrics.length, 2);
    });

    test('counts purges', () {
      cache.set('a', 1);
      cache.setMissing('x');
      cache.purge();
      expect(metrics.purges, 1);
      expect(metrics.length, 0);
      expect(metrics.missingLength, 0);
    });

    test('counts loads and load errors', () async {
      var fail = false;
      final loadMetrics = SimpleCacheMetrics();
      final loadCache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 2,
        metrics: loadMetrics,
        loaders: [
          (keys) async {
            if (fail) {
              throw StateError('boom');
            }
            return {for (final key in keys) key: 1};
          },
        ],
      );

      await loadCache.getOrLoad('a');
      expect(loadMetrics.loads, 1);
      fail = true;
      await expectLater(
        loadCache.getOrLoad('b'),
        throwsA(isA<CacheLoadException<String>>()),
      );
      expect(loadMetrics.loadErrors, 1);
    });

    test('counts negative-cache hits as misses', () {
      cache.setMissing('a');
      cache.get('a');
      expect(metrics.misses, 1);
      expect(metrics.hits, 0);
    });

    test('the base sink accepts every event', () async {
      var fail = false;
      final nullMetrics = _NullMetrics();
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 1,
        ttl: const Duration(milliseconds: 1),
        metrics: nullMetrics,
        loaders: [
          (keys) async {
            if (fail) {
              throw StateError('boom');
            }
            return {for (final key in keys) key: 1};
          },
        ],
      );
      cache.set('a', 1);
      cache.get('a');
      cache.set('b', 2);
      await cache.getOrLoad('c');
      fail = true;
      await expectLater(
        cache.getOrLoad('d'),
        throwsA(isA<CacheLoadException<String>>()),
      );
      cache.delete('b');
      cache.purge();
    });
  });

  group('exception and lookup formatting', () {
    test('CacheLoadException describes the failure', () {
      final exception = CacheLoadException<String>('key', StateError('boom'));
      expect(exception.toString(), contains('key'));
      expect(exception.toString(), contains('boom'));
    });

    test('lookup variants have readable representations', () {
      expect(const Present<int>(1).toString(), 'Present(1)');
      expect(const Missing<int>().toString(), 'Missing()');
      expect(const Absent<int>().toString(), 'Absent()');
    });
  });
}

final class _NullMetrics extends CacheMetrics {
  const _NullMetrics();
}
