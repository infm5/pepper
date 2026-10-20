/// A source of monotonically increasing timestamps, in microseconds.
///
/// Cache expiry is measured against this clock rather than [DateTime.now], so
/// it is immune to wall-clock adjustments. Implementations are used from the
/// cache's isolate only.
abstract interface class TimeSource {
  /// The number of microseconds elapsed since a fixed, arbitrary origin.
  ///
  /// Values are only meaningful when compared with other values returned by
  /// the same source.
  int nowMicros();
}

/// A [TimeSource] backed by a [Stopwatch].
final class MonotonicTimeSource implements TimeSource {
  /// Creates a source whose origin is the moment of construction.
  MonotonicTimeSource() : _stopwatch = Stopwatch()..start();

  /// A process-wide shared instance.
  static final MonotonicTimeSource shared = MonotonicTimeSource();

  final Stopwatch _stopwatch;

  @override
  int nowMicros() => _stopwatch.elapsedMicroseconds;
}
