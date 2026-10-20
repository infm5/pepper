import 'eviction/eviction_reason.dart';

/// Receives cache activity events.
///
/// Extend this class and override the events of interest; the default
/// implementations do nothing. Events are delivered synchronously on the
/// code path that produced them, so implementations must be cheap and must
/// not call back into the cache. A sink may be shared by several caches.
abstract class CacheMetrics {
  /// Creates a metrics sink.
  const CacheMetrics();

  /// Called when a lookup finds a value.
  void onHit() {}

  /// Called when a lookup finds no value, including negative-cache hits.
  void onMiss() {}

  /// Called when an entry is stored, including loaded and negative entries.
  void onInsert() {}

  /// Called when an entry is evicted automatically.
  void onEviction(EvictionReason reason) {}

  /// Called when the cache is purged.
  void onPurge() {}

  /// Called when a loader batch completes successfully.
  void onLoad() {}

  /// Called when a loader batch fails.
  void onLoadError() {}

  /// Called when the number of value entries changes.
  void onLength(int length) {}

  /// Called when the number of negative entries changes.
  void onMissingLength(int missingLength) {}
}

/// A [CacheMetrics] implementation keeping simple counters.
final class SimpleCacheMetrics extends CacheMetrics {
  final List<int> _evictions = List<int>.filled(
    EvictionReason.values.length,
    0,
  );
  int _hits = 0;
  int _misses = 0;
  int _inserts = 0;
  int _loads = 0;
  int _loadErrors = 0;
  int _purges = 0;
  int _length = 0;
  int _missingLength = 0;

  /// The number of lookups that found a value.
  int get hits => _hits;

  /// The number of lookups that found no value.
  int get misses => _misses;

  /// The number of entries stored.
  int get inserts => _inserts;

  /// The number of loader batches that completed successfully.
  int get loads => _loads;

  /// The number of loader batches that failed.
  int get loadErrors => _loadErrors;

  /// The number of purge calls.
  int get purges => _purges;

  /// The current number of value entries.
  int get length => _length;

  /// The current number of negative entries.
  int get missingLength => _missingLength;

  /// The fraction of lookups that found a value, or 0 before the first
  /// lookup.
  double get hitRate {
    final total = _hits + _misses;
    return total == 0 ? 0 : _hits / total;
  }

  /// The total number of automatic evictions.
  int get totalEvictions {
    var total = 0;
    for (final count in _evictions) {
      total += count;
    }
    return total;
  }

  /// The number of evictions with the given [reason].
  int evictions(EvictionReason reason) => _evictions[reason.index];

  @override
  void onHit() => _hits++;

  @override
  void onMiss() => _misses++;

  @override
  void onInsert() => _inserts++;

  @override
  void onEviction(EvictionReason reason) => _evictions[reason.index]++;

  @override
  void onPurge() => _purges++;

  @override
  void onLoad() => _loads++;

  @override
  void onLoadError() => _loadErrors++;

  @override
  void onLength(int length) => _length = length;

  @override
  void onMissingLength(int missingLength) => _missingLength = missingLength;
}
