import 'dart:convert';
import 'dart:math';

import 'package:pepper/pepper.dart';

import '../config.dart';
import '../data/relic_repository.dart';
import '../model/relic.dart';
import '../model/relic_update.dart';
import '../model/search_query.dart';

/// Values and missing ids returned by a batch read.
final class BatchReadResult {
  /// Creates a batch result.
  const BatchReadResult({required this.items, required this.missing});

  /// Encoded JSON objects, in request order.
  final List<String> items;

  /// Requested ids that were not found.
  final List<int> missing;

  /// Builds the API response without decoding the cached objects.
  String toJsonString() {
    final buffer = StringBuffer('{"items":[');
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        buffer.write(',');
      }
      buffer.write(items[i]);
    }
    buffer.write('],"missing":');
    buffer.write(jsonEncode(missing));
    buffer.write('}');
    return buffer.toString();
  }
}

/// The application service that places pepper between Relic and SQLite.
final class RelicService {
  /// Creates the service, optionally enabling the caches.
  RelicService({
    required RelicRepository repository,
    required CacheSettings settings,
    TimeSource? timeSource,
    Random? random,
  }) : _repository = repository,
       _settings = settings {
    if (!settings.enabled) {
      return;
    }

    final jitter = settings.jitter == Duration.zero ? null : settings.jitter;
    _detailMetrics = SimpleCacheMetrics();
    _detailCache = HotCache<int, String>(
      algorithm: settings.algorithm,
      capacity: settings.capacity,
      ttl: settings.detailTtl,
      jitter: jitter,
      janitor: settings.janitor,
      missingCache: MissingCacheConfig.dedicated(
        algorithm: EvictionAlgorithm.lru,
        capacity: max(1, settings.missingCapacity),
      ),
      loaders: [_loadRelics],
      metrics: _detailMetrics,
      timeSource: timeSource,
      random: random,
    );

    _searchMetrics = SimpleCacheMetrics();
    _searchCache = HotCache<String, String>(
      algorithm: settings.algorithm,
      capacity: settings.searchCapacity,
      ttl: settings.searchTtl,
      jitter: jitter,
      janitor: settings.janitor,
      loaders: [_loadSearches],
      metrics: _searchMetrics,
      timeSource: timeSource,
      random: random,
    );
  }

  final RelicRepository _repository;
  final CacheSettings _settings;

  HotCache<int, String>? _detailCache;
  HotCache<String, String>? _searchCache;
  SimpleCacheMetrics? _detailMetrics;
  SimpleCacheMetrics? _searchMetrics;

  /// The active cache settings.
  CacheSettings get settings => _settings;

  /// The detail-cache counters, when caching is enabled.
  SimpleCacheMetrics? get detailMetrics => _detailMetrics;

  /// The search-cache counters, when caching is enabled.
  SimpleCacheMetrics? get searchMetrics => _searchMetrics;

  /// Whether the caches are active.
  bool get cacheEnabled => _detailCache != null;

  /// Returns one encoded relic, or `null` when it does not exist.
  Future<String?> getRelic(int id) async {
    final cache = _detailCache;
    if (cache == null) {
      final relic = await _repository.findById(id);
      return relic == null ? null : jsonEncode(relic.toJson());
    }
    return cache.getOrLoad(id);
  }

  /// Returns encoded relics and the requested ids that were missing.
  Future<BatchReadResult> getRelics(Iterable<int> ids) async {
    final ordered = <int>[];
    final requested = <int>{};
    for (final id in ids) {
      if (requested.add(id)) {
        ordered.add(id);
      }
    }
    if (ordered.isEmpty) {
      return const BatchReadResult(items: [], missing: []);
    }

    final cache = _detailCache;
    if (cache == null) {
      final rows = await _repository.findByIds(requested);
      final byId = {for (final relic in rows) relic.id: relic};
      final items = <String>[];
      final missing = <int>[];
      for (final id in ordered) {
        final relic = byId[id];
        if (relic == null) {
          missing.add(id);
        } else {
          items.add(jsonEncode(relic.toJson()));
        }
      }
      return BatchReadResult(items: items, missing: missing);
    }

    final result = await cache.getOrLoadMany(requested);
    if (result.hasError) {
      throw result.error!;
    }
    final items = <String>[];
    final missing = <int>[];
    for (final id in ordered) {
      final value = result.values[id];
      if (value == null) {
        missing.add(id);
      } else {
        items.add(value);
      }
    }
    return BatchReadResult(items: items, missing: missing);
  }

  /// Returns an encoded JSON array of search results.
  Future<String> search(SearchQuery query) async {
    final cache = _searchCache;
    if (cache == null) {
      final rows = await _repository.search(query);
      return _encodeSummaries(rows);
    }
    return await cache.getOrLoad(query.cacheKey) ?? '[]';
  }

  /// Applies an update and invalidates affected cache entries.
  Future<String?> updateRelic(int id, RelicUpdate update) async {
    if (update.isEmpty) {
      return getRelic(id);
    }

    final relic = await _repository.update(id, update);
    if (relic == null) {
      return null;
    }

    final body = jsonEncode(relic.toJson());
    _detailCache?.set(id, body);
    _searchCache?.purge();
    return body;
  }

  /// Clears the detail and search caches.
  void purgeCaches() {
    _detailCache?.purge();
    _searchCache?.purge();
  }

  /// Cancels the cache janitors.
  void dispose() {
    _detailCache?.dispose();
    _searchCache?.dispose();
  }

  Future<Map<int, String>> _loadRelics(Set<int> ids) async {
    final rows = await _repository.findByIds(ids);
    return {for (final relic in rows) relic.id: jsonEncode(relic.toJson())};
  }

  Future<Map<String, String>> _loadSearches(Set<String> keys) async {
    final result = <String, String>{};
    for (final key in keys) {
      final rows = await _repository.search(SearchQuery.fromCacheKey(key));
      result[key] = _encodeSummaries(rows);
    }
    return result;
  }

  String _encodeSummaries(Iterable<Relic> rows) {
    return jsonEncode([for (final row in rows) row.toSummaryJson()]);
  }
}
