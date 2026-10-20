/// The eviction algorithm used by a cache.
enum EvictionAlgorithm {
  /// Least recently used.
  lru,

  /// Least frequently used.
  lfu,

  /// First in, first out.
  fifo,
}

/// Configures negative caching of keys that are known to be missing.
final class MissingCacheConfig {
  /// Stores negative entries alongside values, sharing the main cache's
  /// capacity and eviction algorithm.
  const MissingCacheConfig.shared() : algorithm = null, capacity = 0;

  /// Stores negative entries in a dedicated cache with its own [algorithm]
  /// and [capacity].
  const MissingCacheConfig.dedicated({
    required this.algorithm,
    required this.capacity,
  });

  /// The eviction algorithm of the dedicated missing cache, or `null` when
  /// the main cache is shared.
  final EvictionAlgorithm? algorithm;

  /// The capacity of the dedicated missing cache, or 0 when shared.
  final int capacity;

  /// Whether negative entries share the main cache.
  bool get isShared => algorithm == null;
}
