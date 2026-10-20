# Relic Vault

An end-to-end example for [`pepper`](../../README.md): a read-heavy relic
catalog served by [Relic](https://pub.dev/packages/relic), backed by SQLite,
and protected by the package's in-memory cache.

This directory is a separate Dart application. It is not part of the published
`pepper` package and does not add runtime dependencies to it.

## What it demonstrates

- `HotCache` in front of a real HTTP service
- LRU and LFU eviction over a hot/long-tail workload
- TTL, jitter and the background janitor
- Load-through with `getOrLoad` and `getOrLoadMany`
- Single-flight deduplication for cold keys
- Dedicated negative caching for 404s
- Separate search-result caching
- Write invalidation: detail entries are replaced and search results purged
- `SimpleCacheMetrics` exposed through `/api/cache/stats`
- A real end-to-end benchmark with `oha`

## Quick start

```sh
cd example/relic_vault
dart pub get
dart run bin/seed.dart --db=data/relics.db --count=50000
dart run bin/server.dart --db=data/relics.db
```

Open <http://127.0.0.1:8080>.

The server can also seed an empty database itself:

```sh
dart run bin/server.dart --db=data/relics.db --seed
```

## API

```text
GET  /                              demo UI
GET  /health                        health check
GET  /api/relics/:id                cached detail
GET  /api/relics?ids=1,2,3          cached batch load
GET  /api/relics?q=gold&limit=20    cached search
PUT  /api/relics/:id                update + invalidation
GET  /api/cache/stats               counters and process stats
POST /api/cache/purge               clear both caches
```

Examples:

```sh
curl http://127.0.0.1:8080/api/relics/1
curl 'http://127.0.0.1:8080/api/relics?q=gold&limit=5'
curl 'http://127.0.0.1:8080/api/relics?ids=1,2,3'
curl -X PUT -H 'content-type: application/json' \
  -d '{"rarity":5,"name":"The Sun Disk"}' \
  http://127.0.0.1:8080/api/relics/1
curl http://127.0.0.1:8080/api/cache/stats
```

## Cache design

The service keeps two caches:

| Cache | Key | Value | TTL | Purpose |
|---|---|---|---|---|
| Detail | `int` relic id | encoded JSON object | 60 s | detail and batch reads |
| Search | normalized query key | encoded JSON array | 30 s | search results |

Both use the configured algorithm (LRU by default), jitter and a janitor. The
detail cache has a dedicated negative cache for missing ids; the search cache
treats an empty array as a valid cached value.

Writes call `detailCache.set(id, newJson)` and `searchCache.purge()`. This is
deliberately simple: pepper has no tag invalidation in v0.1.

The cache stores **encoded JSON**, not model objects. A hit therefore avoids
both SQLite and repeated `jsonEncode` work.

## Configuration

```text
--host=127.0.0.1
--port=8080
--db=data/relics.db
--no-cache
--algorithm=lru|lfu|fifo
--capacity=10000
--search-capacity=2000
--missing-capacity=5000
--ttl-ms=60000
--search-ttl-ms=30000
--jitter-ms=5000
--db-delay-us=0
--log
--seed
--seed-count=50000
```

`--db-delay-us` injects a delay before every SQLite operation. It is used by
the benchmark to model a remote database; it is not a real network database.

## Benchmark

```sh
dart run bench/run.dart --profile=quick
dart run bench/run.dart --profile=full
```

The harness:

1. Seeds 50,000 deterministic relics.
2. Generates a 100,000-URL trace: 60% detail, 25% batch, 10% search, 5% missing
   ids, with detail ids drawn from a Zipf(1.0) distribution.
3. Builds the server as an AOT CLI bundle with `dart build cli`.
4. Starts the server, warms it with `oha`, then runs the matrix.
5. Writes `bench/results/latest.md` and `bench/results/latest.json`, plus raw
   `oha` output under `bench/results/raw/`.

The full matrix compares:

- no cache vs pepper, local SQLite
- no cache vs pepper, 2 ms simulated backend latency
- LRU vs LFU
- detail capacity 100 / 1k / 10k / 50k
- 1,000 concurrent requests for a cold key
- 1,000 concurrent 404s with negative caching

On the reference run (Apple M5, Dart 3.12.2, 100,000-URL trace, 64 connections,
three 20-second runs), the local-SQLite mixed workload went from **1,116 req/s**
without caching to **21,562 req/s** with a 10k LRU entry cache; p99 fell from
**111 ms** to **14.3 ms**. With a simulated 2 ms backend it went from 1,109 to
20,450 req/s. A 1,000-request cold burst issued **1** SQLite query with pepper
versus **1,000** without, and negative caching did the same for the 404 burst.

See the generated report for the full capacity sweep, LFU comparison and
methodology caveats. The benchmark client runs on the same machine as the
server; relative deltas matter more than absolute RPS.

`dart compile exe` cannot be used here because `sqlite3` uses build hooks. The
harness uses `dart build cli`, which produces
`build/server/bundle/bin/server`.

## Tests

```sh
dart test
dart analyze --fatal-infos
```

Service tests cover hit/miss behavior, single-flight, negative caching, TTL,
batch reads, update invalidation and the no-cache path. HTTP tests exercise the
Relic routes and the stats/purge endpoints.

## Notes

- The demo binds to `127.0.0.1` by default.
- There is no authentication. Do not expose `/api/cache/purge` publicly.
- One isolate only: pepper state is per isolate.
- SQLite is synchronous in this prototype.
- The UI is intentionally dependency-free and uses only inline HTML/CSS/JS.
