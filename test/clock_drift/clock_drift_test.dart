import 'package:test/test.dart';
import 'package:talon/talon.dart';

import '../mocks/mock_offline_database.dart';
import '../mocks/mock_server_database.dart';

// Import internal HLC classes for direct testing
import 'package:talon/src/hybrid_logical_clock/hlc.dart';
import 'package:talon/src/hybrid_logical_clock/hlc.state.dart';
import 'package:talon/src/hybrid_logical_clock/hlc.utils.dart';

void main() {
  group('HLC Clock Drift Scenarios', () {
    test('HLC handles past timestamps correctly', () {
      final hlcUtils = HLCUtils('client-1');
      final now = DateTime.now().millisecondsSinceEpoch;

      // Create a clock with past timestamp
      final pastClock = HLC(
        timestamp: now - 10000, // 10 seconds in the past
        count: 0,
        node: 'client-1',
      );

      // Send should advance to current time
      final newClock = hlcUtils.send(pastClock);

      expect(newClock.timestamp, greaterThanOrEqualTo(now - 100));
      expect(newClock.count, equals(0)); // Count resets when time advances
    });

    test('HLC handles future timestamps correctly', () {
      final hlcUtils = HLCUtils('client-1');
      final now = DateTime.now().millisecondsSinceEpoch;

      // Create a clock with future timestamp
      final futureClock = HLC(
        timestamp: now + 10000, // 10 seconds in the future
        count: 5,
        node: 'client-1',
      );

      // Send should keep the future timestamp and increment counter
      final newClock = hlcUtils.send(futureClock);

      expect(newClock.timestamp, equals(now + 10000));
      expect(newClock.count, equals(6));
    });

    test('receiving future timestamp updates local clock', () {
      final hlcUtils = HLCUtils('client-1');
      final now = DateTime.now().millisecondsSinceEpoch;

      final localClock = HLC(timestamp: now, count: 0, node: 'client-1');
      final remoteClock = HLC(
        timestamp: now + 5000, // 5 seconds in future
        count: 10,
        node: 'client-2',
      );

      final newClock = hlcUtils.receive(localClock, remoteClock);

      // Should advance to remote's timestamp
      expect(newClock.timestamp, equals(now + 5000));
      expect(newClock.count, equals(11)); // remote.count + 1
    });

    test('receiving past timestamp keeps local clock', () {
      final hlcUtils = HLCUtils('client-1');
      final now = DateTime.now().millisecondsSinceEpoch;

      final localClock = HLC(timestamp: now + 5000, count: 5, node: 'client-1');
      final remoteClock = HLC(
        timestamp: now, // Current time (past relative to local)
        count: 10,
        node: 'client-2',
      );

      final newClock = hlcUtils.receive(localClock, remoteClock);

      // Should keep local's future timestamp
      expect(newClock.timestamp, equals(now + 5000));
      expect(newClock.count, equals(6)); // local.count + 1
    });

    test('receiving equal timestamp uses max count', () {
      final hlcUtils = HLCUtils('client-1');
      final now = DateTime.now().millisecondsSinceEpoch;

      final localClock = HLC(timestamp: now, count: 3, node: 'client-1');
      final remoteClock = HLC(timestamp: now, count: 7, node: 'client-2');

      final newClock = hlcUtils.receive(localClock, remoteClock);

      expect(newClock.timestamp, equals(now));
      expect(newClock.count, equals(8)); // max(3, 7) + 1
    });

    test('TimeDriftException thrown for excessive drift', () {
      final hlcUtils = HLCUtils('client-1');
      final now = DateTime.now().millisecondsSinceEpoch;

      final localClock = HLC(timestamp: now, count: 0, node: 'client-1');
      final remoteClock = HLC(
        timestamp: now + 3600000, // 1 hour in future
        count: 0,
        node: 'client-2',
      );

      expect(
        () => hlcUtils.receive(
          localClock,
          remoteClock,
          maximumDrift: const Duration(minutes: 5),
        ),
        throwsA(isA<TimeDriftException>()),
      );
    });

    test('no exception for acceptable drift', () {
      final hlcUtils = HLCUtils('client-1');
      final now = DateTime.now().millisecondsSinceEpoch;

      final localClock = HLC(timestamp: now, count: 0, node: 'client-1');
      final remoteClock = HLC(
        timestamp: now + 60000, // 1 minute in future
        count: 0,
        node: 'client-2',
      );

      // Should not throw
      final result = hlcUtils.receive(
        localClock,
        remoteClock,
        maximumDrift: const Duration(minutes: 5),
      );

      expect(result.timestamp, equals(now + 60000));
    });

    test('TimeDriftException contains correct values', () {
      final hlcUtils = HLCUtils('client-1');
      final now = DateTime.now().millisecondsSinceEpoch;
      final driftMs = 600000; // 10 minutes

      final localClock = HLC(timestamp: now, count: 0, node: 'client-1');
      final remoteClock = HLC(
        timestamp: now + driftMs,
        count: 0,
        node: 'client-2',
      );

      try {
        hlcUtils.receive(
          localClock,
          remoteClock,
          maximumDrift: const Duration(minutes: 5),
          now: now,
        );
        fail('Should have thrown TimeDriftException');
      } on TimeDriftException catch (e) {
        expect(e.maximumDrift, equals(const Duration(minutes: 5)));
        expect(e.drift.inMinutes, greaterThanOrEqualTo(9));
        expect(e.message, contains('TimeDriftException'));
      }
    });
  });

  group('HLCState Clock Drift', () {
    test('HLCState tracks clock across multiple sends', () {
      final state = HLCState('client-1');

      final t1 = state.send();
      final t2 = state.send();
      final t3 = state.send();

      // Each send should be strictly greater than previous
      expect(t2.compareTo(t1), greaterThan(0));
      expect(t3.compareTo(t2), greaterThan(0));
    });

    test('HLCState receive updates internal clock', () {
      final state = HLCState('client-1');
      final now = DateTime.now().millisecondsSinceEpoch;

      // Receive a future timestamp
      final remoteClock = HLC(
        timestamp: now + 10000,
        count: 100,
        node: 'client-2',
      );

      state.receive(remoteClock);

      // Next send should be after the received timestamp
      final nextSend = state.send();

      expect(nextSend.compareTo(remoteClock), greaterThan(0));
    });

    test('HLCState receiveFromString handles invalid strings', () {
      final state = HLCState('client-1');

      expect(state.receiveFromString('invalid'), isFalse);
      expect(state.receiveFromString(''), isFalse);
      expect(state.receiveFromString('12345'), isFalse);
    });

    test('HLCState receiveFromString handles valid strings', () {
      final state = HLCState('client-1');
      final now = DateTime.now().millisecondsSinceEpoch;

      final remoteClock = HLC(
        timestamp: now + 5000,
        count: 50,
        node: 'client-2',
      );

      expect(state.receiveFromString(remoteClock.toString()), isTrue);

      // Next send should be after received
      final nextSend = state.send();
      expect(nextSend.compareTo(remoteClock), greaterThan(0));
    });
  });

  group('Talon with Clock Drift', () {
    late MockOfflineDatabase offlineDb;
    late MockServerDatabase serverDb;
    int messageIdCounter = 0;

    setUp(() {
      offlineDb = MockOfflineDatabase();
      serverDb = MockServerDatabase();
      messageIdCounter = 0;
    });

    tearDown(() {
      serverDb.dispose();
    });

    test('messages from future-drifted client are handled correctly', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      // Save a local change
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'local-value',
      );

      final localMsg = offlineDb.messages.first;

      // Create a message with future timestamp
      final now = DateTime.now().millisecondsSinceEpoch;
      final futureHlc = HLC(
        timestamp: now + 60000, // 1 minute in future
        count: 0,
        node: 'client-2',
      );

      final futureMessage = Message(
        id: 'future-msg',
        table: 'test',
        row: 'row-1',
        column: 'value',
        dataType: 'string',
        value: 'future-value',
        localTimestamp: futureHlc.toString(),
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      );

      // Simulate receiving from server
      talon.syncIsEnabled = true;
      serverDb.simulateServerMessage(futureMessage);

      await Future.delayed(const Duration(milliseconds: 100));

      // Future message should win in last-write-wins
      final messages = offlineDb.messages
          .where((m) => m.table == 'test' && m.row == 'row-1')
          .toList();

      // Both messages should be stored
      expect(messages.length, greaterThanOrEqualTo(2));

      // The one with future timestamp should be "later"
      final parsed1 = HLC.tryParse(localMsg.localTimestamp);
      final parsed2 = HLC.tryParse(futureMessage.localTimestamp);
      expect(parsed2!.compareTo(parsed1!), greaterThan(0));

      talon.dispose();
    });

    test('local clock advances after receiving future timestamp', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      // Save initial local change
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'first',
      );

      final firstLocalTs = offlineDb.messages.first.localTimestamp;

      // Receive message with future timestamp
      final now = DateTime.now().millisecondsSinceEpoch;
      final futureHlc = HLC(
        timestamp: now + 30000, // 30 seconds in future
        count: 0,
        node: 'client-2',
      );

      talon.syncIsEnabled = true;
      serverDb.simulateServerMessage(Message(
        id: 'future-msg',
        table: 'test',
        row: 'row-2',
        column: 'value',
        dataType: 'string',
        value: 'from-future',
        localTimestamp: futureHlc.toString(),
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      // Save another local change - should have advanced timestamp
      await talon.saveChange(
        table: 'test',
        row: 'row-3',
        column: 'value',
        value: 'after-future',
      );

      final afterFutureMsg =
          offlineDb.messages.where((m) => m.row == 'row-3').first;

      // The new local timestamp should be after the future one
      final afterTs = HLC.tryParse(afterFutureMsg.localTimestamp)!;
      expect(afterTs.compareTo(futureHlc), greaterThan(0));

      talon.dispose();
    });

    test('rapid saves maintain causal ordering', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      // Rapidly save many changes
      for (int i = 0; i < 100; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      // All timestamps should be strictly increasing
      final timestamps = offlineDb.messages
          .map((m) => HLC.tryParse(m.localTimestamp)!)
          .toList();

      for (int i = 1; i < timestamps.length; i++) {
        expect(
          timestamps[i].compareTo(timestamps[i - 1]),
          greaterThan(0),
          reason: 'Timestamp $i should be greater than ${i - 1}',
        );
      }

      talon.dispose();
    });

    test('concurrent clients maintain global ordering', () async {
      final offlineDb1 = MockOfflineDatabase();
      final offlineDb2 = MockOfflineDatabase();

      final talon1 = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb1,
        createNewIdFunction: () => 'msg-1-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      final talon2 = Talon(
        userId: 'user-1',
        clientId: 'client-2',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb2,
        createNewIdFunction: () => 'msg-2-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      // Both clients save changes
      await talon1.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'from-client-1',
      );

      await talon2.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'from-client-2',
      );

      final msg1 = offlineDb1.messages.first;
      final msg2 = offlineDb2.messages.first;

      final hlc1 = HLC.tryParse(msg1.localTimestamp)!;
      final hlc2 = HLC.tryParse(msg2.localTimestamp)!;

      // Both should be valid and comparable
      expect(hlc1.node, equals('client-1'));
      expect(hlc2.node, equals('client-2'));

      // One should be definitively before or after the other
      final comparison = hlc1.compareTo(hlc2);
      expect(comparison, isNot(equals(0)));

      talon1.dispose();
      talon2.dispose();
    });
  });

  group('HLC Comparison Edge Cases', () {
    test('same timestamp and count, different nodes', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      final hlc1 = HLC(timestamp: now, count: 0, node: 'aaa');
      final hlc2 = HLC(timestamp: now, count: 0, node: 'bbb');

      expect(hlc1.compareTo(hlc2), lessThan(0));
      expect(hlc2.compareTo(hlc1), greaterThan(0));
    });

    test('compareTimestamps with invalid strings', () {
      expect(HLC.compareTimestamps('invalid', 'invalid'), equals(0));
      expect(HLC.compareTimestamps('invalid', 'valid:00000:node'), lessThan(0));
      expect(HLC.compareTimestamps('valid:00000:node', 'invalid'), greaterThan(0));
    });

    test('tryParse with malformed strings', () {
      expect(HLC.tryParse(''), isNull);
      expect(HLC.tryParse('no-delimiters'), isNull);
      expect(HLC.tryParse('only:two'), isNull);
      expect(HLC.tryParse('abc:def:node'), isNull); // non-numeric
    });

    test('tryParse with node containing delimiter', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final hlc = HLC(timestamp: now, count: 0, node: 'node:with:colons');

      final packed = hlc.toString();
      final parsed = HLC.tryParse(packed);

      expect(parsed, isNotNull);
      expect(parsed!.node, equals('node:with:colons'));
    });

    test('HLC equality', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      final hlc1 = HLC(timestamp: now, count: 5, node: 'client');
      final hlc2 = HLC(timestamp: now, count: 5, node: 'client');
      final hlc3 = HLC(timestamp: now, count: 6, node: 'client');

      expect(hlc1 == hlc2, isTrue);
      expect(hlc1 == hlc3, isFalse);
      expect(hlc1.hashCode, equals(hlc2.hashCode));
    });

    test('HLC now uses current time', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final hlc = HLC.now('test-node');
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(hlc.timestamp, greaterThanOrEqualTo(before));
      expect(hlc.timestamp, lessThanOrEqualTo(after));
      expect(hlc.count, equals(0));
      expect(hlc.node, equals('test-node'));
    });
  });

  group('Pack/Unpack', () {
    test('pack produces padded output', () {
      final hlcUtils = HLCUtils('client');
      final hlc = HLC(timestamp: 123, count: 1, node: 'client');

      final packed = hlcUtils.pack(hlc);

      expect(packed, contains('000000000000123'));
      expect(packed, contains('00001'));
    });

    test('unpack reverses pack', () {
      final hlcUtils = HLCUtils('client');
      final original = HLC(
        timestamp: 1234567890123,
        count: 42,
        node: 'client',
      );

      final packed = hlcUtils.pack(original);
      final unpacked = hlcUtils.unpack(packed);

      expect(unpacked.timestamp, equals(original.timestamp));
      expect(unpacked.count, equals(original.count));
      expect(unpacked.node, equals(original.node));
    });

    test('pack/unpack with large count', () {
      final hlcUtils = HLCUtils('client');
      final hlc = HLC(
        timestamp: 1234567890123,
        count: 1000000, // Large count
        node: 'client',
      );

      final packed = hlcUtils.pack(hlc);
      final unpacked = hlcUtils.unpack(packed);

      expect(unpacked.count, equals(hlc.count));
    });

    test('HLC toString uses pack', () {
      final hlc = HLC(
        timestamp: 1234567890123,
        count: 10,
        node: 'test-client',
      );

      final str = hlc.toString();

      expect(str, contains('1234567890123'));
      expect(str, contains('test-client'));
    });
  });
}
