import 'package:test/test.dart';
import 'package:talon/src/hybrid_logical_clock/hlc.dart';
import 'package:talon/src/hybrid_logical_clock/hlc.utils.dart';

void main() {
  group('HLCUtils', () {
    late HLCUtils utils;

    setUp(() {
      utils = HLCUtils('test-device');
    });

    group('pack', () {
      test('packs HLC into string format', () {
        final hlc = HLC(timestamp: 1234567890123, count: 42, node: 'test-device');
        final packed = utils.pack(hlc);

        expect(packed, contains(':'));
        expect(packed, startsWith('001234567890123')); // 15-digit padded timestamp
      });

      test('packs zero timestamp correctly', () {
        final hlc = HLC(timestamp: 0, count: 0, node: 'test-device');
        final packed = utils.pack(hlc);

        expect(packed, startsWith('000000000000000:'));
      });

      test('packs count as base-36', () {
        final hlc = HLC(timestamp: 1000, count: 35, node: 'test-device');
        final packed = utils.pack(hlc);

        // 35 in base-36 is 'z', padded to 5 chars
        expect(packed, contains(':0000z:'));
      });

      test('packs count larger than 36 correctly', () {
        final hlc = HLC(timestamp: 1000, count: 36, node: 'test-device');
        final packed = utils.pack(hlc);

        // 36 in base-36 is '10'
        expect(packed, contains(':00010:'));
      });

      test('preserves node in packed string', () {
        final hlc = HLC(timestamp: 1000, count: 0, node: 'my-device-123');
        final packed = utils.pack(hlc);

        expect(packed, endsWith(':my-device-123'));
      });
    });

    group('unpack', () {
      test('unpacks valid packed string', () {
        final original = HLC(timestamp: 1234567890123, count: 42, node: 'test-device');
        final packed = utils.pack(original);
        final unpacked = utils.unpack(packed);

        expect(unpacked.timestamp, equals(original.timestamp));
        expect(unpacked.count, equals(original.count));
        expect(unpacked.node, equals(original.node));
      });

      test('unpacks string with zero count', () {
        final original = HLC(timestamp: 9999999999999, count: 0, node: 'node');
        final packed = utils.pack(original);
        final unpacked = utils.unpack(packed);

        expect(unpacked.count, equals(0));
      });

      test('handles node with colons', () {
        final original = HLC(timestamp: 1000, count: 0, node: 'node:with:colons');
        final packed = utils.pack(original);
        final unpacked = utils.unpack(packed);

        expect(unpacked.node, equals('node:with:colons'));
      });

      test('roundtrip preserves all fields', () {
        final testCases = [
          HLC(timestamp: 0, count: 0, node: ''),
          HLC(timestamp: 1, count: 1, node: 'a'),
          HLC(timestamp: 9007199254740991, count: 999999, node: 'very-long-node-id-here'),
          HLC(timestamp: 1234567890123, count: 42, node: 'uuid:550e8400-e29b-41d4'),
        ];

        for (final original in testCases) {
          final packed = utils.pack(original);
          final unpacked = utils.unpack(packed);

          expect(unpacked.timestamp, equals(original.timestamp), reason: 'timestamp mismatch');
          expect(unpacked.count, equals(original.count), reason: 'count mismatch');
          expect(unpacked.node, equals(original.node), reason: 'node mismatch');
        }
      });
    });

    group('send', () {
      test('advances clock timestamp', () {
        final initial = HLC(timestamp: 1000, count: 0, node: 'test-device');
        final beforeSend = DateTime.now().millisecondsSinceEpoch;
        final sent = utils.send(initial);
        final afterSend = DateTime.now().millisecondsSinceEpoch;

        // New timestamp should be at least current time
        expect(sent.timestamp, greaterThanOrEqualTo(beforeSend));
        expect(sent.timestamp, lessThanOrEqualTo(afterSend));
      });

      test('resets count when physical time advances', () {
        // Use a timestamp in the past
        final past = HLC(
          timestamp: DateTime.now().millisecondsSinceEpoch - 10000,
          count: 99,
          node: 'test-device',
        );
        final sent = utils.send(past);

        // Count should be reset to 0 since physical time advanced
        expect(sent.count, equals(0));
      });

      test('increments count when physical time has not advanced', () {
        // Use a timestamp in the future
        final future = HLC(
          timestamp: DateTime.now().millisecondsSinceEpoch + 100000,
          count: 5,
          node: 'test-device',
        );
        final sent = utils.send(future);

        // Count should increment since physical time hasn't caught up
        expect(sent.count, equals(6));
        expect(sent.timestamp, equals(future.timestamp));
      });

      test('uses correct node from HLCUtils', () {
        final hlc = HLC(timestamp: 1000, count: 0, node: 'old-node');
        final sent = utils.send(hlc);

        // Node should be from the HLCUtils, not the input HLC
        expect(sent.node, equals('test-device'));
      });

      test('produces monotonically increasing HLCs', () {
        var current = HLC.now('test-device');
        for (int i = 0; i < 100; i++) {
          final next = utils.send(current);
          expect(next.compareTo(current), greaterThan(0));
          current = next;
        }
      });
    });

    group('receive', () {
      test('advances to remote timestamp when remote is ahead', () {
        final local = HLC(timestamp: 1000, count: 5, node: 'test-device');
        final remote = HLC(timestamp: 5000, count: 10, node: 'other-device');

        final result = utils.receive(local, remote);

        expect(result.timestamp, equals(5000));
        expect(result.count, equals(11)); // remote.count + 1
        expect(result.node, equals('test-device'));
      });

      test('uses local timestamp when local is ahead', () {
        final local = HLC(timestamp: 5000, count: 5, node: 'test-device');
        final remote = HLC(timestamp: 1000, count: 10, node: 'other-device');

        final result = utils.receive(local, remote);

        expect(result.timestamp, equals(5000));
        expect(result.count, equals(6)); // local.count + 1
        expect(result.node, equals('test-device'));
      });

      test('uses max count when timestamps are equal', () {
        final local = HLC(timestamp: 3000, count: 5, node: 'test-device');
        final remote = HLC(timestamp: 3000, count: 10, node: 'other-device');

        final result = utils.receive(local, remote);

        expect(result.timestamp, equals(3000));
        expect(result.count, equals(11)); // max(5, 10) + 1
        expect(result.node, equals('test-device'));
      });

      test('uses physical time when it is ahead of both', () {
        final now = DateTime.now().millisecondsSinceEpoch;
        final local = HLC(timestamp: now - 10000, count: 5, node: 'test-device');
        final remote = HLC(timestamp: now - 5000, count: 10, node: 'other-device');

        final result = utils.receive(local, remote);

        // Physical time should be used, count reset to 0
        expect(result.timestamp, greaterThanOrEqualTo(now));
        expect(result.count, equals(0));
        expect(result.node, equals('test-device'));
      });

      test('throws TimeDriftException when drift exceeds maximum', () {
        final local = HLC.now('test-device');
        final farFuture = HLC(
          timestamp: DateTime.now().millisecondsSinceEpoch + 100000, // 100 seconds in future
          count: 0,
          node: 'other-device',
        );

        expect(
          () => utils.receive(
            local,
            farFuture,
            maximumDrift: Duration(seconds: 10),
          ),
          throwsA(isA<TimeDriftException>()),
        );
      });

      test('does not throw when drift is within maximum', () {
        final local = HLC.now('test-device');
        final slightlyFuture = HLC(
          timestamp: DateTime.now().millisecondsSinceEpoch + 1000, // 1 second in future
          count: 0,
          node: 'other-device',
        );

        expect(
          () => utils.receive(
            local,
            slightlyFuture,
            maximumDrift: Duration(seconds: 10),
          ),
          returnsNormally,
        );
      });

      test('does not check drift when maximumDrift is null', () {
        final local = HLC.now('test-device');
        final farFuture = HLC(
          timestamp: DateTime.now().millisecondsSinceEpoch + 1000000,
          count: 0,
          node: 'other-device',
        );

        // Should not throw
        expect(
          () => utils.receive(local, farFuture),
          returnsNormally,
        );
      });

      test('respects custom now parameter', () {
        final customNow = 5000;
        final local = HLC(timestamp: 1000, count: 0, node: 'test-device');
        final remote = HLC(timestamp: 2000, count: 0, node: 'other-device');

        final result = utils.receive(local, remote, now: customNow);

        // Custom now (5000) is greater than both, so should use it
        expect(result.timestamp, equals(5000));
        expect(result.count, equals(0));
      });
    });
  });

  group('TimeDriftException', () {
    test('stores drift and maximumDrift', () {
      final exception = TimeDriftException(
        drift: Duration(seconds: 30),
        maximumDrift: Duration(seconds: 10),
      );

      expect(exception.drift, equals(Duration(seconds: 30)));
      expect(exception.maximumDrift, equals(Duration(seconds: 10)));
    });

    test('provides error message', () {
      final exception = TimeDriftException(
        drift: Duration(seconds: 30),
        maximumDrift: Duration(seconds: 10),
      );

      expect(exception.message, contains('TimeDriftException'));
      expect(exception.message, contains('drift'));
    });
  });
}
