// as seen in: https://github.com/misha/dart-hlc/blob/master/lib/hlc.dart

import 'hlc.utils.dart';

/// A hybrid logical clock implementation with string-based nodes.
///
/// HLC provides causally-ordered timestamps that work correctly even when
/// device clocks are out of sync. It combines a physical timestamp with a
/// logical counter to ensure unique, monotonically increasing timestamps.
class HLC implements Comparable<HLC> {
  final int timestamp;

  final int count;

  final String node;

  /// The delimiter used in packed string representation.
  static const String _delimiter = ':';

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

  /// Try to parse an HLC from its packed string representation.
  ///
  /// Returns null if the string is invalid or cannot be parsed.
  ///
  /// The expected format is: `{timestamp}:{count}:{node}`
  /// where timestamp is a 15-digit padded integer and count is base-36 encoded.
  static HLC? tryParse(String packed) {
    if (packed.isEmpty) return null;

    try {
      final parts = packed.split(_delimiter);
      if (parts.length < 3) return null;

      return HLC(
        timestamp: int.parse(parts[0]),
        count: int.parse(parts[1], radix: 36),
        node: parts.sublist(2).join(_delimiter),
      );
    } catch (e) {
      return null;
    }
  }

  /// Compare two HLC timestamp strings.
  ///
  /// Returns:
  /// - negative if [a] < [b]
  /// - zero if [a] == [b]
  /// - positive if [a] > [b]
  ///
  /// If either string cannot be parsed, returns 0.
  static int compareTimestamps(String a, String b) {
    final hlcA = tryParse(a);
    final hlcB = tryParse(b);

    if (hlcA == null && hlcB == null) return 0;
    if (hlcA == null) return -1;
    if (hlcB == null) return 1;

    return hlcA.compareTo(hlcB);
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
