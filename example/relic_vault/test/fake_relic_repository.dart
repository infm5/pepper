import 'dart:async';

import 'package:relic_vault/relic_vault.dart';

/// A deterministic in-memory repository for service and HTTP tests.
final class FakeRelicRepository implements RelicRepository {
  FakeRelicRepository({required Map<int, Relic> relics})
    : _relics = Map.of(relics);

  final Map<int, Relic> _relics;

  Duration delay = Duration.zero;
  Completer<void>? gate;

  int findByIdCalls = 0;
  int findByIdsCalls = 0;
  int searchCalls = 0;
  int updateCalls = 0;
  bool closed = false;

  @override
  Future<Relic?> findById(int id) async {
    findByIdCalls++;
    await _wait();
    return _relics[id];
  }

  @override
  Future<List<Relic>> findByIds(Set<int> ids) async {
    findByIdsCalls++;
    await _wait();
    return [
      for (final id in ids)
        if (_relics[id] != null) _relics[id]!,
    ];
  }

  @override
  Future<List<Relic>> search(SearchQuery query) async {
    searchCalls++;
    await _wait();
    final matches =
        _relics.values.where((relic) {
          final text = query.text;
          final matchesText =
              text.isEmpty ||
              relic.name.toLowerCase().contains(text) ||
              relic.description.toLowerCase().contains(text) ||
              relic.material.toLowerCase().contains(text);
          final matchesCulture =
              query.culture == null ||
              relic.culture.toLowerCase() == query.culture;
          final matchesEra =
              query.era == null || relic.era.toLowerCase() == query.era;
          return matchesText && matchesCulture && matchesEra;
        }).toList()..sort((a, b) {
          final rarity = b.rarity.compareTo(a.rarity);
          return rarity == 0 ? a.id.compareTo(b.id) : rarity;
        });
    return matches.take(query.limit).toList();
  }

  @override
  Future<Relic?> update(int id, RelicUpdate update) async {
    updateCalls++;
    await _wait();
    final current = _relics[id];
    if (current == null) {
      return null;
    }
    final next = current.copyWith(
      name: update.name,
      culture: update.culture,
      era: update.era,
      material: update.material,
      rarity: update.rarity,
      description: update.description,
      discoveredYear: update.discoveredYear,
      discoverySite: update.discoverySite,
    );
    _relics[id] = next;
    return next;
  }

  @override
  Future<int> rowCount() async => _relics.length;

  @override
  void close() {
    closed = true;
  }

  Future<void> _wait() async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final gate = this.gate;
    if (gate != null) {
      await gate.future;
    }
  }
}
