/// The reason an entry left the cache.
enum EvictionReason {
  /// The entry was evicted to make room for another entry.
  capacity,

  /// The entry's time-to-live elapsed.
  ttl,

  /// The entry was removed explicitly, through `delete` or `purge`.
  manual,
}

/// Called when an entry is evicted from a cache.
///
/// The callback runs synchronously on the code path that triggered the
/// eviction and receives the stored value as it was at that moment. Capacity
/// and TTL evictions are reported; explicit removals are not.
///
/// Callbacks may read from the cache, but mutating it — storing, removing or
/// purging entries — throws a [StateError], because the cache is mid-eviction
/// while the callback runs. Callbacks should also be fast and should not
/// throw: an exception propagates to the caller of the operation that
/// triggered the eviction, after the victim has already been removed.
typedef EvictionCallback<K, V> =
    void Function(EvictionReason reason, K key, V value);
