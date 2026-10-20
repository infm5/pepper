# Relic Vault benchmark

The benchmark measures the complete HTTP path: `oha` → Relic router → pepper →
SQLite → JSON response.

## Run

```sh
# From example/relic_vault
dart run bench/run.dart --profile=quick
dart run bench/run.dart --profile=full
```

The harness seeds 50,000 deterministic relics, generates the URL trace, builds
the server with `dart build cli`, and writes:

- `bench/results/latest.md` — readable report
- `bench/results/latest.json` — machine-readable summary
- `bench/results/raw/*.json` — raw `oha` output

## Workload

The trace contains 100,000 URLs:

| Share | Request |
|---:|---|
| 60% | `GET /api/relics/:id` |
| 25% | `GET /api/relics?ids=a,b,c` |
| 10% | `GET /api/relics?q=...&limit=20` |
| 5% | `GET /api/relics/900000000` |

Detail ids are sampled from Zipf(1.0) over the 50,000 relics, so a small hot
set receives most traffic. Search queries are 80% hot terms and 20% long-tail
combinations, with optional culture/era filters. The trace is deterministic.

## Scenarios

### Throughput

- local SQLite, no cache
- local SQLite, pepper LRU
- 2 ms simulated backend, no cache
- 2 ms simulated backend, pepper LRU 10k
- 2 ms simulated backend, pepper LFU 10k
- 2 ms simulated backend, pepper LRU capacities 100, 1k and 50k

The 2 ms delay is injected before every SQLite operation. It is a deliberate
model of a remote database, not a real network database. Benchmark runs use a
5 minute TTL so entries do not expire mid-scenario; the demo defaults are 60
seconds for detail and 30 seconds for search.

### Cold-start and negative cache

- 1,000 concurrent requests for one uncached relic
- 1,000 concurrent requests for one missing relic

Both run with and without pepper. Every cold run starts a fresh server so the
cache is truly empty.

## Metrics

- requests per second
- p50/p95/p99 latency
- cache hit rate (detail and search)
- SQLite queries per request
- RSS
- expected vs failed responses

404 is treated as an expected response, because the workload intentionally
requests missing ids.

## Caveats

- One isolate. pepper is intentionally per-isolate.
- `oha` runs on the same machine as the server.
- SQLite is synchronous.
- Search is a `LIKE` scan, not FTS5. It is a deliberately expensive read to
  exercise caching.
- Absolute RPS is machine-specific; the no-cache/pepper delta is the useful
  result.

## Reading a result

A healthy cached run should show:

- a high detail hit rate on the hot detail/batch traffic
- a high search hit rate for the hot-query portion
- far fewer SQLite queries per request than the no-cache baseline
- lower p95/p99 latency under the simulated backend delay
- more RSS, because the cache holds encoded JSON

The cold burst should show one SQLite query with pepper, versus one per request
without it. The 404 burst should show the same pattern via negative caching.
