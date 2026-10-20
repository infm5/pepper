import 'dart:collection';

import 'in_memory_cache.dart';

final class _LfuNode<K, V> extends LinkedListEntry<_LfuNode<K, V>> {
  _LfuNode(this.key, this.value, this.frequency);

  final K key;
  V value;
  int frequency;
}

/// A least-frequently-used eviction cache.
///
/// Every entry carries an access frequency that [get] and [set] increment;
/// [peek] does not. When the cache is at capacity the entry with the lowest
/// frequency is evicted, and among entries with equal frequency the least
/// recently used one loses. Frequency bookkeeping is O(1): entries live in
/// per-frequency buckets, each ordered by recency, and the lowest non-empty
/// bucket is tracked in [_minFrequency].
final class LfuCache<K, V> implements InMemoryCache<K, V> {
  /// Creates a cache holding at most [capacity] entries.
  ///
  /// [onEviction] is invoked synchronously for every entry evicted to make
  /// room and may be assigned after construction.
  ///
  /// Throws an [ArgumentError] if [capacity] is less than 1.
  LfuCache({required this.capacity, this.onEviction}) {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'must be at least 1');
    }
  }

  /// Called with the key and value of every entry evicted to make room.
  @override
  void Function(K key, V value)? onEviction;

  @override
  final int capacity;

  final Map<K, _LfuNode<K, V>> _entries = HashMap<K, _LfuNode<K, V>>();
  final Map<int, LinkedList<_LfuNode<K, V>>> _buckets =
      HashMap<int, LinkedList<_LfuNode<K, V>>>();
  bool _notifying = false;

  int _minFrequency = 0;

  @override
  String get algorithm => 'lfu';

  @override
  int get length => _entries.length;

  @override
  bool containsKey(K key) => _entries.containsKey(key);

  @override
  V? peek(K key) => _entries[key]?.value;

  @override
  V? get(K key) {
    final node = _entries[key];
    if (node == null) {
      return null;
    }
    _incrementFrequency(node);
    return node.value;
  }

  @override
  V? set(K key, V value) {
    _checkNotNotifying();
    final node = _entries[key];
    if (node != null) {
      final previous = node.value;
      node.value = value;
      _incrementFrequency(node);
      return previous;
    }
    if (_entries.length >= capacity) {
      _evictLeastFrequent();
    }
    final created = _LfuNode<K, V>(key, value, 0);
    _entries[key] = created;
    _bucketFor(0).addFirst(created);
    _minFrequency = 0;
    return null;
  }

  @override
  V? delete(K key) {
    _checkNotNotifying();
    final node = _entries.remove(key);
    if (node == null) {
      return null;
    }
    final bucket = _buckets[node.frequency]!;
    node.unlink();
    if (bucket.isEmpty) {
      _buckets.remove(node.frequency);
      if (node.frequency == _minFrequency && _entries.isNotEmpty) {
        _minFrequency = _lowestBucketFrequency();
      }
    }
    return node.value;
  }

  @override
  void purge() {
    _checkNotNotifying();
    _entries.clear();
    _buckets.clear();
    _minFrequency = 0;
  }

  @override
  void forEach(void Function(K key, V value) action) {
    for (final node in _entries.values) {
      action(node.key, node.value);
    }
  }

  void _incrementFrequency(_LfuNode<K, V> node) {
    final frequency = node.frequency;
    final bucket = _buckets[frequency]!;
    node.unlink();
    if (bucket.isEmpty) {
      _buckets.remove(frequency);
      if (frequency == _minFrequency) {
        _minFrequency = frequency + 1;
      }
    }
    final next = frequency + 1;
    node.frequency = next;
    _bucketFor(next).addFirst(node);
  }

  void _evictLeastFrequent() {
    final bucket = _buckets[_minFrequency];
    if (bucket == null) {
      return;
    }
    final victim = bucket.last;
    victim.unlink();
    _entries.remove(victim.key);
    if (bucket.isEmpty) {
      _buckets.remove(_minFrequency);
    }
    final callback = onEviction;
    if (callback != null) {
      _notifying = true;
      try {
        callback(victim.key, victim.value);
      } finally {
        _notifying = false;
      }
    }
  }

  LinkedList<_LfuNode<K, V>> _bucketFor(int frequency) {
    var bucket = _buckets[frequency];
    if (bucket == null) {
      bucket = LinkedList<_LfuNode<K, V>>();
      _buckets[frequency] = bucket;
    }
    return bucket;
  }

  int _lowestBucketFrequency() {
    var lowest = -1;
    for (final frequency in _buckets.keys) {
      if (lowest == -1 || frequency < lowest) {
        lowest = frequency;
      }
    }
    return lowest;
  }

  void _checkNotNotifying() {
    if (_notifying) {
      throw StateError(
        'the cache must not be mutated from an eviction callback',
      );
    }
  }
}
