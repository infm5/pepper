# Eviction Techniques

A cache has two independent limits: **capacity** (how many entries it can
hold) and **time** (how long an entry stays fresh). This section is about the
first one — what happens when the cache is full.

`pepper` ships three policies behind one contract:

| Policy | Keeps | Victim |
|---|---|---|
| [LRU](/eviction/lru) | What was used most **recently** | The least recently used entry |
| [LFU](/eviction/lfu) | What was used most **often** | The least frequently used entry (oldest among ties) |
| [FIFO](/eviction/fifo) | What was inserted most **recently** | The oldest inserted entry |

## The contract

Every algorithm implements `InMemoryCache<K, V>`:

```dart
abstract interface class InMemoryCache<K, V> {
  void Function(K key, V value)? onEviction;

  String get algorithm;
  int get capacity;
  int get length;

  bool containsKey(K key);
  V? get(K key);      // updates recency / frequency
  V? peek(K key);     // does not update anything
  V? set(K key, V value); // returns the previous value, or null
  V? delete(K key);   // returns the removed value, or null
  void purge();
  void forEach(void Function(K key, V value) action);
}
```

The low-level caches store **opaque values**. Time, TTL, negative caching,
loaders and counters are layered on top by `HotCache`. You can use
`LruCache`, `LfuCache` or `FifoCache` directly when you only need the
eviction policy.

## The eviction flow

All three algorithms follow the same sequence:

```text
set(key, value)
  → key already present?
      → update in place; never evict
  → length >= capacity?
      → remove one victim chosen by the policy
      → invoke onEviction(key, value)
  → insert the new entry
  → return the previous value or null
```

Eviction happens **before** insertion, so `length` never exceeds `capacity`,
even transiently. `onEviction` runs after the victim is removed and before
the replacement is inserted. It may read the cache but must not mutate it —
doing so throws a `StateError`, because the cache is mid-eviction.

## Same operations, different survivors

Capacity 2, then:

```dart
set('a', 1);
set('b', 2);
get('a'); get('a'); get('a');
get('b');
set('c', 3); // eviction
```

| Policy | Survivors | Why |
|---|---|---|
| **LRU** | `{b, c}` | `a` was the least recently touched |
| **LFU** | `{a, c}` | `b` has frequency 1; `a` has frequency 3 |
| **FIFO** | `{b, c}` | `a` was inserted first |

Same cache, same calls, three different victims. That is the entire point of
choosing a policy.

## Workload quality

Two deterministic traces from `bench/bench.dart`:

### Zipf(1.0)

100,000 accesses over 10,000 keys, capacity 1,000:

| Policy | Hit rate |
|---|---:|
| LRU | 67.29% |
| **LFU** | **72.58%** |
| FIFO | 62.88% |

A skewed workload rewards frequency awareness: LFU keeps the popular keys
even when they are not the most recent.

### Scan resistance

1,000 hot keys, each read four times, then a scan of 20,000 new keys, capacity
1,000:

| Policy | Hot keys retained |
|---|---:|
| LRU | **0.0%** |
| **LFU** | **99.9%** |
| FIFO | **0.0%** |

Why LRU and FIFO lose everything: the scan inserts 20,000 new keys into a
1,000-entry cache. Every scan key is newer (LRU) or inserted later (FIFO) than
the hot keys, so the hot set is flushed after the first 1,000 insertions.

Why LFU keeps almost everything: hot keys have frequency 4, scan keys have
frequency 0. Eviction picks a frequency-0 scan key, so the scan keys evict
each other. The missing 0.1% is exactly one key: on the very first scan
insertion the cache is full of frequency-4 hot keys and there is no cold
victim yet, so one hot key has to go.

::: tip This is an adversarial benchmark
It isolates scan pollution, so the gap is dramatic. The Zipf trace above is
the more realistic everyday difference: 5.3 points of hit rate, not 100 vs 0.
:::

## Choosing a policy

| If your workload… | Choose | Why |
|---|---|---|
| Has recency-dominated reuse (sessions, recent queries) | **LRU** | Adapts immediately to a changing working set |
| Has a stable hot set, or scans/batch jobs | **LFU** | Frequency history resists one-touch floods |
| Values are immutable and access order is irrelevant | **FIFO** | Cheapest resident path; predictable eviction order |
| Is unknown | **LRU** | The safest general default; measure and switch if hit rate is poor |

There is no universally best policy. LRU is vulnerable to scans; LFU is slow
to adapt when the hot set moves (old popular keys keep their frequency until
they are evicted).

## TTL and capacity are independent

TTL does not participate in victim selection. An entry can leave because:

- the cache is full and the policy selects it (`EvictionReason.capacity`), or
- its deadline passed (`EvictionReason.ttl`), whichever happens first.

A cache with no TTL still has a hard memory bound: capacity. A cache with a
TTL still needs capacity: TTL bounds staleness, not memory.

## Implementing a new algorithm

Adding a policy is deliberately mechanical:

1. **Implement `InMemoryCache<K, V>`.** Keep an index
   `Map<K, Node>` for O(1) lookup and an ordering structure for O(1) victim
   selection. The existing algorithms pair a `HashMap` with an intrusive
   `LinkedList` of `LinkedListEntry` nodes.
2. **Define what a "touch" means.** `get` updates the policy; `peek` and
   `containsKey` must not. Updating an existing key with `set` must never
   evict.
3. **Evict before inserting** when `length >= capacity`. Return the previous
   value from `set` and the removed value from `delete`.
4. **Fire `onEviction` after removing the victim** and before inserting the
   replacement. Respect the reentrancy guard: mutating from the callback must
   throw.
5. **Run the shared contract suite**
   (`test/eviction/in_memory_cache_contract.dart`). It covers capacities 1–8,
   previous-value returns, callbacks firing exactly once, explicit removals
   not firing, reentrancy, and invalid capacities.
6. **Add an order test and a reference-model fuzz test.** The fuzzer compares
   the cache against an independent model built from plain collections after
   every operation, so off-by-one eviction and counter drift are caught.
7. **Wire the enum value** and the factory in
   `HotCache._createCache`, then update the decision guide.
