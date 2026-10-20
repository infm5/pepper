import 'dart:async';
import 'dart:collection';

/// The value delivered to each waiter of a load batch.
final class LoadOutcome<V> {
  /// Creates an outcome holding a loaded [value].
  const LoadOutcome.found(this.value) : isFound = true;

  /// Creates an outcome reporting that the key was not found.
  const LoadOutcome.notFound() : value = null, isFound = false;

  /// The loaded value, or `null` when not found.
  final V? value;

  /// Whether the loader returned a value.
  final bool isFound;
}

/// Deduplicates concurrent loads and batches keys requested within the same
/// event-loop turn into a single loader call.
///
/// The first [load] schedules a microtask that collects every key requested
/// before it runs and invokes the batch runner once. Callers arriving while a
/// batch is in flight join it instead of triggering another call, and each
/// waiter receives the outcome for its own key.
final class LoadBatcher<K, V> {
  /// Creates a batcher resolving each batch through [runBatch].
  LoadBatcher(this._runBatch);

  final Future<Map<K, V>> Function(Set<K> keys) _runBatch;
  final Map<K, Completer<LoadOutcome<V>>> _inFlight =
      HashMap<K, Completer<LoadOutcome<V>>>();
  final Set<K> _pending = HashSet<K>();
  bool _scheduled = false;

  /// Schedules [key] for loading, joining an in-flight batch when possible.
  Future<LoadOutcome<V>> load(K key) {
    final existing = _inFlight[key];
    if (existing != null) {
      return existing.future;
    }
    final completer = Completer<LoadOutcome<V>>();
    _inFlight[key] = completer;
    _pending.add(key);
    if (!_scheduled) {
      _scheduled = true;
      scheduleMicrotask(_flush);
    }
    return completer.future;
  }

  Future<void> _flush() async {
    _scheduled = false;
    if (_pending.isEmpty) {
      return;
    }
    final keys = Set<K>.of(_pending);
    _pending.clear();
    try {
      final found = await _runBatch(keys);
      for (final key in keys) {
        final completer = _inFlight.remove(key);
        if (completer == null) {
          continue;
        }
        final value = found[key];
        completer.complete(
          value == null
              ? LoadOutcome<V>.notFound()
              : LoadOutcome<V>.found(value),
        );
      }
    } catch (error, stackTrace) {
      for (final key in keys) {
        _inFlight.remove(key)?.completeError(error, stackTrace);
      }
    }
  }
}
