// as seen in: https://github.com/misha/dart-hlc/blob/master/lib/hlc.dart

import 'hlc.utils.dart';

/// A hybrid logical clock implementation with string-based nodes.
class HLC implements Comparable<HLC> {
  final int timestamp;

  final int count;

  final String node;

  HLC({
    required this.timestamp,
    required this.count,
    required this.node,
  });

  /// Constructs an initial HLC using the current wall clock.
  static HLC now(String node) {
    return HLC(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      count: 0,
      node: node,
    );
  }

  @override
  int compareTo(HLC other) {
    var result = timestamp.compareTo(other.timestamp);

    if (result != 0) {
      return result;
    }

    result = count.compareTo(other.count);

    if (result != 0) {
      return result;
    }

    return node.compareTo(other.node);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is HLC &&
            timestamp == other.timestamp &&
            count == other.count &&
            node == other.node);
  }

  @override
  int get hashCode => Object.hash(
        runtimeType,
        timestamp.hashCode,
        count.hashCode,
        node.hashCode,
      );

  @override
  String toString() {
    return HLCUtils(node).pack(this);
  }
}

class TimeDriftException implements Exception {
  final Duration drift;

  final Duration maximumDrift;

  const TimeDriftException({
    required this.drift,
    required this.maximumDrift,
  });

  String get message =>
      'TimeDriftException: The received clock\'s time drift exceeds the maximum.';
}
