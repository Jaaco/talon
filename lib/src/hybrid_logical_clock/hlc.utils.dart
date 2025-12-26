import 'dart:math';

import 'hlc.dart';

/// Utility class for Hybrid Logical Clock operations.
///
/// Provides the core HLC algorithms for:
/// - Generating new timestamps when sending messages ([send])
/// - Updating the clock when receiving messages ([receive])
/// - Serializing/deserializing HLC to/from strings ([pack]/[unpack])
///
/// This is an internal class. Most users should use [HLCState] instead,
/// which provides a simpler stateful interface.
///
/// ## Algorithm Overview
///
/// The HLC algorithm ensures causally-ordered timestamps even when
/// device clocks are out of sync. It combines:
/// - Physical time (wall clock milliseconds)
/// - Logical counter (for same-millisecond ordering)
/// - Node identifier (for tie-breaking)
///
/// ## References
///
/// Based on the HLC algorithm from:
/// - [Logical Physical Clocks](https://cse.buffalo.edu/tech-reports/2014-04.pdf)
/// - [dart-hlc](https://github.com/misha/dart-hlc)
class HLCUtils {
  /// The device/client ID used as the node identifier in HLC timestamps.
  final String deviceId;

  /// The delimiter character used in packed string representation.
  ///
  /// Format: `{timestamp}:{count}:{node}`
  final String delimiter = ':';

  /// Creates a new [HLCUtils] for the given device/client ID.
  HLCUtils(this.deviceId);

  /// Generates a new HLC timestamp for sending a message.
  ///
  /// The algorithm ensures the new timestamp is:
  /// - Greater than or equal to the current wall clock time
  /// - Greater than the previous clock value
  /// - Monotonically increasing
  ///
  /// Parameters:
  /// - [oldClock]: The current HLC state before this send
  ///
  /// Returns a new [HLC] that should be used as the message timestamp.
  ///
  /// ## Algorithm
  ///
  /// 1. Get current wall clock time
  /// 2. Use max(wall clock, old timestamp) as new timestamp
  /// 3. If wall clock advanced, reset counter to 0
  /// 4. Otherwise, increment counter
  HLC send(HLC oldClock) {
    final physicalTimeOld = oldClock.timestamp;
    final physicalTimeNow = DateTime.now().millisecondsSinceEpoch;

    final newPhysicalTime = max(physicalTimeNow, physicalTimeOld);

    final newCounter =
        physicalTimeNow > physicalTimeOld ? 0 : oldClock.count + 1;

    final newClock =
        HLC(timestamp: newPhysicalTime, count: newCounter, node: deviceId);

    return newClock;
  }

  /// Updates the local clock after receiving a message with a remote HLC.
  ///
  /// Ensures the local clock is at least as advanced as the remote clock,
  /// maintaining causal ordering across distributed nodes.
  ///
  /// Parameters:
  /// - [local]: The current local HLC state
  /// - [remote]: The HLC from the received message
  /// - [maximumDrift]: Optional maximum allowed clock drift. If the remote
  ///   clock is too far in the future, throws [TimeDriftException].
  /// - [now]: Optional current time for testing. Defaults to wall clock.
  ///
  /// Returns a new [HLC] representing the updated local clock.
  ///
  /// Throws [TimeDriftException] if [maximumDrift] is set and the remote
  /// clock's timestamp exceeds the allowed drift from current time.
  ///
  /// ## Algorithm
  ///
  /// 1. If current time is ahead of both clocks, use current time (counter=0)
  /// 2. If remote is ahead, adopt remote timestamp with incremented counter
  /// 3. If local is ahead, keep local timestamp with incremented counter
  /// 4. If equal, use max counter + 1
  HLC receive(
    HLC local,
    HLC remote, {
    Duration? maximumDrift,
    int? now,
  }) {
    now ??= DateTime.now().millisecondsSinceEpoch;

    if (maximumDrift != null) {
      final drift = Duration(milliseconds: remote.timestamp - now);

      if (drift > maximumDrift) {
        throw TimeDriftException(
          drift: drift,
          maximumDrift: maximumDrift,
        );
      }
    }

    if (now > local.timestamp && now > remote.timestamp) {
      return HLC(
        timestamp: now,
        count: 0,
        node: deviceId,
      );
    }

    if (local.timestamp < remote.timestamp) {
      return HLC(
        timestamp: remote.timestamp,
        count: remote.count + 1,
        node: deviceId,
      );
    } else if (local.timestamp > remote.timestamp) {
      return HLC(
        timestamp: local.timestamp,
        count: local.count + 1,
        node: deviceId,
      );
    } else {
      return HLC(
        timestamp: local.timestamp,
        count: max(local.count, remote.count) + 1,
        node: deviceId,
      );
    }
  }

  /// Serializes an HLC to a string for storage/transmission.
  ///
  /// Format: `{timestamp}:{count}:{node}`
  /// - timestamp: 15-digit zero-padded milliseconds
  /// - count: 5-digit zero-padded base-36 encoded counter
  /// - node: The device/client ID
  ///
  /// Example output: `000001704067200000:00001:device-123`
  ///
  /// The padding ensures lexicographic string comparison produces
  /// the correct ordering for most practical use cases.
  String pack(HLC clock) {
    final buffer = StringBuffer();
    buffer.write(clock.timestamp.toString().padLeft(15, '0'));
    buffer.write(delimiter);
    buffer.write(clock.count.toRadixString(36).padLeft(5, '0'));
    buffer.write(delimiter);
    buffer.write(clock.node);
    return buffer.toString();
  }

  /// Deserializes an HLC from its packed string representation.
  ///
  /// The string should be in the format produced by [pack].
  ///
  /// Note: This method assumes the string is valid. For parsing
  /// untrusted input, use [HLC.tryParse] instead.
  ///
  /// Throws if the string format is invalid.
  HLC unpack(String packed) {
    final parts = packed.split(delimiter);

    return HLC(
      timestamp: int.parse(parts[0]),
      count: int.parse(parts[1], radix: 36),
      node: parts.sublist(2).join(delimiter),
    );
  }
}
