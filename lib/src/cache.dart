import 'dart:async';
import 'dart:math';

import 'config.dart';
import 'entry.dart';
import 'errors.dart';
import 'eviction/eviction_reason.dart';
import 'eviction/fifo.dart';
import 'eviction/in_memory_cache.dart';
import 'eviction/lfu.dart';
import 'eviction/lru.dart';
import 'internal/load_batcher.dart';
import 'loader.dart';
import 'lookup.dart';
import 'metrics.dart';
import 'time_source.dart';

/// A high-performance in-memory cache.
///
/// A cache combines an eviction algorithm, optional time-to-live expiry,
/// optional load-through functions and optional negative caching. Synchronous
/// operations never interleave with each other inside an isolate; only
/// [getOrLoad], [getOrLoadMany] and [warmUp] are asynchronous.
///
/// ```dart
/// final cache = HotCache<String, User>(
///   algorithm: EvictionAlgorithm.lru,
///   capacity: 10_000,
///   ttl: const Duration(minutes: 5),
/// );
///
/// cache.set('user:1', user);
/// final User? cached = cache.get('user:1');
/// ```
///
/// Entries expire through [ttl], are evicted when capacity is reached, or are
/// removed explicitly. Capacity and TTL evictions are reported through
/// `onEviction`; explicit removals through [delete] and [purge] are not.
///
/// When loaders are configured, [getOrLoad] and [getOrLoadMany] resolve
/// misses through them, deduplicate concurrent loads and negative-cache the
/// keys the loaders do not return.
final class HotCache<K, V> {
  /// Creates a cache.
  ///
  /// [algorithm] and [capacity] select the eviction policy and its maximum
  /// number of value entries. [ttl] gives every entry a default lifetime;
  /// [jitter] adds a uniform random delay in `[0, jitter)` to every stored
  /// expiry, spreading expirations out. [janitor] starts a periodic
  /// [purgeExpired] timer at [janitorInterval], or at the TTL by default.
  ///
  /// [missingCache] enables negative caching. [loaders] configure the loader
  /// chain used by [getOrLoad] and [getOrLoadMany]. [onEviction] observes
  /// automatic evictions. [copyOnWrite] and [copyOnRead] isolate stored
  /// values from their callers. [metrics] receives activity events.
  ///
  /// [timeSource] and [random] are hooks for tests and custom environments.
  ///
  /// Throws an [ArgumentError] when [capacity] is less than 1, when a
  /// duration is not positive, or when [janitor] is requested without a TTL
  /// or an explicit [janitorInterval].
  HotCache({
    required EvictionAlgorithm algorithm,
    required int capacity,
    Duration? ttl,
    Duration? jitter,
    bool janitor = false,
    Duration? janitorInterval,
    MissingCacheConfig? missingCache,
    List<Loader<K, V>> loaders = const [],
    EvictionCallback<K, V>? onEviction,
    V Function(V value)? copyOnWrite,
    V Function(V value)? copyOnRead,
    CacheMetrics? metrics,
    TimeSource? timeSource,
    Random? random,
  }) : _algorithm = algorithm,
       _capacity = capacity,
       _ttlMicros = _durationMicros(ttl, 'ttl'),
       _jitterMicros = _durationMicros(jitter, 'jitter'),
       _missingEnabled = missingCache != null,
       _loaders = loaders,
       _onEviction = onEviction,
       _copyOnWrite = copyOnWrite,
       _copyOnRead = copyOnRead,
       _metrics = metrics,
       _time = timeSource ?? MonotonicTimeSource.shared,
       _random = random ?? Random(),
       _cache = _createCache<K, CacheEntry<V>>(algorithm, capacity),
       _missingCache = _createMissingCache<K, CacheEntry<V>>(missingCache) {
    if (janitor && ttl == null && janitorInterval == null) {
      throw ArgumentError(
        'janitor requires a ttl or an explicit janitorInterval',
      );
    }
    if (janitorInterval != null && janitorInterval <= Duration.zero) {
      throw ArgumentError.value(
        janitorInterval,
        'janitorInterval',
        'must be positive',
      );
    }
    _cache.onEviction = _handleCapacityEviction;
    _missingCache?.onEviction = _handleCapacityEviction;
    _batcher = loaders.isEmpty ? null : LoadBatcher<K, V>(_loadBatch);
    if (janitor) {
      _janitorTimer = Timer.periodic(
        janitorInterval ?? ttl!,
        (_) => purgeExpired(),
      );
    }
  }

  final EvictionAlgorithm _algorithm;
  final int _capacity;
  final int _ttlMicros;
  final int _jitterMicros;
  final bool _missingEnabled;
  final List<Loader<K, V>> _loaders;
  final EvictionCallback<K, V>? _onEviction;
  final V Function(V value)? _copyOnWrite;
  final V Function(V value)? _copyOnRead;
  final CacheMetrics? _metrics;
  final TimeSource _time;
  final Random _random;
  final InMemoryCache<K, CacheEntry<V>> _cache;
  final InMemoryCache<K, CacheEntry<V>>? _missingCache;
  late final LoadBatcher<K, V>? _batcher;

  Timer? _janitorTimer;
  int _liveCount = 0;
  int _missingCount = 0;
  bool _notifyingEviction = false;

  /// The configured eviction algorithm.
  EvictionAlgorithm get algorithm => _algorithm;

  /// The maximum number of value entries the cache holds.
  int get capacity => _capacity;

  /// The number of value entries currently stored.
  ///
  /// Entries whose TTL has elapsed are included until they are cleaned up.
  int get length => _liveCount;

  /// The number of negative-cache entries currently stored.
  int get missingLength => _missingCount;

  /// Stores [value] under [key].
  ///
  /// The value passes through `copyOnWrite` when configured. Storing a value
  /// clears any negative entry for the key.
  void set(K key, V value) {
    _storeLive(key, ValueEntry<V>(_write(value), _expiryFor(_ttlMicros)));
    _metrics?.onInsert();
  }

  /// Stores [value] under [key] with a per-entry time-to-live.
  ///
  /// [ttl] overrides the cache-wide TTL for this entry and must be positive.
  void setWithTTL(K key, V value, Duration ttl) {
    final ttlMicros = _positiveMicros(ttl, 'ttl');
    _storeLive(key, ValueEntry<V>(_write(value), _expiryFor(ttlMicros)));
    _metrics?.onInsert();
  }

  /// Stores every entry of [items].
  ///
  /// Entries are processed in iteration order; each insertion may evict to
  /// respect capacity.
  void setMany(Map<K, V> items) {
    items.forEach((key, value) {
      set(key, value);
    });
  }

  /// Marks [key] as known to be missing.
  ///
  /// A negative entry makes [getOrLoad] return `null` without calling the
  /// loaders, until the entry expires or a value is stored. Requires an
  /// enabled missing cache and throws a [StateError] otherwise.
  void setMissing(K key) {
    _requireMissingCache();
    _storeMissing(key, MissingEntry<V>(_expiryFor(_ttlMicros)));
    _metrics?.onInsert();
  }

  /// Marks [key] as known to be missing with a per-entry time-to-live.
  ///
  /// [ttl] overrides the cache-wide TTL for this entry and must be positive.
  void setMissingWithTTL(K key, Duration ttl) {
    _requireMissingCache();
    final ttlMicros = _positiveMicros(ttl, 'ttl');
    _storeMissing(key, MissingEntry<V>(_expiryFor(ttlMicros)));
    _metrics?.onInsert();
  }

  /// Marks every key of [keys] as known to be missing.
  void setMissingMany(Iterable<K> keys) {
    _requireMissingCache();
    for (final key in keys) {
      _storeMissing(key, MissingEntry<V>(_expiryFor(_ttlMicros)));
      _metrics?.onInsert();
    }
  }

  /// Returns the value stored for [key], or `null` when the key is absent,
  /// negative-cached or expired.
  ///
  /// Accessing an expired entry removes it and reports a TTL eviction. The
  /// returned value passes through `copyOnRead` when configured. Use [lookup]
  /// to tell absence and negative caching apart.
  V? get(K key) {
    final entry = _usableEntry(key);
    if (entry is ValueEntry<V>) {
      _metrics?.onHit();
      return _read(entry.value);
    }
    _metrics?.onMiss();
    return null;
  }

  /// Returns the values found for [keys].
  ///
  /// Keys that are absent, negative-cached or expired are omitted.
  Map<K, V> getAll(Iterable<K> keys) {
    final result = <K, V>{};
    for (final key in keys) {
      final entry = _usableEntry(key);
      if (entry is ValueEntry<V>) {
        _metrics?.onHit();
        result[key] = _read(entry.value);
      } else {
        _metrics?.onMiss();
      }
    }
    return result;
  }

  /// Returns the value stored for [key] without updating access order.
  ///
  /// Unlike [get], expiry is not checked: an expired entry is still returned.
  /// Returns `null` for absent and negative-cached keys.
  V? peek(K key) {
    final entry = _cache.peek(key);
    return entry is ValueEntry<V> ? _read(entry.value) : null;
  }

  /// Whether a live value is stored for [key].
  ///
  /// Expired and negative-cached entries report `false`.
  bool containsKey(K key) {
    final entry = _cache.peek(key) ?? _missingCache?.peek(key);
    return entry is ValueEntry<V> && !_isExpired(entry);
  }

  /// Looks up [key], distinguishing a value, a negative entry and absence.
  ///
  /// Expired entries report [Absent] and are not removed by this call.
  CacheLookup<V> lookup(K key) {
    final entry = _cache.peek(key) ?? _missingCache?.peek(key);
    if (entry == null || _isExpired(entry)) {
      return Absent<V>();
    }
    return switch (entry) {
      ValueEntry<V>(:final value) => Present<V>(_read(value)),
      MissingEntry<V>() => Missing<V>(),
    };
  }

  /// The keys holding a live value, excluding negative and expired entries.
  List<K> keys() {
    final now = _time.nowMicros();
    final result = <K>[];
    _cache.forEach((key, entry) {
      if (entry is ValueEntry<V> && !_expiredAt(entry, now)) {
        result.add(key);
      }
    });
    return result;
  }

  /// The values currently stored, excluding negative and expired entries.
  List<V> values() {
    final now = _time.nowMicros();
    final result = <V>[];
    _cache.forEach((key, entry) {
      if (entry is ValueEntry<V> && !_expiredAt(entry, now)) {
        result.add(_read(entry.value));
      }
    });
    return result;
  }

  /// A snapshot of every live entry.
  Map<K, V> all() {
    final now = _time.nowMicros();
    final result = <K, V>{};
    _cache.forEach((key, entry) {
      if (entry is ValueEntry<V> && !_expiredAt(entry, now)) {
        result[key] = _read(entry.value);
      }
    });
    return result;
  }

  /// Invokes [action] for every live entry until it returns `false`.
  ///
  /// The cache is snapshotted before iterating, so [action] may modify it.
  void forEach(bool Function(K key, V value) action) {
    final now = _time.nowMicros();
    final snapshot = <K, V>{};
    _cache.forEach((key, entry) {
      if (entry is ValueEntry<V> && !_expiredAt(entry, now)) {
        snapshot[key] = _read(entry.value);
      }
    });
    for (final entry in snapshot.entries) {
      if (!action(entry.key, entry.value)) {
        break;
      }
    }
  }

  /// Removes [key] and reports whether it was present.
  ///
  /// Explicit removals do not invoke the eviction callback.
  bool delete(K key) {
    _checkNotNotifying();
    var deleted = false;
    final removed = _cache.delete(key);
    if (removed != null) {
      _decrementFor(removed);
      _metrics?.onEviction(EvictionReason.manual);
      deleted = true;
    }
    final missingCache = _missingCache;
    if (missingCache != null) {
      final removedMissing = missingCache.delete(key);
      if (removedMissing != null) {
        _decrementFor(removedMissing);
        _metrics?.onEviction(EvictionReason.manual);
        deleted = true;
      }
    }
    return deleted;
  }

  /// Removes every key of [keys] and returns how many were present.
  int deleteMany(Iterable<K> keys) {
    var deleted = 0;
    for (final key in keys) {
      if (delete(key)) {
        deleted++;
      }
    }
    return deleted;
  }

  /// Removes every entry, including negative entries.
  void purge() {
    _checkNotNotifying();
    _cache.purge();
    _missingCache?.purge();
    _liveCount = 0;
    _missingCount = 0;
    final metrics = _metrics;
    if (metrics != null) {
      metrics.onPurge();
      metrics.onLength(0);
      metrics.onMissingLength(0);
    }
  }

  /// Removes every expired entry and returns how many were removed.
  ///
  /// Expiry is also applied lazily by [get] and [getOrLoad]; the janitor
  /// calls this method periodically when enabled.
  int purgeExpired() {
    final now = _time.nowMicros();
    var removed = _purgeExpiredFrom(_cache, now);
    final missingCache = _missingCache;
    if (missingCache != null) {
      removed += _purgeExpiredFrom(missingCache, now);
    }
    return removed;
  }

  /// Returns the value for [key], loading it when the cache misses.
  ///
  /// A cache hit returns immediately. A negative-cache hit returns `null`
  /// without calling the loaders. Otherwise the key joins the current load
  /// batch, which is deduplicated against concurrent calls and resolved by
  /// the loader chain; loaded values and unresolved keys are cached before
  /// the value is returned. A value stored for [key] while its load was in
  /// flight is overwritten when the load completes.
  ///
  /// Throws a [CacheLoadException] when a loader fails. Returns `null` for
  /// misses when no loaders are configured.
  Future<V?> getOrLoad(K key) async {
    final entry = _usableEntry(key);
    if (entry is ValueEntry<V>) {
      _metrics?.onHit();
      return _read(entry.value);
    }
    _metrics?.onMiss();
    if (entry is MissingEntry<V>) {
      return null;
    }
    final batcher = _batcher;
    if (batcher == null) {
      return null;
    }
    final LoadOutcome<V> outcome;
    try {
      outcome = await batcher.load(key);
    } catch (error, stackTrace) {
      throw CacheLoadException<K>(key, error, stackTrace);
    }
    if (!outcome.isFound) {
      return null;
    }
    return _read(outcome.value as V);
  }

  /// Returns values for [keys], loading the missing ones as one batch.
  ///
  /// Values already cached are returned immediately; the remaining keys are
  /// coalesced with concurrent loads and passed to the loader chain together.
  /// The result reports values, negative-cache hits and unresolved keys, and
  /// never throws for loader failures: successful values are kept and the
  /// failure is reported through [LoadResult.error].
  Future<LoadResult<K, V>> getOrLoadMany(Set<K> keys) async {
    final values = <K, V>{};
    final missing = <K>{};
    final failed = <K>{};
    Object? error;
    StackTrace? stackTrace;

    final toLoad = <K>[];
    for (final key in keys) {
      final entry = _usableEntry(key);
      if (entry is ValueEntry<V>) {
        _metrics?.onHit();
        values[key] = _read(entry.value);
      } else if (entry is MissingEntry<V>) {
        _metrics?.onMiss();
        missing.add(key);
      } else {
        _metrics?.onMiss();
        toLoad.add(key);
      }
    }

    final batcher = _batcher;
    if (batcher == null || toLoad.isEmpty) {
      missing.addAll(toLoad);
      return LoadResult(values: values, missing: missing, failed: failed);
    }

    final outcomes = <K, Future<LoadOutcome<V>>>{};
    for (final key in toLoad) {
      outcomes[key] = batcher.load(key);
    }
    for (final entry in outcomes.entries) {
      try {
        final outcome = await entry.value;
        if (outcome.isFound) {
          values[entry.key] = _read(outcome.value as V);
        } else {
          missing.add(entry.key);
        }
      } catch (err, stack) {
        failed.add(entry.key);
        error ??= err;
        stackTrace ??= stack;
      }
    }
    return LoadResult(
      values: values,
      missing: missing,
      failed: failed,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Populates the cache with values and known-missing keys from [loader].
  ///
  /// The loader runs asynchronously and its result is applied atomically;
  /// when [timeout] is provided the wait is bounded and a
  /// [TimeoutException] propagates on expiry. Missing keys require an
  /// enabled missing cache; otherwise a [StateError] is thrown and nothing
  /// is stored.
  Future<void> warmUp(WarmUpLoader<K, V> loader, {Duration? timeout}) async {
    _checkNotNotifying();
    final future = loader();
    final data = timeout == null ? await future : await future.timeout(timeout);
    if (data.missing.isNotEmpty) {
      _requireMissingCache();
    }
    data.values.forEach((key, value) {
      _storeLive(key, ValueEntry<V>(_write(value), _expiryFor(_ttlMicros)));
      _metrics?.onInsert();
    });
    if (data.missing.isNotEmpty) {
      for (final key in data.missing) {
        _storeMissing(key, MissingEntry<V>(_expiryFor(_ttlMicros)));
        _metrics?.onInsert();
      }
    }
  }

  /// Stops the background janitor started with `janitor: true`.
  ///
  /// Disposing is idempotent and does not invalidate the cache: entries can
  /// still be read, written and purged afterwards.
  void dispose() {
    _janitorTimer?.cancel();
    _janitorTimer = null;
  }

  CacheEntry<V>? _usableEntry(K key) {
    final entry = _cache.get(key);
    if (entry != null) {
      if (_isExpired(entry)) {
        _removeExpired(key, entry);
        return null;
      }
      return entry;
    }
    final missingCache = _missingCache;
    if (missingCache != null) {
      final missing = missingCache.get(key);
      if (missing != null) {
        if (_isExpired(missing)) {
          _removeExpired(key, missing);
          return null;
        }
        return missing;
      }
    }
    return null;
  }

  void _storeLive(K key, CacheEntry<V> entry) {
    _checkNotNotifying();
    final missingCache = _missingCache;
    if (missingCache != null) {
      final removed = missingCache.delete(key);
      if (removed != null) {
        _decrementFor(removed);
      }
    }
    final previous = _cache.set(key, entry);
    if (previous != null) {
      _decrementFor(previous);
    }
    _incrementFor(entry);
  }

  void _storeMissing(K key, CacheEntry<V> entry) {
    _checkNotNotifying();
    final missingCache = _missingCache;
    if (missingCache != null) {
      final removed = _cache.delete(key);
      if (removed != null) {
        _decrementFor(removed);
      }
      final previous = missingCache.set(key, entry);
      if (previous != null) {
        _decrementFor(previous);
      }
    } else {
      final previous = _cache.set(key, entry);
      if (previous != null) {
        _decrementFor(previous);
      }
    }
    _incrementFor(entry);
  }

  void _removeExpired(K key, CacheEntry<V> entry) {
    if (_cache.delete(key) == null) {
      _missingCache?.delete(key);
    }
    _decrementFor(entry);
    _metrics?.onEviction(EvictionReason.ttl);
    _notifyEviction(EvictionReason.ttl, key, entry);
  }

  int _purgeExpiredFrom(InMemoryCache<K, CacheEntry<V>> cache, int nowMicros) {
    _checkNotNotifying();
    final expired = <K>[];
    cache.forEach((key, entry) {
      if (_expiredAt(entry, nowMicros)) {
        expired.add(key);
      }
    });
    var removed = 0;
    for (final key in expired) {
      final entry = cache.delete(key);
      if (entry == null) {
        continue;
      }
      removed++;
      _decrementFor(entry);
      _metrics?.onEviction(EvictionReason.ttl);
      _notifyEviction(EvictionReason.ttl, key, entry);
    }
    return removed;
  }

  void _handleCapacityEviction(K key, CacheEntry<V> entry) {
    _decrementFor(entry);
    _metrics?.onEviction(EvictionReason.capacity);
    _notifyEviction(EvictionReason.capacity, key, entry);
  }

  void _notifyEviction(EvictionReason reason, K key, CacheEntry<V> entry) {
    if (entry is! ValueEntry<V>) {
      return;
    }
    final callback = _onEviction;
    if (callback == null) {
      return;
    }
    _notifyingEviction = true;
    try {
      callback(reason, key, entry.value);
    } finally {
      _notifyingEviction = false;
    }
  }

  void _checkNotNotifying() {
    if (_notifyingEviction) {
      throw StateError(
        'the cache must not be mutated from an eviction callback',
      );
    }
  }

  Future<Map<K, V>> _loadBatch(Set<K> keys) async {
    try {
      final found = await _runLoaders(keys);
      _writeBack(keys, found);
      _metrics?.onLoad();
      return found;
    } catch (_) {
      _metrics?.onLoadError();
      rethrow;
    }
  }

  Future<Map<K, V>> _runLoaders(Set<K> keys) async {
    final results = <K, V>{};
    final pending = Set<K>.of(keys);
    for (final loader in _loaders) {
      if (pending.isEmpty) {
        break;
      }
      final found = await loader(Set<K>.of(pending));
      if (found.isEmpty) {
        continue;
      }
      found.forEach((key, value) {
        if (value != null) {
          results[key] = value;
        }
      });
      pending.removeAll(found.keys);
    }
    return results;
  }

  void _writeBack(Set<K> keys, Map<K, V> found) {
    found.forEach((key, value) {
      _storeLive(key, ValueEntry<V>(_write(value), _expiryFor(_ttlMicros)));
      _metrics?.onInsert();
    });
    if (_missingEnabled) {
      for (final key in keys) {
        if (!found.containsKey(key)) {
          _storeMissing(key, MissingEntry<V>(_expiryFor(_ttlMicros)));
          _metrics?.onInsert();
        }
      }
    }
  }

  void _incrementFor(CacheEntry<V> entry) {
    if (entry is ValueEntry<V>) {
      _liveCount++;
      _metrics?.onLength(_liveCount);
    } else {
      _missingCount++;
      _metrics?.onMissingLength(_missingCount);
    }
  }

  void _decrementFor(CacheEntry<V> entry) {
    if (entry is ValueEntry<V>) {
      _liveCount--;
      _metrics?.onLength(_liveCount);
    } else {
      _missingCount--;
      _metrics?.onMissingLength(_missingCount);
    }
  }

  bool _isExpired(CacheEntry<V> entry) {
    final expiry = entry.expiryMicros;
    return expiry != 0 && _time.nowMicros() >= expiry;
  }

  bool _expiredAt(CacheEntry<V> entry, int nowMicros) {
    final expiry = entry.expiryMicros;
    return expiry != 0 && nowMicros >= expiry;
  }

  int _expiryFor(int ttlMicros) {
    if (ttlMicros <= 0) {
      return 0;
    }
    final jitterMicros = _jitterMicros;
    final jitter = jitterMicros > 0
        ? (_random.nextDouble() * jitterMicros).floor()
        : 0;
    return _time.nowMicros() + ttlMicros + jitter;
  }

  V _read(V value) => _copyOnRead == null ? value : _copyOnRead(value);

  V _write(V value) => _copyOnWrite == null ? value : _copyOnWrite(value);

  void _requireMissingCache() {
    if (!_missingEnabled) {
      throw StateError(
        'missing cache is not enabled; pass a MissingCacheConfig',
      );
    }
  }
}

int _durationMicros(Duration? duration, String name) =>
    duration == null ? 0 : _positiveMicros(duration, name);

int _positiveMicros(Duration duration, String name) {
  if (duration <= Duration.zero) {
    throw ArgumentError.value(duration, name, 'must be positive');
  }
  return duration.inMicroseconds;
}

InMemoryCache<K, V> _createCache<K, V>(
  EvictionAlgorithm algorithm,
  int capacity,
) {
  return switch (algorithm) {
    EvictionAlgorithm.lru => LruCache<K, V>(capacity: capacity),
    EvictionAlgorithm.lfu => LfuCache<K, V>(capacity: capacity),
    EvictionAlgorithm.fifo => FifoCache<K, V>(capacity: capacity),
  };
}

InMemoryCache<K, V>? _createMissingCache<K, V>(MissingCacheConfig? config) {
  if (config == null || config.isShared) {
    return null;
  }
  return _createCache<K, V>(config.algorithm!, config.capacity);
}
