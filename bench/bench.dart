import 'dart:math';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:collection/collection.dart';
import 'package:pepper/pepper.dart';

const _opsPerRun = 20000;

final class _Bench extends BenchmarkBase {
  _Bench(super.name, this.body);

  final void Function() body;

  @override
  void run() => body();

  @override
  void exercise() => body();
}

void main() async {
  print(
    'pepper benchmarks — $_opsPerRun ops per run, warmup + 2s measurement\n',
  );

  _benchPair(
    'LruCache set+get',
    resident: () => LruCache<int, int>(capacity: 100000),
    evicting: () => LruCache<int, int>(capacity: 1000),
  );
  _benchPair(
    'LfuCache set+get',
    resident: () => LfuCache<int, int>(capacity: 100000),
    evicting: () => LfuCache<int, int>(capacity: 1000),
  );
  _benchPair(
    'FifoCache set+get',
    resident: () => FifoCache<int, int>(capacity: 100000),
    evicting: () => FifoCache<int, int>(capacity: 1000),
  );

  _facadeBenchmarks();

  print('');
  _zipfHitRates();
  print('');
  _scanResistance();
}

void _benchPair(
  String name, {
  required InMemoryCache<int, int> Function() resident,
  required InMemoryCache<int, int> Function() evicting,
}) {
  _report('$name, resident', () {
    final cache = resident();
    var counter = 0;
    return () {
      for (var i = 0; i < _opsPerRun; i++) {
        final key = counter++ & 1023;
        cache.set(key, i);
        cache.get(key);
      }
    };
  }());
  _report('$name, evicting', () {
    final cache = evicting();
    var counter = 0;
    return () {
      for (var i = 0; i < _opsPerRun; i++) {
        final key = counter++ & 2047;
        cache.set(key, i);
        cache.get(key);
      }
    };
  }());
}

void _facadeBenchmarks() {
  _report('HotCache set+get, resident', () {
    final cache = HotCache<int, int>(
      algorithm: EvictionAlgorithm.lru,
      capacity: 100000,
    );
    var counter = 0;
    return () {
      for (var i = 0; i < _opsPerRun; i++) {
        final key = counter++ & 1023;
        cache.set(key, i);
        cache.get(key);
      }
    };
  }());

  _report('HotCache get hit, ttl+expiry check', () {
    final cache = HotCache<int, int>(
      algorithm: EvictionAlgorithm.lru,
      capacity: 1024,
      ttl: const Duration(hours: 1),
    );
    for (var i = 0; i < 1024; i++) {
      cache.set(i, i);
    }
    var counter = 0;
    return () {
      for (var i = 0; i < _opsPerRun; i++) {
        cache.get(counter++ & 1023);
      }
    };
  }());

  _report('HotCache set, ttl+jitter', () {
    final cache = HotCache<int, int>(
      algorithm: EvictionAlgorithm.lru,
      capacity: 100000,
      ttl: const Duration(minutes: 5),
      jitter: const Duration(seconds: 30),
    );
    var counter = 0;
    return () {
      for (var i = 0; i < _opsPerRun; i++) {
        cache.set(counter++ & 1023, i);
      }
    };
  }());

  _report('HotCache get hit, negative cache enabled', () {
    final cache = HotCache<int, int>(
      algorithm: EvictionAlgorithm.lru,
      capacity: 1024,
      missingCache: const MissingCacheConfig.shared(),
    );
    for (var i = 0; i < 1024; i++) {
      cache.set(i, i);
    }
    var counter = 0;
    return () {
      for (var i = 0; i < _opsPerRun; i++) {
        cache.get(counter++ & 1023);
      }
    };
  }());

  _report('HotCache get miss', () {
    final cache = HotCache<int, int>(
      algorithm: EvictionAlgorithm.lru,
      capacity: 1024,
    );
    var counter = 0;
    return () {
      for (var i = 0; i < _opsPerRun; i++) {
        cache.get(-(counter++ & 1023) - 1);
      }
    };
  }());

  _asyncReport('HotCache getOrLoad hit (async)', () async {
    final cache = HotCache<int, int>(
      algorithm: EvictionAlgorithm.lru,
      capacity: 1024,
      loaders: [
        (keys) async => {for (final key in keys) key: 1},
      ],
    );
    for (var i = 0; i < 1024; i++) {
      cache.set(i, i);
    }
    var counter = 0;
    return () {
      return cache.getOrLoad(counter++ & 1023);
    };
  });
}

void _report(String name, void Function() body) {
  final bench = _Bench(name, body);
  final microsPerRun = bench.measure();
  _printResult(name, microsPerRun * 1000 / _opsPerRun);
}

void _asyncReport(
  String name,
  Future<Future<void> Function()> Function() setup,
) async {
  final load = await setup();
  for (var i = 0; i < 5000; i++) {
    await load();
  }
  const ops = 50000;
  final watch = Stopwatch()..start();
  for (var i = 0; i < ops; i++) {
    await load();
  }
  final micros = watch.elapsedMicroseconds;
  _printResult(name, micros * 1000 / ops);
}

void _printResult(String name, double nsPerOp) {
  final opsPerSecond = 1e9 / nsPerOp;
  print(
    '${name.padRight(44)}'
    '${nsPerOp.toStringAsFixed(1).padLeft(9)} ns/op'
    '${_group((opsPerSecond / 1000).round()).padLeft(12)} K ops/s',
  );
}

String _group(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

List<int> _zipfTrace(int accesses, int keys, double exponent, Random random) {
  final cumulative = List<double>.filled(keys, 0);
  var total = 0.0;
  for (var i = 0; i < keys; i++) {
    total += 1 / pow(i + 1, exponent);
    cumulative[i] = total;
  }
  final trace = List<int>.filled(accesses, 0);
  for (var i = 0; i < accesses; i++) {
    final target = random.nextDouble() * total;
    trace[i] = lowerBound(cumulative, target);
  }
  return trace;
}

void _zipfHitRates() {
  const capacity = 1000;
  final trace = _zipfTrace(100000, 10000, 1.0, Random(42));
  print('Zipf(1.0) trace: 100k accesses over 10k keys, capacity $capacity');
  final caches = <String, InMemoryCache<int, int>>{
    'LruCache': LruCache<int, int>(capacity: capacity),
    'LfuCache': LfuCache<int, int>(capacity: capacity),
    'FifoCache': FifoCache<int, int>(capacity: capacity),
  };
  caches.forEach((name, cache) {
    var hits = 0;
    for (final key in trace) {
      if (cache.get(key) != null) {
        hits++;
      } else {
        cache.set(key, key);
      }
    }
    final rate = hits * 100 / trace.length;
    print('${name.padRight(12)} ${rate.toStringAsFixed(2)}% hit rate');
  });
}

void _scanResistance() {
  const hotKeys = 1000;
  const scanKeys = 20000;
  print('scan resistance: $hotKeys hot keys, then a $scanKeys-key scan');
  final caches = <String, InMemoryCache<int, int>>{
    'LruCache': LruCache<int, int>(capacity: hotKeys),
    'LfuCache': LfuCache<int, int>(capacity: hotKeys),
    'FifoCache': FifoCache<int, int>(capacity: hotKeys),
  };
  caches.forEach((name, cache) {
    for (var i = 0; i < hotKeys; i++) {
      cache.set(i, i);
    }
    for (var round = 0; round < 4; round++) {
      for (var i = 0; i < hotKeys; i++) {
        cache.get(i);
      }
    }
    for (var i = 0; i < scanKeys; i++) {
      cache.set(1000000 + i, i);
    }
    var retained = 0;
    for (var i = 0; i < hotKeys; i++) {
      if (cache.containsKey(i)) {
        retained++;
      }
    }
    final rate = retained * 100 / hotKeys;
    print('${name.padRight(12)} ${rate.toStringAsFixed(1)}% hot keys retained');
  });
}
