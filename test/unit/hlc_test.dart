import 'package:test/test.dart';
import 'package:talon/talon.dart';
import 'package:talon/src/hybrid_logical_clock/hlc.state.dart';

void main() {
  group('HLC', () {
    test('now() creates HLC with current timestamp', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final hlc = HLC.now('node-1');
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(hlc.timestamp, greaterThanOrEqualTo(before));
      expect(hlc.timestamp, lessThanOrEqualTo(after));
      expect(hlc.count, equals(0));
      expect(hlc.node, equals('node-1'));
    });

    test('compareTo orders by timestamp first', () {
      final earlier = HLC(timestamp: 1000, count: 5, node: 'z');
      final later = HLC(timestamp: 2000, count: 0, node: 'a');

      expect(earlier.compareTo(later), lessThan(0));
      expect(later.compareTo(earlier), greaterThan(0));
    });

    test('compareTo orders by count when timestamps equal', () {
      final lower = HLC(timestamp: 1000, count: 1, node: 'z');
      final higher = HLC(timestamp: 1000, count: 5, node: 'a');

      expect(lower.compareTo(higher), lessThan(0));
      expect(higher.compareTo(lower), greaterThan(0));
    });

    test('compareTo orders by node when timestamp and count equal', () {
      final nodeA = HLC(timestamp: 1000, count: 1, node: 'aaa');
      final nodeZ = HLC(timestamp: 1000, count: 1, node: 'zzz');

      expect(nodeA.compareTo(nodeZ), lessThan(0));
      expect(nodeZ.compareTo(nodeA), greaterThan(0));
    });

    test('compareTo returns 0 for equal HLCs', () {
      final hlc1 = HLC(timestamp: 1000, count: 1, node: 'node');
      final hlc2 = HLC(timestamp: 1000, count: 1, node: 'node');

      expect(hlc1.compareTo(hlc2), equals(0));
    });

    group('tryParse', () {
      test('successfully parses valid HLC string', () {
        final hlc = HLC(timestamp: 1234567890123, count: 42, node: 'my-node');
        final packed = hlc.toString();
        final parsed = HLC.tryParse(packed);

        expect(parsed, isNotNull);
        expect(parsed!.timestamp, equals(hlc.timestamp));
        expect(parsed.count, equals(hlc.count));
        expect(parsed.node, equals(hlc.node));
      });

      test('returns null for empty string', () {
        expect(HLC.tryParse(''), isNull);
      });

      test('returns null for invalid format', () {
        expect(HLC.tryParse('invalid'), isNull);
        expect(HLC.tryParse('123:456'), isNull);
        expect(HLC.tryParse('not:a:number:node'), isNull);
      });

      test('handles node with colons', () {
        final hlc =
            HLC(timestamp: 1234567890123, count: 0, node: 'node:with:colons');
        final packed = hlc.toString();
        final parsed = HLC.tryParse(packed);

        expect(parsed, isNotNull);
        expect(parsed!.node, equals('node:with:colons'));
      });
    });

    group('compareTimestamps', () {
      test('correctly compares valid timestamps', () {
        final hlc1 = HLC(timestamp: 1000, count: 0, node: 'a');
        final hlc2 = HLC(timestamp: 2000, count: 0, node: 'b');

        expect(
          HLC.compareTimestamps(hlc1.toString(), hlc2.toString()),
          lessThan(0),
        );
        expect(
          HLC.compareTimestamps(hlc2.toString(), hlc1.toString()),
          greaterThan(0),
        );
        expect(
          HLC.compareTimestamps(hlc1.toString(), hlc1.toString()),
          equals(0),
        );
      });

      test('returns 0 for two invalid strings', () {
        expect(HLC.compareTimestamps('invalid', 'also-invalid'), equals(0));
      });

      test('invalid string is less than valid string', () {
        final valid = HLC(timestamp: 1000, count: 0, node: 'a').toString();
        expect(HLC.compareTimestamps('invalid', valid), lessThan(0));
        expect(HLC.compareTimestamps(valid, 'invalid'), greaterThan(0));
      });
    });

    test('equality works correctly', () {
      final hlc1 = HLC(timestamp: 1000, count: 1, node: 'node');
      final hlc2 = HLC(timestamp: 1000, count: 1, node: 'node');
      final hlc3 = HLC(timestamp: 1000, count: 2, node: 'node');

      expect(hlc1, equals(hlc2));
      expect(hlc1, isNot(equals(hlc3)));
    });

    test('hashCode is consistent with equality', () {
      final hlc1 = HLC(timestamp: 1000, count: 1, node: 'node');
      final hlc2 = HLC(timestamp: 1000, count: 1, node: 'node');

      expect(hlc1.hashCode, equals(hlc2.hashCode));
    });

    test('toString and tryParse roundtrip', () {
      final original = HLC(timestamp: 1234567890123, count: 42, node: 'test');
      final packed = original.toString();
      final restored = HLC.tryParse(packed);

      expect(restored, isNotNull);
      expect(restored!.timestamp, equals(original.timestamp));
      expect(restored.count, equals(original.count));
      expect(restored.node, equals(original.node));
    });

    group('edge cases', () {
      test('handles zero timestamp', () {
        final hlc = HLC(timestamp: 0, count: 0, node: 'node');
        final packed = hlc.toString();
        final restored = HLC.tryParse(packed);

        expect(restored, isNotNull);
        expect(restored!.timestamp, equals(0));
      });

      test('handles very large timestamp', () {
        // Max safe integer in JavaScript (relevant for cross-platform)
        final hlc = HLC(timestamp: 9007199254740991, count: 0, node: 'node');
        final packed = hlc.toString();
        final restored = HLC.tryParse(packed);

        expect(restored, isNotNull);
        expect(restored!.timestamp, equals(9007199254740991));
      });

      test('handles very large count', () {
        final hlc = HLC(timestamp: 1000, count: 99999, node: 'node');
        final packed = hlc.toString();
        final restored = HLC.tryParse(packed);

        expect(restored, isNotNull);
        expect(restored!.count, equals(99999));
      });

      test('handles empty node', () {
        final hlc = HLC(timestamp: 1000, count: 0, node: '');
        final packed = hlc.toString();
        final restored = HLC.tryParse(packed);

        expect(restored, isNotNull);
        expect(restored!.node, equals(''));
      });

      test('handles node with special characters', () {
        final hlc = HLC(timestamp: 1000, count: 0, node: 'node-123_abc');
        final packed = hlc.toString();
        final restored = HLC.tryParse(packed);

        expect(restored, isNotNull);
        expect(restored!.node, equals('node-123_abc'));
      });

      test('handles UUID as node', () {
        final uuid = '550e8400-e29b-41d4-a716-446655440000';
        final hlc = HLC(timestamp: 1000, count: 0, node: uuid);
        final packed = hlc.toString();
        final restored = HLC.tryParse(packed);

        expect(restored, isNotNull);
        expect(restored!.node, equals(uuid));
      });
    });

    group('compareTimestamps edge cases', () {
      test('handles comparison of empty strings', () {
        expect(HLC.compareTimestamps('', ''), equals(0));
      });

      test('empty string is less than valid timestamp', () {
        final valid = HLC(timestamp: 1000, count: 0, node: 'a').toString();
        expect(HLC.compareTimestamps('', valid), lessThan(0));
        expect(HLC.compareTimestamps(valid, ''), greaterThan(0));
      });

      test('compares by count when timestamps equal', () {
        final low = HLC(timestamp: 1000, count: 0, node: 'a').toString();
        final high = HLC(timestamp: 1000, count: 10, node: 'a').toString();

        expect(HLC.compareTimestamps(low, high), lessThan(0));
        expect(HLC.compareTimestamps(high, low), greaterThan(0));
      });

      test('compares by node when timestamp and count equal', () {
        final nodeA = HLC(timestamp: 1000, count: 0, node: 'aaa').toString();
        final nodeZ = HLC(timestamp: 1000, count: 0, node: 'zzz').toString();

        expect(HLC.compareTimestamps(nodeA, nodeZ), lessThan(0));
        expect(HLC.compareTimestamps(nodeZ, nodeA), greaterThan(0));
      });

      test('returns 0 for identical timestamps', () {
        final ts = HLC(timestamp: 1000, count: 5, node: 'test').toString();
        expect(HLC.compareTimestamps(ts, ts), equals(0));
      });
    });
  });

  group('HLCState', () {
    test('send() returns incrementing HLCs', () {
      final state = HLCState('node-1');

      final first = state.send();
      final second = state.send();

      // Second should be greater than first
      expect(second.compareTo(first), greaterThan(0));
    });

    test('send() increments count for rapid successive calls', () {
      final state = HLCState('node-1');

      final first = state.send();
      final second = state.send();

      // If called in same millisecond, count should increment
      if (first.timestamp == second.timestamp) {
        expect(second.count, equals(first.count + 1));
      }
    });

    test('receive() updates state from remote HLC', () {
      final state = HLCState('node-1');

      // Simulate receiving a message with a future timestamp
      final futureHlc = HLC(
        timestamp: DateTime.now().millisecondsSinceEpoch + 10000,
        count: 5,
        node: 'node-2',
      );

      state.receive(futureHlc);
      final next = state.send();

      // Our next HLC should be greater than what we received
      expect(next.compareTo(futureHlc), greaterThan(0));
    });

    test('receiveFromString returns false for invalid string', () {
      final state = HLCState('node-1');
      expect(state.receiveFromString('invalid'), isFalse);
    });

    test('receiveFromString returns true for valid string', () {
      final state = HLCState('node-1');
      final hlc = HLC(timestamp: 1000, count: 0, node: 'node-2');
      expect(state.receiveFromString(hlc.toString()), isTrue);
    });

    test('current returns the current HLC', () {
      final state = HLCState('node-1');
      final current = state.current;

      expect(current.node, equals('node-1'));
      expect(current.count, equals(0));
    });
  });
}
