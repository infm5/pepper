import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:pepper/pepper.dart';
import 'package:relic_vault/relic_vault.dart';
import 'package:test/test.dart';

import 'fake_relic_repository.dart';

const _settings = CacheSettings(
  capacity: 100,
  searchCapacity: 100,
  missingCapacity: 100,
  detailTtl: Duration(minutes: 1),
  searchTtl: Duration(minutes: 1),
  jitter: Duration.zero,
  janitor: false,
);

final class TestTimeSource implements TimeSource {
  int micros = 0;

  @override
  int nowMicros() => micros;
}

Relic _relic(
  int id, {
  String name = 'Gilded Mask',
  String culture = 'Roman',
  String era = 'Classical',
  String material = 'gold',
  int rarity = 3,
}) {
  return Relic(
    id: id,
    name: name,
    culture: culture,
    era: era,
    material: material,
    rarity: rarity,
    description: 'A $material relic from the $culture $era.',
    discoveredYear: 1900 + id,
    discoverySite: 'Pompeii',
  );
}

RelicService _service(
  FakeRelicRepository repository, {
  CacheSettings settings = _settings,
  TimeSource? timeSource,
}) {
  return RelicService(
    repository: repository,
    settings: settings,
    timeSource: timeSource,
    random: Random(42),
  );
}

void main() {
  group('RelicService', () {
    test('caches detail reads', () async {
      final repository = FakeRelicRepository(relics: {1: _relic(1)});
      final service = _service(repository);

      final first = await service.getRelic(1);
      final second = await service.getRelic(1);

      expect(first, isNotNull);
      expect(second, first);
      expect(repository.findByIdsCalls, 1);
      expect(service.detailMetrics!.hits, 1);
      expect(service.detailMetrics!.misses, 1);
    });

    test('negative-caches missing detail reads', () async {
      final repository = FakeRelicRepository(relics: {1: _relic(1)});
      final service = _service(repository);

      expect(await service.getRelic(9), isNull);
      expect(await service.getRelic(9), isNull);

      expect(repository.findByIdsCalls, 1);
      expect(service.detailMetrics!.missingLength, 1);
    });

    test('caches search results', () async {
      final repository = FakeRelicRepository(relics: {1: _relic(1)});
      final service = _service(repository);
      final query = SearchQuery(text: 'gold');

      final first = await service.search(query);
      final second = await service.search(query);

      expect(second, first);
      expect(repository.searchCalls, 1);
      expect(service.searchMetrics!.hits, 1);
    });

    test(
      'batch reads return values and missing ids in request order',
      () async {
        final repository = FakeRelicRepository(
          relics: {
            1: _relic(1, name: 'One'),
            2: _relic(2, name: 'Two'),
          },
        );
        final service = _service(repository);

        final first = await service.getRelics([2, 9, 1]);
        final second = await service.getRelics([2, 9, 1]);

        expect(first.items, hasLength(2));
        expect(first.missing, [9]);
        expect(second.missing, [9]);
        expect(repository.findByIdsCalls, 1);
        expect(first.toJsonString(), contains('"missing":[9]'));
      },
    );

    test('single-flight collapses concurrent cold reads', () async {
      final repository = FakeRelicRepository(relics: {1: _relic(1)});
      repository.gate = Completer<void>();
      final service = _service(repository);

      final requests = [for (var i = 0; i < 64; i++) service.getRelic(1)];
      await Future<void>.delayed(Duration.zero);
      expect(repository.findByIdsCalls, 1);

      repository.gate!.complete();
      final values = await Future.wait(requests);

      expect(values, everyElement(isNotNull));
      expect(repository.findByIdsCalls, 1);
    });

    test(
      'update replaces the detail entry and clears search results',
      () async {
        final repository = FakeRelicRepository(relics: {1: _relic(1)});
        final service = _service(repository);
        final query = SearchQuery(text: 'mask');

        await service.getRelic(1);
        await service.search(query);
        expect(repository.searchCalls, 1);

        final updated = await service.updateRelic(
          1,
          const RelicUpdate(name: 'Updated Mask', rarity: 5),
        );
        final read = await service.getRelic(1);

        expect(updated, isNotNull);
        expect(jsonDecode(updated!)['name'], 'Updated Mask');
        expect(read, updated);
        expect(service.searchMetrics!.purges, 1);

        await service.search(query);
        expect(repository.searchCalls, 2);
      },
    );

    test('expires entries using the injected clock', () async {
      final time = TestTimeSource();
      final repository = FakeRelicRepository(relics: {1: _relic(1)});
      final service = _service(
        repository,
        settings: const CacheSettings(
          capacity: 10,
          searchCapacity: 10,
          missingCapacity: 10,
          detailTtl: Duration(seconds: 1),
          searchTtl: Duration(seconds: 1),
          jitter: Duration.zero,
          janitor: false,
        ),
        timeSource: time,
      );

      await service.getRelic(1);
      time.micros += const Duration(seconds: 2).inMicroseconds;
      await service.getRelic(1);

      expect(repository.findByIdsCalls, 2);
      expect(service.detailMetrics!.evictions(EvictionReason.ttl), 1);
    });

    test('bypasses caches when disabled', () async {
      final repository = FakeRelicRepository(relics: {1: _relic(1)});
      final service = _service(
        repository,
        settings: const CacheSettings(enabled: false, janitor: false),
      );

      expect(await service.getRelic(1), isNotNull);
      expect(await service.getRelic(1), isNotNull);

      expect(repository.findByIdCalls, 2);
      expect(repository.findByIdsCalls, 0);
      expect(service.cacheEnabled, isFalse);
      expect(service.detailMetrics, isNull);
    });
  });

  group('SearchQuery', () {
    test('normalizes text, filters and limits', () {
      final query = SearchQuery(
        text: '  GOLD  ',
        culture: ' Roman ',
        era: '  ',
        limit: 1000,
      );

      expect(query.text, 'gold');
      expect(query.culture, 'roman');
      expect(query.era, isNull);
      expect(query.limit, 100);
    });

    test('round-trips through its cache key', () {
      final query = SearchQuery(
        text: 'jade',
        culture: 'mayan',
        era: 'classical',
        limit: 12,
      );
      final decoded = SearchQuery.fromCacheKey(query.cacheKey);

      expect(decoded.text, query.text);
      expect(decoded.culture, query.culture);
      expect(decoded.era, query.era);
      expect(decoded.limit, query.limit);
    });
  });
}
