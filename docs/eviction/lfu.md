# LFU — Least Frequently Used

**LFU keeps the entries that are used most often.** When the cache is full,
the entry with the lowest access frequency is evicted. Ties are broken by
age: among entries with the same frequency, the oldest is evicted.

Frequency is history, not recency. One access to a cold key cannot outrank a
hot key that has been read many times — which makes LFU naturally resistant
to scans.

## Data structures

```text
Map<K, Node>                     key → node
Map<int, LinkedList<Node>>       frequency → bucket
int minFrequency                 lowest non-empty bucket

Node                             key, value, frequency
```

Every node lives in exactly one bucket. New entries start at frequency 0.
Reading or updating an entry removes it from its current bucket and adds it
to the front of the next bucket.

Because nodes are added to the **front** of a bucket, the **last** node in a
bucket is the oldest entry at that frequency — that is the tie-break.

## Operations

| Operation | Bookkeeping |
|---|---|
| `get(key)` | Increment frequency; move the node to the next bucket |
| `set(key, value)` on an existing key | Update the value, then increment frequency |
| `set(key, value)` on a new key | Evict the least frequent if full; insert at frequency 0 |
| `peek(key)` / `containsKey(key)` | No frequency change |
| `delete(key)` | Remove the node; if its bucket empties and it was the minimum, recompute the minimum |
| `purge()` | Clear both maps; reset `minFrequency` |

The victim is `_buckets[_minFrequency].last` — the oldest entry in the
lowest-frequency bucket.

## Implementation sketch

The sketch shows only the policy-specific parts. Validation, `peek`,
`containsKey`, `delete`, `purge`, `forEach` and the reentrancy guard are
omitted.

```dart
final class LfuCache<K, V> implements InMemoryCache<K, V> {
  final Map<K, _Node<K, V>> _entries = HashMap();
  final Map<int, LinkedList<_Node<K, V>>> _buckets = HashMap();
  int _minFrequency = 0;

  @override
  V? get(K key) {
    final node = _entries[key];
    if (node == null) return null;
    _increment(node);
    return node.value;
  }

  void _increment(_Node<K, V> node) {
    final frequency = node.frequency;
    final bucket = _buckets[frequency]!;
    node.unlink();
    if (bucket.isEmpty) {
      _buckets.remove(frequency);
      if (frequency == _minFrequency) _minFrequency = frequency + 1;
    }
    final next = frequency + 1;
    node.frequency = next;
    (_buckets[next] ??= LinkedList()).addFirst(node);
  }

  void _evictLeastFrequent() {
    final bucket = _buckets[_minFrequency];
    if (bucket == null) return;
    final victim = bucket.last; // oldest among equal frequency
    victim.unlink();
    _entries.remove(victim.key);
    if (bucket.isEmpty) _buckets.remove(_minFrequency);
    onEviction?.call(victim.key, victim.value);
  }

  // set, delete, purge and forEach are omitted here.
}
```

The real implementation also handles the reentrancy guard, and `delete`
recomputes `_minFrequency` by scanning the bucket keys when the minimum
bucket empties.

## Why the tie-break matters

Without a tie-break, a monotonic scan could evict a newly inserted key
immediately, or an arbitrary key within the bucket. The "oldest among equal
frequency" rule makes eviction deterministic: within a frequency bucket, the
entry that has been there longest is the victim. That is also why the fuzz
reference model tracks a per-key recency sequence alongside the frequency.

## Complexity

| Operation | Cost |
|---|---|
| `get` | O(1) |
| `set` | O(1) |
| `peek`, `containsKey` | O(1) |
| `delete` | O(1) normally; **O(F)** when the minimum bucket empties, where `F` is the number of distinct live frequencies |
| `forEach`, `purge` | O(n) |

`F ≤ length`, so the delete scan is bounded by the number of entries. It only
happens when the entry being deleted is the last one at the minimum frequency.

## Measured behavior

AOT, per `set+get` pair (Dart 3.12.2, Apple M-series):

| Workload | ns/op |
|---|---:|
| Resident (capacity 100k, 1k keys) | 99.3 |
| Evicting (capacity 1k, 2k keys) | 114.0 |

Deterministic traces:

| Trace | Result |
|---|---:|
| Zipf(1.0), 100k accesses, 10k keys, capacity 1k | **72.58% hits** |
| Scan resistance, 1k hot keys after a 20k-key scan | **99.9% retained** |

### Why 99.9% and not 100%?

The hot keys are read four times each, so they have frequency 4. The scan keys
are inserted and never read, so they have frequency 0. Every scan insertion
evicts a frequency-0 scan key — except the **first** one, when the cache is
still full of frequency-4 hot keys and no cold victim exists yet. That single
insertion evicts one hot key. 999 / 1000 = 99.9%.

## Strengths and weaknesses

**Strengths**

- Scan-resistant: one-touch keys cannot displace frequently used keys.
- A stable hot set stays resident even if it is not recently touched.
- The Zipf trace shows the highest hit rate of the three policies.

**Weaknesses**

- **Slow adaptation.** If the working set moves permanently, old popular keys
  keep their high frequency and resist eviction. There is no frequency decay
  in v0.1.0.
- Slightly more bookkeeping than LRU: a bucket move on every touch.
- The minimum-frequency recompute on delete is O(F) in the worst case.

## When to use LFU

Use LFU when:

- the hot set is stable,
- scans, batch jobs or crawlers touch many one-off keys,
- frequency is a better signal than recency (popular products, DNS,
  reference data).

If the workload shifts frequently, LRU adapts faster.
