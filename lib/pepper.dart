/// A feature-complete, high-performance in-memory cache for Dart servers.
///
/// `pepper` pairs eviction algorithms with time-to-live expiry, load-through
/// with in-flight deduplication, negative caching and metrics, all with zero
/// runtime dependencies.
///
/// ```dart
/// import 'package:pepper/pepper.dart';
///
/// final cache = HotCache<String, String>(
///   algorithm: EvictionAlgorithm.lru,
///   capacity: 1_000,
///   ttl: const Duration(minutes: 5),
/// );
///
/// cache.set('greeting', 'hello');
/// print(cache.get('greeting'));
/// ```
library;

export 'src/cache.dart';
export 'src/config.dart';
export 'src/errors.dart';
export 'src/eviction/eviction_reason.dart';
export 'src/eviction/fifo.dart';
export 'src/eviction/in_memory_cache.dart';
export 'src/eviction/lfu.dart';
export 'src/eviction/lru.dart';
export 'src/loader.dart';
export 'src/lookup.dart';
export 'src/metrics.dart';
export 'src/time_source.dart';
