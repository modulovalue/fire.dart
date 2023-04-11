import 'dart:async';

Future<MapEntry<String, T>> measure_in_ms<T>({
  required final FutureOr<T> Function() fn,
}) async {
  final stopwatch = Stopwatch();
  stopwatch.start();
  final result = await fn();
  stopwatch.stop();
  final ms = stopwatch.elapsed.inMicroseconds / 1000;
  stopwatch.reset();
  return MapEntry(ms.toStringAsFixed(2) + " ms.", result);
}

extension SafeMapExtension<K, V extends Object> on Map<K, V> {
  void force_set(
    final K key,
    final V value,
  ) {
    if (typed_contains_key(key)) {
      throw Exception("Key already inside the map.");
    } else {
      this[key] = value;
    }
  }

  V? typed_get(
    final K key,
  ) {
    return this[key];
  }

  bool typed_contains_key(
    final K key,
  ) {
    return this.containsKey(key);
  }
}
