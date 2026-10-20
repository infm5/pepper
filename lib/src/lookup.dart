/// The outcome of a cache lookup, distinguishing absence from negative
/// caching.
sealed class CacheLookup<V> {
  const CacheLookup();
}

/// A lookup that found a value.
final class Present<V> extends CacheLookup<V> {
  /// Creates a present lookup holding [value].
  const Present(this.value);

  /// The stored value.
  final V value;

  @override
  String toString() => 'Present($value)';
}

/// A lookup that hit a negative-cache entry.
///
/// The key is known to be missing: a loader previously confirmed that it does
/// not exist, and no value is stored for it.
final class Missing<V> extends CacheLookup<V> {
  /// Creates a missing lookup.
  const Missing();

  @override
  String toString() => 'Missing()';
}

/// A lookup that found nothing.
final class Absent<V> extends CacheLookup<V> {
  /// Creates an absent lookup.
  const Absent();

  @override
  String toString() => 'Absent()';
}
