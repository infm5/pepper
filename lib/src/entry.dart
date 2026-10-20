/// An entry stored inside an in-memory eviction cache.
///
/// An entry is either a value ([ValueEntry]) or a negative-cache marker
/// ([MissingEntry]). The [expiryMicros] field carries the expiry deadline so
/// that eviction algorithms never need to understand time.
sealed class CacheEntry<V> {
  const CacheEntry(this.expiryMicros);

  /// The deadline after which the entry is expired, expressed in microseconds
  /// from the origin of the cache's time source.
  ///
  /// Zero means the entry never expires.
  final int expiryMicros;
}

/// A [CacheEntry] holding a value.
final class ValueEntry<V> extends CacheEntry<V> {
  /// Creates a value entry expiring at [expiryMicros].
  const ValueEntry(this.value, super.expiryMicros);

  /// The stored value.
  final V value;
}

/// A [CacheEntry] marking a key as known to be missing (negative caching).
final class MissingEntry<V> extends CacheEntry<V> {
  /// Creates a missing entry expiring at [expiryMicros].
  const MissingEntry(super.expiryMicros);
}
