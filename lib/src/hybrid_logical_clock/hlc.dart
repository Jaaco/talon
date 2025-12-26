import 'hlc.utils.dart';

/// A Hybrid Logical Clock (HLC) timestamp.
///
/// HLC provides causally-ordered timestamps that work correctly even when
/// device clocks are out of sync. It combines a physical timestamp with a
/// logical counter to ensure unique, monotonically increasing timestamps.
///
/// ## Why HLC?
///
/// In distributed systems like offline-first apps, devices may have different
/// clock times. HLC solves this by:
/// - Using physical time when available for human-readable ordering
/// - Falling back to logical ordering when clocks are out of sync
/// - Ensuring strict causal ordering of events
///
/// ## Components
///
/// An HLC has three parts:
/// - [timestamp]: Wall clock time in milliseconds
/// - [count]: Logical counter for same-millisecond ordering
/// - [node]: Device/client identifier for tie-breaking
///
/// ## Comparison
///
/// HLCs are compared in order: timestamp → count → node.
/// This ensures a total ordering of all events across all devices.
///
/// ## String Format
///
/// HLCs serialize to: `{timestamp}:{count}:{node}`
/// - timestamp: 15-digit zero-padded milliseconds
/// - count: 5-digit zero-padded base-36 number
/// - node: Client/device identifier
///
/// Example: `000001704067200000:00001:device-abc`
///
/// ## Usage
///
/// Most users don't interact with HLC directly. Talon manages it internally.
/// For advanced use cases:
///
/// ```dart
/// // Parse an HLC from a string
/// final hlc = HLC.tryParse(message.localTimestamp);
///
/// // Compare two HLC timestamps
/// final comparison = HLC.compareTimestamps(ts1, ts2);
/// if (comparison > 0) {
///   // ts1 is newer than ts2
/// }
/// ```
///
/// ## References
///
/// Based on the HLC algorithm from:
/// - [Logical Physical Clocks](https://cse.buffalo.edu/tech-reports/2014-04.pdf)
/// - [dart-hlc](https://github.com/misha/dart-hlc)
class HLC implements Comparable<HLC> {
  /// The physical timestamp in milliseconds since epoch.
  ///
  /// This is typically the wall clock time when the event occurred,
  /// but may be adjusted to maintain causal ordering.
  final int timestamp;

  /// The logical counter for ordering events within the same millisecond.
  ///
  /// Increments when multiple events occur in the same millisecond
  /// or when the physical clock hasn't advanced.
  final int count;

  /// The node/device identifier.
  ///
  /// Used for tie-breaking when timestamp and count are equal.
  /// Typically the client ID.
  final String node;

  /// The delimiter used in packed string representation.
  static const String _delimiter = ':';

  /// Creates an HLC with the given components.
  ///
  /// For creating a new HLC at the current time, use [HLC.now].
  /// For parsing from a string, use [HLC.tryParse].
  HLC({
    required this.timestamp,
    required this.count,
    required this.node,
  });

  /// Creates an HLC at the current wall clock time.
  ///
  /// The count is initialized to 0. Use this for creating the
  /// initial HLC state for a new device.
  ///
  /// Example:
  /// ```dart
  /// final initialClock = HLC.now('device-123');
  /// ```
  static HLC now(String node) {
    return HLC(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      count: 0,
      node: node,
    );
  }

  /// Parses an HLC from its packed string representation.
  ///
  /// Returns null if the string is invalid or cannot be parsed.
  /// This is safe to use with untrusted input.
  ///
  /// The expected format is: `{timestamp}:{count}:{node}`
  /// - timestamp: Integer (usually 15-digit padded)
  /// - count: Base-36 encoded integer
  /// - node: String identifier (may contain delimiters)
  ///
  /// Example:
  /// ```dart
  /// final hlc = HLC.tryParse('000001704067200000:00001:device-123');
  /// if (hlc != null) {
  ///   print('Timestamp: ${hlc.timestamp}');
  /// }
  /// ```
  static HLC? tryParse(String packed) {
    if (packed.isEmpty) return null;

    try {
      final parts = packed.split(_delimiter);
      if (parts.length < 3) return null;

      return HLC(
        timestamp: int.parse(parts[0]),
        count: int.parse(parts[1], radix: 36),
        // Node may contain delimiters, so join remaining parts
        node: parts.sublist(2).join(_delimiter),
      );
    } catch (e) {
      return null;
    }
  }

  /// Compares two HLC timestamp strings.
  ///
  /// This is a convenience method for comparing HLC strings without
  /// manually parsing them.
  ///
  /// Returns:
  /// - Negative if [a] < [b] (a is earlier)
  /// - Zero if [a] == [b] (same time)
  /// - Positive if [a] > [b] (a is later)
  ///
  /// If either string cannot be parsed:
  /// - Both invalid: returns 0
  /// - Only [a] invalid: returns -1 (invalid treated as earlier)
  /// - Only [b] invalid: returns 1
  ///
  /// Example:
  /// ```dart
  /// final result = HLC.compareTimestamps(
  ///   message1.localTimestamp,
  ///   message2.localTimestamp,
  /// );
  /// if (result > 0) {
  ///   // message1 is newer, use its value
  /// }
  /// ```
  static int compareTimestamps(String a, String b) {
    final hlcA = tryParse(a);
    final hlcB = tryParse(b);

    if (hlcA == null && hlcB == null) return 0;
    if (hlcA == null) return -1;
    if (hlcB == null) return 1;

    return hlcA.compareTo(hlcB);
  }

  /// Compares this HLC to another for ordering.
  ///
  /// Comparison order: [timestamp] → [count] → [node]
  ///
  /// Returns:
  /// - Negative if this < other
  /// - Zero if this == other
  /// - Positive if this > other
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

  /// Returns the packed string representation of this HLC.
  ///
  /// Format: `{timestamp}:{count}:{node}`
  ///
  /// The output can be parsed back using [HLC.tryParse].
  @override
  String toString() {
    return HLCUtils(node).pack(this);
  }
}

/// Exception thrown when a received clock's time drift exceeds the maximum.
///
/// This exception is thrown by [HLCUtils.receive] when the [maximumDrift]
/// parameter is set and the remote clock's timestamp is too far in the future
/// relative to the local wall clock.
///
/// ## Why Limit Drift?
///
/// Allowing unlimited clock drift can cause problems:
/// - A malicious or misconfigured client could set their clock far in the future
/// - Their changes would always "win" in last-write-wins conflict resolution
/// - Other clients would have to advance their clocks to catch up
///
/// By limiting drift, you can reject messages from clients with severely
/// misconfigured clocks.
///
/// ## Handling
///
/// When this exception is thrown, you might:
/// - Log the error for monitoring
/// - Reject the message
/// - Notify the user to check their device clock
///
/// Example:
/// ```dart
/// try {
///   hlcState.receive(remoteHlc);
/// } on TimeDriftException catch (e) {
///   print('Clock drift too large: ${e.drift}');
///   print('Maximum allowed: ${e.maximumDrift}');
///   // Handle the error appropriately
/// }
/// ```
class TimeDriftException implements Exception {
  /// The actual drift between the remote clock and local time.
  ///
  /// Positive values mean the remote clock is ahead of local time.
  final Duration drift;

  /// The maximum allowed drift that was exceeded.
  final Duration maximumDrift;

  /// Creates a TimeDriftException with the given drift values.
  const TimeDriftException({
    required this.drift,
    required this.maximumDrift,
  });

  /// A human-readable message describing the exception.
  String get message =>
      'TimeDriftException: The received clock\'s time drift (${drift.inSeconds}s) '
      'exceeds the maximum allowed (${maximumDrift.inSeconds}s).';

  @override
  String toString() => message;
}
