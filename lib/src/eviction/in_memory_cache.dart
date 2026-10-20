/// The contract implemented by every eviction algorithm.
///
/// Implementations store opaque values in memory and know nothing about time,
/// expiry or negative caching; those concepts are layered on top by
/// `HotCache`, which composes one of these stores with entry wrappers.
///
/// Implementations are not safe for concurrent use across isolates, which is
/// irrelevant in practice: a Dart isolate executes synchronous code without
/// interleaving.
abstract interface class InMemoryCache<K, V> {
  /// Called with the key and value of every entry evicted to make room.
  ///
  /// Implementations invoke it synchronously after removing the victim and
  /// before storing the new entry.
  void Function(K key, V value)? onEviction;

  /// The name of the eviction algorithm, such as `lru`.
  String get algorithm;

  /// The maximum number of entries the cache holds.
  int get capacity;

  /// The number of entries currently stored.
  int get length;

  /// Whether [key] is stored, without updating access order.
  bool containsKey(K key);

  /// Returns the value stored for [key], updating access order.
  ///
  /// Returns `null` when the key is absent. When [V] is nullable, use
  /// [containsKey] to tell a stored `null` apart from absence.
  V? get(K key);

  /// Returns the value stored for [key] without updating access order.
  ///
  /// Returns `null` when the key is absent. When [V] is nullable, use
  /// [containsKey] to tell a stored `null` apart from absence.
  V? peek(K key);

  /// Stores [value] under [key].
  ///
  /// Returns the value that was previously stored for [key], or `null` when
  /// the key was absent. Evicts the algorithm's victim when the cache is at
  /// capacity.
  V? set(K key, V value);

  /// Removes [key] and returns the value it held, or `null` when absent.
  V? delete(K key);

  /// Removes every entry.
  void purge();

  /// Invokes [action] once for every stored entry.
  ///
  /// The cache must not be modified while iterating.
  void forEach(void Function(K key, V value) action);
}
