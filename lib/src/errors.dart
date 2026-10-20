/// Thrown when a loader fails while resolving a key.
final class CacheLoadException<K> implements Exception {
  /// Creates an exception for [key] wrapping the loader's [cause].
  const CacheLoadException(this.key, this.cause, [this.stackTrace]);

  /// The key whose load failed.
  final K key;

  /// The error reported by the loader.
  final Object cause;

  /// The stack trace of [cause], when available.
  final StackTrace? stackTrace;

  @override
  String toString() => 'CacheLoadException: loading "$key" failed: $cause';
}
