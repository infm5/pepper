/// Load-through support for caches.
///
/// @docImport 'package:pepper/src/cache.dart';
library;

/// Resolves values for the given keys.
///
/// A loader is invoked with the keys that could not be served from the cache.
/// It must return a map holding the values that were found; keys that do not
/// exist must be omitted, and `null` values are treated as not found. Keys
/// outside the requested set may also be returned and are cached too.
///
/// Loader chains run in order, each receiving the keys still missing after
/// the previous loaders. The first error aborts the chain and discards the
/// results of the batch.
typedef Loader<K, V> = Future<Map<K, V>> Function(Set<K> keys);

/// Values and known-missing keys produced by a warm-up function.
final class WarmUpData<K, V> {
  /// Creates warm-up data from [values] and [missing].
  const WarmUpData({this.values = const {}, this.missing = const {}});

  /// The values to store.
  final Map<K, V> values;

  /// The keys known to be missing.
  final Set<K> missing;
}

/// Loads initial cache content.
typedef WarmUpLoader<K, V> = Future<WarmUpData<K, V>> Function();

/// The outcome of [HotCache.getOrLoadMany].
///
/// A batch never throws for loader failures: successful values are kept and
/// the failure is reported through [error] and [failed].
final class LoadResult<K, V> {
  /// Creates a load result.
  const LoadResult({
    required this.values,
    required this.missing,
    required this.failed,
    this.error,
    this.stackTrace,
  });

  /// The values found in the cache or loaded.
  final Map<K, V> values;

  /// The keys that could not be resolved.
  final Set<K> missing;

  /// The keys whose load failed.
  final Set<K> failed;

  /// The first loader error, or `null` when every key resolved.
  final Object? error;

  /// The stack trace of [error], when available.
  final StackTrace? stackTrace;

  /// Whether at least one key failed to load.
  bool get hasError => error != null;
}
