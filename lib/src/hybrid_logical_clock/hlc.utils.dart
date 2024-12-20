import 'dart:math';

import 'hlc.dart';

class HLCUtils {
  final String deviceId;
  final String delimiter = ':';

  HLCUtils(this.deviceId);

  HLC send(HLC oldClock) {
    final physicalTimeOld = oldClock.timestamp;
    final physicalTimeNow = DateTime.now().millisecondsSinceEpoch;

    final newPhysicalTime = max(physicalTimeNow, physicalTimeOld);
    // todo could implement maxDriftError here

    final newCounter =
        physicalTimeNow > physicalTimeOld ? 0 : oldClock.count + 1;

    final newClock =
        HLC(timestamp: newPhysicalTime, count: newCounter, node: deviceId);

    return newClock;
  }

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

  String pack(HLC clock) {
    final buffer = StringBuffer();
    buffer.write(clock.timestamp.toString().padLeft(15, '0'));
    buffer.write(delimiter);
    buffer.write(clock.count.toRadixString(36).padLeft(5, '0'));
    buffer.write(delimiter);
    buffer.write(clock.node);
    return buffer.toString();
  }

  HLC unpack(String packed) {
    final parts = packed.split(delimiter);

    return HLC(
      timestamp: int.parse(parts[0]),
      count: int.parse(parts[1], radix: 36),
      node: parts.sublist(2).join(delimiter),
    );
  }
}
