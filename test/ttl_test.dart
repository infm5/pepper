import 'package:fake_async/fake_async.dart';
import 'package:pepper/pepper.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('HotCache TTL', () {
    late FakeTime time;
    late HotCache<String, int> cache;

    setUp(() {
      time = FakeTime();
      cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        ttl: const Duration(minutes: 1),
        timeSource: time,
      );
    });

    test('entries expire once the ttl elapses', () {
      cache.set('a', 1);
      time.advance(const Duration(seconds: 59));
      expect(cache.get('a'), 1);
      time.advance(const Duration(seconds: 1));
      expect(cache.get('a'), isNull);
    });

    test('expired entries are removed on access with a ttl eviction', () {
      final events = <(EvictionReason, String, int)>[];
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        ttl: const Duration(minutes: 1),
        timeSource: time,
        onEviction: (reason, key, value) => events.add((reason, key, value)),
      );
      cache.set('a', 1);
      time.advance(const Duration(minutes: 1));
      expect(cache.get('a'), isNull);
      expect(events, [(EvictionReason.ttl, 'a', 1)]);
      expect(cache.length, 0);
    });

    test('containsKey respects expiry while peek ignores it', () {
      cache.set('a', 1);
      time.advance(const Duration(minutes: 1));
      expect(cache.containsKey('a'), isFalse);
      expect(cache.peek('a'), 1);
      expect(cache.lookup('a'), isA<Absent<int>>());
    });

    test('keys, values, all and forEach hide expired entries', () {
      cache.set('a', 1);
      time.advance(const Duration(minutes: 1));
      expect(cache.keys(), isEmpty);
      expect(cache.values(), isEmpty);
      expect(cache.all(), isEmpty);
      var visited = 0;
      cache.forEach((key, value) {
        visited++;
        return true;
      });
      expect(visited, 0);
    });

    test('getAll hides expired entries', () {
      cache.set('a', 1);
      time.advance(const Duration(minutes: 1));
      expect(cache.getAll(['a']), isEmpty);
    });

    test('entries without a ttl never expire', () {
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 2,
        timeSource: time,
      );
      cache.set('a', 1);
      time.advance(const Duration(days: 365));
      expect(cache.get('a'), 1);
    });

    test('setWithTTL overrides the cache-wide ttl', () {
      cache.setWithTTL('a', 1, const Duration(seconds: 10));
      time.advance(const Duration(seconds: 10));
      expect(cache.get('a'), isNull);
    });

    test('setWithTTL rejects non-positive durations', () {
      expect(
        () => cache.setWithTTL('a', 1, Duration.zero),
        throwsArgumentError,
      );
    });

    test('purgeExpired removes expired entries and reports the count', () {
      cache.set('a', 1);
      cache.set('b', 2);
      time.advance(const Duration(minutes: 1));
      cache.set('c', 3);
      expect(cache.purgeExpired(), 2);
      expect(cache.length, 1);
      expect(cache.get('c'), 3);
    });

    test('purgeExpired reports ttl evictions', () {
      final events = <(EvictionReason, String, int)>[];
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        ttl: const Duration(minutes: 1),
        timeSource: time,
        onEviction: (reason, key, value) => events.add((reason, key, value)),
      );
      cache.set('a', 1);
      time.advance(const Duration(minutes: 1));
      cache.purgeExpired();
      expect(events, [(EvictionReason.ttl, 'a', 1)]);
    });
  });

  group('HotCache jitter', () {
    HotCache<String, int> build(
      FakeTime time, {
      List<Loader<String, int>> loaders = const [],
    }) {
      return HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 16,
        ttl: const Duration(microseconds: 1000),
        jitter: const Duration(microseconds: 100),
        timeSource: time,
        random: FixedRandom(doubleValue: 0.5),
        loaders: loaders,
      );
    }

    test('adds a bounded delay to set', () {
      final time = FakeTime();
      final cache = build(time);
      cache.set('a', 1);
      time.advance(const Duration(microseconds: 1049));
      expect(cache.get('a'), 1);
      time.advance(const Duration(microseconds: 1));
      expect(cache.get('a'), isNull);
    });

    test('applies on top of a per-entry ttl', () {
      final time = FakeTime();
      final cache = build(time);
      cache.setWithTTL('a', 1, const Duration(microseconds: 500));
      time.advance(const Duration(microseconds: 549));
      expect(cache.get('a'), 1);
      time.advance(const Duration(microseconds: 1));
      expect(cache.get('a'), isNull);
    });

    test('applies to every entry of setMany', () {
      final time = FakeTime();
      final cache = build(time);
      cache.setMany({'a': 1, 'b': 2});
      time.advance(const Duration(microseconds: 1049));
      expect(cache.get('a'), 1);
      time.advance(const Duration(microseconds: 1));
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), isNull);
    });

    test('applies to loaded values', () async {
      final time = FakeTime();
      final cache = build(
        time,
        loaders: [
          (keys) async => {for (final key in keys) key: 1},
        ],
      );
      expect(await cache.getOrLoad('a'), 1);
      time.advance(const Duration(microseconds: 1049));
      expect(cache.get('a'), 1);
      time.advance(const Duration(microseconds: 1));
      expect(cache.get('a'), isNull);
    });

    test('applies to warm-up values', () async {
      final time = FakeTime();
      final cache = build(time);
      await cache.warmUp(
        () async => const WarmUpData<String, int>(values: {'a': 1}),
      );
      time.advance(const Duration(microseconds: 1049));
      expect(cache.get('a'), 1);
      time.advance(const Duration(microseconds: 1));
      expect(cache.get('a'), isNull);
    });

    test('supports jitter windows beyond the 32-bit microsecond range', () {
      final time = FakeTime();
      final cache = HotCache<String, int>(
        algorithm: EvictionAlgorithm.lru,
        capacity: 4,
        ttl: const Duration(hours: 1),
        jitter: const Duration(days: 30),
        timeSource: time,
        random: FixedRandom(doubleValue: 0.9),
      );
      cache.set('a', 1);
      time.advance(const Duration(hours: 1));
      expect(cache.get('a'), 1);
    });
  });

  group('HotCache janitor', () {
    test('purges expired entries periodically', () {
      fakeAsync((async) {
        final time = FakeTime();
        final cache = HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 4,
          ttl: const Duration(minutes: 1),
          janitor: true,
          timeSource: time,
        );
        cache.set('a', 1);
        time.advance(const Duration(minutes: 1));
        async.elapse(const Duration(minutes: 1));
        expect(cache.length, 0);
        cache.dispose();
      });
    });

    test('does not purge live entries', () {
      fakeAsync((async) {
        final time = FakeTime();
        final cache = HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 4,
          ttl: const Duration(minutes: 1),
          janitor: true,
          timeSource: time,
        );
        cache.set('a', 1);
        async.elapse(const Duration(minutes: 1));
        expect(cache.length, 1);
        cache.dispose();
      });
    });

    test('supports a custom janitor interval', () {
      fakeAsync((async) {
        final time = FakeTime();
        final cache = HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 4,
          janitor: true,
          janitorInterval: const Duration(seconds: 30),
          timeSource: time,
        );
        cache.setWithTTL('a', 1, const Duration(seconds: 10));
        time.advance(const Duration(seconds: 10));
        async.elapse(const Duration(seconds: 30));
        expect(cache.length, 0);
        cache.dispose();
      });
    });

    test('dispose cancels the timer and is idempotent', () {
      fakeAsync((async) {
        final cache = HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 4,
          ttl: const Duration(minutes: 1),
          janitor: true,
          timeSource: FakeTime(),
        );
        expect(async.pendingTimers, hasLength(1));
        cache.dispose();
        cache.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('the cache stays usable after dispose', () {
      fakeAsync((async) {
        final cache = HotCache<String, int>(
          algorithm: EvictionAlgorithm.lru,
          capacity: 4,
          ttl: const Duration(minutes: 1),
          janitor: true,
          timeSource: FakeTime(),
        );
        cache.dispose();
        cache.set('a', 1);
        expect(cache.get('a'), 1);
      });
    });
  });
}
