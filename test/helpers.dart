import 'dart:math';

import 'package:pepper/pepper.dart';

/// A manually advanced [TimeSource] for deterministic expiry tests.
final class FakeTime implements TimeSource {
  int _micros = 0;

  @override
  int nowMicros() => _micros;

  /// Advances the clock by [duration].
  void advance(Duration duration) => _micros += duration.inMicroseconds;
}

/// A [Random] returning fixed values.
final class FixedRandom implements Random {
  FixedRandom({this.intValue = 0, this.doubleValue = 0});

  final int intValue;
  final double doubleValue;

  @override
  int nextInt(int max) => intValue % max;

  @override
  double nextDouble() => doubleValue;

  @override
  bool nextBool() => false;
}

/// A loader that records the batches it was called with.
final class RecordingLoader<K, V> {
  RecordingLoader(this._resolve);

  final Future<Map<K, V>> Function(Set<K> keys) _resolve;

  /// The batches passed to the loader, in call order.
  final List<Set<K>> calls = [];

  /// The number of loader invocations.
  int get callCount => calls.length;

  /// Resolves [keys] through the underlying function, recording the call.
  Future<Map<K, V>> call(Set<K> keys) {
    calls.add(Set<K>.of(keys));
    return _resolve(keys);
  }
}
