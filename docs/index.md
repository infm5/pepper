---
layout: home

hero:
  name: pepper
  text: High-performance in-memory caching for Dart servers
  tagline: LRU · LFU · FIFO · TTL + jitter · single-flight loaders · negative caching · zero runtime dependencies
  image:
    src: /logo.svg
    alt: pepper
  actions:
    - theme: brand
      text: Get started
      link: /get-started

features:
  - icon: ⚡
    title: Fast by construction
    details: One hash lookup per operation, O(1) eviction, and no locks on the hot path.
    link: /get-started#how-it-works
  - icon: 🧩
    title: Three eviction policies
    details: LRU, LFU and FIFO behind one contract, with measured hit rates and scan resistance.
    link: /eviction/
  - icon: ⏱️
    title: TTL that behaves
    details: Monotonic deadlines, bounded jitter on every write path, and an optional janitor.
    link: /get-started#ttl
  - icon: 🔁
    title: Single-flight loaders
    details: Concurrent misses share one load; same-turn keys are batched into one loader call.
    link: /get-started#load-through
  - icon: 🚫
    title: Negative caching
    details: Remember missing keys in the shared cache or in a dedicated cache with its own capacity.
    link: /get-started#negative-caching
  - icon: 📊
    title: Metrics included
    details: CacheMetrics events plus SimpleCacheMetrics hit, miss, insert, eviction, load and length counters.
    link: /get-started#metrics-and-callbacks
  - icon: 🧬
    title: Copy hooks & warm-up
    details: copyOnRead/copyOnWrite isolate mutable values; warmUp preloads values and known-missing keys.
    link: /get-started#copy-hooks
  - icon: 📦
    title: Batch operations & iteration
    details: setMany, getAll, deleteMany, purge, keys, values, all and forEach, with snapshot-safe iteration.
    link: /get-started#core-operations
---
