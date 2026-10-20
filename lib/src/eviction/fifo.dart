import 'dart:collection';

import 'in_memory_cache.dart';

final class _FifoNode<K, V> extends LinkedListEntry<_FifoNode<K, V>> {
  _FifoNode(this.key, this.value);

  final K key;
  V value;
}

/// A first-in-first-out eviction cache.
///
/// Entries are evicted in insertion order. [get] and [peek] never reorder
/// anything, and updating an existing entry keeps its original position.
final class FifoCache<K, V> implements InMemoryCache<K, V> {
  /// Creates a cache holding at most [capacity] entries.
  ///
  /// [onEviction] is invoked synchronously for every entry evicted to make
  /// room and may be assigned after construction.
  ///
  /// Throws an [ArgumentError] if [capacity] is less than 1.
  FifoCache({required this.capacity, this.onEviction}) {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'must be at least 1');
    }
  }

  /// Called with the key and value of every entry evicted to make room.
  @override
  void Function(K key, V value)? onEviction;

  @override
  final int capacity;

  final Map<K, _FifoNode<K, V>> _entries = HashMap<K, _FifoNode<K, V>>();
  final LinkedList<_FifoNode<K, V>> _insertionOrder =
      LinkedList<_FifoNode<K, V>>();
  bool _notifying = false;

  @override
  String get algorithm => 'fifo';

  @override
  int get length => _entries.length;

  @override
  bool containsKey(K key) => _entries.containsKey(key);

  @override
  V? peek(K key) => _entries[key]?.value;

  @override
  V? get(K key) => _entries[key]?.value;

  @override
  V? set(K key, V value) {
    _checkNotNotifying();
    final node = _entries[key];
    if (node != null) {
      final previous = node.value;
      node.value = value;
      return previous;
    }
    if (_entries.length >= capacity) {
      _evictOldest();
    }
    final created = _FifoNode<K, V>(key, value);
    _entries[key] = created;
    _insertionOrder.add(created);
    return null;
  }

  @override
  V? delete(K key) {
    _checkNotNotifying();
    final node = _entries.remove(key);
    if (node == null) {
      return null;
    }
    node.unlink();
    return node.value;
  }

  @override
  void purge() {
    _checkNotNotifying();
    _entries.clear();
    _insertionOrder.clear();
  }

  @override
  void forEach(void Function(K key, V value) action) {
    for (final node in _entries.values) {
      action(node.key, node.value);
    }
  }

  void _evictOldest() {
    final victim = _insertionOrder.first;
    victim.unlink();
    _entries.remove(victim.key);
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

  void _checkNotNotifying() {
    if (_notifying) {
      throw StateError(
        'the cache must not be mutated from an eviction callback',
      );
    }
  }
}
