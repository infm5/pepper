import 'dart:io';

import 'package:pepper/pepper.dart';

import '../config.dart';

/// Process-wide counters exposed by the demo's stats endpoint.
final class AppMetrics {
  final Stopwatch _uptime = Stopwatch()..start();

  int _requests = 0;
  int _dbQueries = 0;
  int _errors = 0;

  /// The number of HTTP requests handled.
  int get requests => _requests;

  /// The number of SQLite operations performed.
  int get dbQueries => _dbQueries;

  /// The number of unhandled request errors.
  int get errors => _errors;

  /// Records one HTTP request.
  void recordRequest() => _requests++;

  /// Records one database operation.
  void recordDbQuery() => _dbQueries++;

  /// Records one unhandled request error.
  void recordError() => _errors++;

  /// Returns the stats payload served by `/api/cache/stats`.
  Map<String, Object?> toJson({
    required CacheSettings settings,
    required SimpleCacheMetrics? detail,
    required SimpleCacheMetrics? search,
  }) {
    return {
      'uptimeSeconds': _uptime.elapsedMicroseconds / 1000000,
      'requests': _requests,
      'dbQueries': _dbQueries,
      'errors': _errors,
      'rssBytes': ProcessInfo.currentRss,
      'maxRssBytes': ProcessInfo.maxRss,
      'cache': {
        'enabled': settings.enabled,
        'algorithm': settings.algorithm.name,
        'capacity': settings.capacity,
        'searchCapacity': settings.searchCapacity,
        'missingCapacity': settings.missingCapacity,
        'detailTtlMs': settings.detailTtl.inMilliseconds,
        'searchTtlMs': settings.searchTtl.inMilliseconds,
        'detail': _cacheJson(detail),
        'search': _cacheJson(search),
      },
    };
  }

  Map<String, Object?>? _cacheJson(SimpleCacheMetrics? metrics) {
    if (metrics == null) {
      return null;
    }
    return {
      'hits': metrics.hits,
      'misses': metrics.misses,
      'hitRate': metrics.hitRate,
      'inserts': metrics.inserts,
      'loads': metrics.loads,
      'loadErrors': metrics.loadErrors,
      'evictions': {
        for (final reason in EvictionReason.values)
          reason.name: metrics.evictions(reason),
      },
      'length': metrics.length,
      'missingLength': metrics.missingLength,
    };
  }
}
