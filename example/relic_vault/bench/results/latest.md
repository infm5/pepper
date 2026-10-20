# Relic Vault benchmark

Generated: 2026-10-20T19:15:55.034991
Profile: **full**
Workload: **100000** URL trace, **64** connections, **20s** per run, **3** runs per scenario.

## Environment

- **os:** Version 26.4 (Build 25E246)
- **dart:** Dart SDK version: 3.12.2 (stable) (Tue Jun 9 01:11:39 2026 -0700) on "macos_arm64"
- **oha:** oha 1.16.0
- **sqlite:** 3.51.2 2026-01-09 17:27:48 b270f8339eb13b504d0b2ba154ebca966b7dde08e40c3ed7d559749818cb2075 (64-bit)
- **cpu:** Apple M5
- **memory:** 16.0 GB

## Throughput

| Scenario | RPS | p50 ms | p95 ms | p99 ms | Errors | Detail hit | Search hit | DB q/req | RSS MB |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| local-no-cache | 1116 | 55.81 | 92.64 | 110.65 | 0.0% | — | — | 1.000 | 50.4 |
| local-pepper-lru | 21562 | 1.76 | 11.76 | 14.33 | 0.0% | 82.0% | 97.0% | 0.183 | 62.9 |
| backend-2ms-no-cache | 1109 | 55.82 | 95.36 | 112.74 | 0.0% | — | — | 1.000 | 51.1 |
| backend-2ms-pepper-lru-10k | 20450 | 1.30 | 13.10 | 21.06 | 0.0% | 82.1% | 96.9% | 0.182 | 80.8 |
| backend-2ms-pepper-lfu-10k | 19611 | 1.44 | 13.42 | 19.99 | 0.0% | 83.8% | 96.9% | 0.164 | 79.8 |
| backend-2ms-pepper-lru-100 | 1663 | 38.42 | 77.00 | 97.23 | 0.0% | 28.1% | 33.3% | 0.702 | 61.4 |
| backend-2ms-pepper-lru-1k | 3153 | 18.25 | 51.75 | 67.00 | 0.0% | 53.0% | 67.7% | 0.504 | 63.9 |
| backend-2ms-pepper-lru-50k | 19412 | 1.76 | 13.94 | 20.07 | 0.0% | 95.1% | 97.0% | 0.019 | 87.9 |

## Cold-start and negative-cache bursts

| Scenario | Requests | DB queries | DB q/req | RPS | p95 ms | p99 ms |
|---|---:|---:|---:|---:|---:|---:|
| cold-detail-no-cache | 3000 | 3000 | 1.0000 | 18152 | 6.76 | 7.54 |
| cold-detail-pepper | 3000 | 3 | 0.0010 | 31435 | 6.88 | 7.43 |
| cold-404-no-cache | 3000 | 3000 | 1.0000 | 19271 | 6.58 | 7.30 |
| cold-404-pepper | 3000 | 3 | 0.0010 | 31914 | 6.59 | 6.62 |

Each cold scenario sends 1,000 requests per run; the DB-query column is the total across runs. Pepper issues one SQLite query per burst.

## Method

- `oha` drives a generated URL mix: 60% detail, 25% batch, 10% search, 5% missing ids. Detail ids are Zipf(1.0) distributed over 50000 relics.
- The server is the AOT CLI bundle from `dart build cli`, running in one isolate. Relic routing and pepper caches are in the same process.
- `backend-2ms` scenarios inject an explicit 2 ms delay before every SQLite operation. The delay is simulated, not a network database.
- Throughput numbers are medians across runs for RPS and latency; cache hit rates and DB queries per request are aggregated across runs.
- Benchmark caches use a 5 minute TTL so entries do not expire in the middle of a scenario. The demo defaults are 60 s for detail and 30 s for search.
- `oha` runs on the same machine as the server. Absolute numbers are machine-specific; the no-cache and pepper deltas are the point.
- A 404 is treated as an expected response in error-rate accounting; only 5xx and transport errors count as failures.
- Search is intentionally a simple `LIKE` scan over SQLite. It is not FTS5; the goal is to exercise cache behavior, not search quality.

Raw `oha` JSON is in `bench/results/raw/`.
