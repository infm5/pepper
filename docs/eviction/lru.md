# LRU — Least Recently Used

**LRU keeps the entries that were used most recently.** When the cache is
full, the entry that has gone the longest without a `get` is evicted.

It is the default choice for workloads where recency is a good proxy for
future usefulness: sessions, recently viewed records, the last N queries.

## Data structures

```text
Map<K, Node>            one hash lookup to find an entry
LinkedList<Node>        recency order:
                          head = most recently used
                          tail = least recently used
Node                    key, value, prev/next pointers
```

Each node is an intrusive `LinkedListEntry`, so moving it to the front is
just pointer surgery — no allocation, no search.

## Operations

| Operation | Bookkeeping |
|---|---|
| `get(key)` | Unlink the node and add it to the head |
| `set(key, value)` on an existing key | Update the value, then move the node to the head |
| `set(key, value)` on a new key | Evict the tail if full, then add the new node at the head |
| `peek(key)` / `containsKey(key)` | No reordering |
| `delete(key)` | Unlink the node and remove it from the map |
| `purge()` | Clear both structures |

The victim is always `_recency.last`.

## Implementation sketch

The sketch shows only the policy-specific parts. Validation, `peek`,
`containsKey`, `delete`, `purge`, `forEach` and the reentrancy guard are
omitted.

```dart
final class LruCache<K, V> implements InMemoryCache<K, V> {
  LruCache({required this.capacity}) {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'must be at least 1');
    }
  }

  @override
  final int capacity;
  final Map<K, _Node<K, V>> _entries = HashMap();
  final LinkedList<_Node<K, V>> _recency = LinkedList();

  @override
  String get algorithm => 'lru';

  @override
  int get length => _entries.length;

  @override
  V? get(K key) {
    final node = _entries[key];
    if (node == null) return null;
    node.unlink();
    _recency.addFirst(node);
    return node.value;
  }

  @override
  V? set(K key, V value) {
    final node = _entries[key];
    if (node != null) {
      final previous = node.value;
      node.value = value;
      node.unlink();
      _recency.addFirst(node);
      return previous;
    }
    if (_entries.length >= capacity) _evictLeastRecent();
    final created = _Node(key, value);
    _entries[key] = created;
    _recency.addFirst(created);
    return null;
  }

  void _evictLeastRecent() {
    final victim = _recency.last;
    victim.unlink();
    _entries.remove(victim.key);
    onEviction?.call(victim.key, victim.value);
  }

  // peek, containsKey, delete, purge and forEach are omitted here.
}
```

The real implementation also has the reentrancy guard that rejects mutations
from `onEviction`, and nullable-value edge cases handled by `containsKey`.

## Complexity

| Operation | Cost |
|---|---|
| `get` | O(1) |
| `set` | O(1) (one eviction, one insertion) |
| `peek`, `containsKey` | O(1) |
| `delete` | O(1) |
| `forEach`, `purge` | O(n) |

## Measured behavior

AOT, per `set+get` pair (Dart 3.12.2, Apple M-series):

| Workload | ns/op |
|---|---:|
| Resident (capacity 100k, 1k keys) | 73.6 |
| Evicting (capacity 1k, 2k keys) | 99.5 |

Deterministic traces:

| Trace | Result |
|---|---:|
| Zipf(1.0), 100k accesses, 10k keys, capacity 1k | 67.29% hits |
| Scan resistance, 1k hot keys after a 20k-key scan | **0.0% retained** |

## Strengths and weaknesses

**Strengths**

- Adapts immediately when the working set changes.
- Excellent when reuse is recency-dominated.
- Simple to reason about: the survivor set is the most recent N touches.

**Weaknesses**

- **Scan pollution.** A single pass over more than `capacity` distinct keys
  flushes the entire hot set. Every scan key looks "recent" at insertion time.
- It cannot tell a one-touch scan from genuinely hot new data until future
  accesses happen — by which point the old data is gone.

This is exactly why the scan benchmark shows 0.0% for LRU: 20,000 insertions
into a 1,000-entry cache guarantee that none of the first 1,000 keys survive.

## When to use LRU

Use LRU when:

- the workload is recency-dominated (sessions, feeds, recent queries),
- the working set changes over time and you want fast adaptation,
- scans are rare, or the cache is large enough to absorb them.

If scans are common but the hot set is stable, use [LFU](/eviction/lfu).
