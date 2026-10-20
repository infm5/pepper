import 'package:pepper/pepper.dart';

/// Cache configuration for the demo service.
final class CacheSettings {
  /// Creates cache settings.
  const CacheSettings({
    this.enabled = true,
    this.algorithm = EvictionAlgorithm.lru,
    this.capacity = 10000,
    this.searchCapacity = 2000,
    this.missingCapacity = 5000,
    this.detailTtl = const Duration(minutes: 1),
    this.searchTtl = const Duration(seconds: 30),
    this.jitter = const Duration(seconds: 5),
    this.janitor = true,
  });

  /// Whether the caches are active.
  final bool enabled;

  /// The eviction algorithm used by both caches.
  final EvictionAlgorithm algorithm;

  /// The detail cache capacity, in entries.
  final int capacity;

  /// The search cache capacity, in entries.
  final int searchCapacity;

  /// The dedicated negative-cache capacity, in entries.
  final int missingCapacity;

  /// The default detail TTL.
  final Duration detailTtl;

  /// The search cache TTL.
  final Duration searchTtl;

  /// The additive jitter applied to cache writes.
  final Duration jitter;

  /// Whether the caches run a background janitor.
  final bool janitor;
}

/// Runtime configuration for the server and benchmark harness.
final class AppConfig {
  /// Creates a configuration.
  const AppConfig({
    this.host = '127.0.0.1',
    this.port = 8080,
    this.dbPath = 'data/relics.db',
    this.cache = const CacheSettings(),
    this.dbDelay = Duration.zero,
    this.logRequests = false,
  });

  /// The address to bind.
  final String host;

  /// The TCP port to bind.
  final int port;

  /// The SQLite database path.
  final String dbPath;

  /// The cache settings.
  final CacheSettings cache;

  /// Simulated backend latency, applied before each database operation.
  final Duration dbDelay;

  /// Whether to log every request.
  final bool logRequests;
}
