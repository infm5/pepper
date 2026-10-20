# FIFO — First In, First Out

**FIFO keeps the most recently inserted entries.** When the cache is full,
the entry that was inserted first is evicted. Reads and updates never change
the order.

It is the simplest and cheapest policy: it does not try to infer which entries
are useful, only which ones arrived first.

## Data structures

```text
Map<K, Node>             key → node
LinkedList<Node>         insertion order:
                           first = oldest insertion (victim)
                           last  = newest insertion
Node                     key, value, prev/next pointers
```

## Operations

| Operation | Bookkeeping |
|---|---|
| `get(key)` | Nothing — the position is unchanged |
| `set(key, value)` on an existing key | Update the value; **keep the original position** |
| `set(key, value)` on a new key | Evict the first node if full, then append at the end |
| `peek` / `containsKey` | Nothing |
| `delete(key)` | Unlink the node |
| `purge()` | Clear both structures |

The victim is always `_insertionOrder.first`.

## Implementation sketch

The sketch shows only the policy-specific parts. Validation, `peek`,
`containsKey`, `delete`, `purge`, `forEach` and the reentrancy guard are
omitted.

```dart
final class FifoCache<K, V> implements InMemoryCache<K, V> {
  final Map<K, _Node<K, V>> _entries = HashMap();
  final LinkedList<_Node<K, V>> _insertionOrder = LinkedList();

  @override
  String get algorithm => 'fifo';

  @override
  V? get(K key) => _entries[key]?.value; // deliberately no reordering

  @override
  V? set(K key, V value) {
    final node = _entries[key];
    if (node != null) {
      final previous = node.value;
      node.value = value;
      return previous; // keeps its original insertion position
    }
    if (_entries.length >= capacity) _evictOldest();
    final created = _Node(key, value);
    _entries[key] = created;
    _insertionOrder.add(created);
    return null;
  }

  void _evictOldest() {
    final victim = _insertionOrder.first;
    victim.unlink();
    _entries.remove(victim.key);
    onEviction?.call(victim.key, victim.value);
  }

  // peek, containsKey, delete, purge and forEach are omitted here.
}
```

The real implementation also includes the reentrancy guard.

## Complexity

| Operation | Cost |
|---|---|
| `get` | O(1) |
| `set` | O(1) |
| `peek`, `containsKey` | O(1) |
| `delete` | O(1) |
| `forEach`, `purge` | O(n) |

Because `get` does no list surgery and updating an existing key keeps its
position, FIFO has the cheapest resident write path of the three policies.

## Measured behavior

AOT, per `set+get` pair (Dart 3.12.2, Apple M-series):

| Workload | ns/op |
|---|---:|
| Resident (capacity 100k, 1k keys) | **9.2** |
| Evicting (capacity 1k, 2k keys) | 63.4 |

Deterministic traces:

| Trace | Result |
|---|---:|
| Zipf(1.0), 100k accesses, 10k keys, capacity 1k | 62.88% hits |
| Scan resistance, 1k hot keys after a 20k-key scan | **0.0% retained** |

The resident number is low because the benchmark repeatedly updates existing
keys: a map lookup and a value assignment, with no linked-list operations.
The evicting number pays for unlinking the victim and allocating a new node.

## Strengths and weaknesses

**Strengths**

- The simplest policy to reason about: survivors are always the newest N
  insertions.
- Cheapest resident path; no touch bookkeeping.
- Predictable eviction order, which can be useful for time-windowed data or
  audit-like retention.

**Weaknesses**

- **No usefulness signal.** A frequently read entry is evicted as soon as it
  becomes the oldest, simply because it was inserted first.
- **No scan resistance.** A 20,000-key scan flushes a 1,000-entry cache, just
  like LRU.
- Updates keep the old position, so re-setting a key does not extend its
  lifetime.

## When to use FIFO

Use FIFO when:

- the data is naturally time-ordered and should expire in insertion order,
- access frequency and recency carry no useful signal,
- you want the cheapest bookkeeping and a fully deterministic victim.

For general-purpose caches, [LRU](/eviction/lru) or [LFU](/eviction/lfu)
usually produce a better hit rate.
