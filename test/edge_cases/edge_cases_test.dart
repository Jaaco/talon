import 'package:test/test.dart';
import 'package:talon/talon.dart';

import '../mocks/mock_offline_database.dart';
import '../mocks/mock_server_database.dart';

void main() {
  late MockOfflineDatabase offlineDb;
  late MockServerDatabase serverDb;
  late Talon talon;
  int messageIdCounter = 0;

  setUp(() {
    offlineDb = MockOfflineDatabase();
    serverDb = MockServerDatabase();
    messageIdCounter = 0;
    talon = Talon(
      userId: 'user-1',
      clientId: 'client-1',
      serverDatabase: serverDb,
      offlineDatabase: offlineDb,
      createNewIdFunction: () => 'msg-${messageIdCounter++}',
      config: TalonConfig.immediate,
    );
  });

  tearDown(() {
    talon.dispose();
    serverDb.dispose();
  });

  group('Edge Cases - Empty Values', () {
    test('handles empty string value', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: '',
      );

      expect(offlineDb.messages.first.value, equals(''));
      expect(offlineDb.getValue('test', 'row-1', 'value'), equals(''));
    });

    test('handles empty table name', () async {
      await talon.saveChange(
        table: '',
        row: 'row-1',
        column: 'value',
        value: 'test',
      );

      expect(offlineDb.messages.first.table, equals(''));
    });

    test('handles empty row identifier', () async {
      await talon.saveChange(
        table: 'test',
        row: '',
        column: 'value',
        value: 'test',
      );

      expect(offlineDb.messages.first.row, equals(''));
    });

    test('handles empty column name', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: '',
        value: 'test',
      );

      expect(offlineDb.messages.first.column, equals(''));
    });

    test('handles empty sync gracefully', () async {
      talon.syncIsEnabled = true;

      // No messages to sync
      await talon.syncToServer();
      await talon.syncFromServer();

      expect(offlineDb.messageCount, equals(0));
      expect(serverDb.messageCount, equals(0));
    });

    test('handles saveChanges with empty list', () async {
      await talon.saveChanges([]);

      expect(offlineDb.messageCount, equals(0));
    });
  });

  group('Edge Cases - Very Long Values', () {
    test('handles 1KB string value', () async {
      final longValue = 'A' * 1024;
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: longValue,
      );

      expect(offlineDb.messages.first.value, equals(longValue));
    });

    test('handles 100KB string value', () async {
      final longValue = 'B' * (100 * 1024);
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: longValue,
      );

      expect(offlineDb.messages.first.value.length, equals(100 * 1024));
    });

    test('handles 1MB string value', () async {
      final longValue = 'C' * (1024 * 1024);
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: longValue,
      );

      expect(offlineDb.messages.first.value.length, equals(1024 * 1024));
    });

    test('handles very long table name', () async {
      final longTableName = 'table_' + ('a' * 1000);
      await talon.saveChange(
        table: longTableName,
        row: 'row-1',
        column: 'value',
        value: 'test',
      );

      expect(offlineDb.messages.first.table, equals(longTableName));
    });

    test('handles very long row identifier', () async {
      final longRowId = 'row_' + ('b' * 1000);
      await talon.saveChange(
        table: 'test',
        row: longRowId,
        column: 'value',
        value: 'test',
      );

      expect(offlineDb.messages.first.row, equals(longRowId));
    });
  });

  group('Edge Cases - Special Characters', () {
    test('handles SQL injection attempt in value', () async {
      final sqlInjection = "'; DROP TABLE users; --";
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: sqlInjection,
      );

      expect(offlineDb.messages.first.value, equals(sqlInjection));
    });

    test('handles SQL injection in table name', () async {
      final sqlInjection = "users; DROP TABLE messages";
      await talon.saveChange(
        table: sqlInjection,
        row: 'row-1',
        column: 'value',
        value: 'test',
      );

      expect(offlineDb.messages.first.table, equals(sqlInjection));
    });

    test('handles unicode characters', () async {
      final unicode = '你好世界 مرحبا العالم Привет мир';
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: unicode,
      );

      expect(offlineDb.messages.first.value, equals(unicode));
    });

    test('handles emojis', () async {
      final emojis = '😀🎉🚀💻🔥✨🌈🎨🎯🏆';
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: emojis,
      );

      expect(offlineDb.messages.first.value, equals(emojis));
    });

    test('handles mixed emoji and text', () async {
      final mixed = 'Hello 👋 World 🌍!';
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: mixed,
      );

      expect(offlineDb.messages.first.value, equals(mixed));
    });

    test('handles newlines and tabs', () async {
      final whitespace = 'Line 1\nLine 2\tTabbed';
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: whitespace,
      );

      expect(offlineDb.messages.first.value, equals(whitespace));
    });

    test('handles quotes in value', () async {
      final quotes = 'He said "Hello" and \'Goodbye\'';
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: quotes,
      );

      expect(offlineDb.messages.first.value, equals(quotes));
    });

    test('handles backslashes', () async {
      final backslashes = 'C:\\Users\\Name\\Documents';
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: backslashes,
      );

      expect(offlineDb.messages.first.value, equals(backslashes));
    });

    test('handles null character in string', () async {
      final nullChar = 'Before\x00After';
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: nullChar,
      );

      expect(offlineDb.messages.first.value, equals(nullChar));
    });
  });

  group('Edge Cases - Rapid Operations', () {
    test('handles rapid successive saves to same cell', () async {
      for (int i = 0; i < 100; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-1',
          column: 'counter',
          value: i,
        );
      }

      // All messages should be stored
      expect(offlineDb.messageCount, equals(100));

      // Final value should be the last one
      expect(offlineDb.getValue('test', 'row-1', 'counter'), equals('99'));
    });

    test('handles rapid saves to different cells', () async {
      for (int i = 0; i < 100; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'Value $i',
        );
      }

      expect(offlineDb.messageCount, equals(100));

      // Check a few values
      expect(offlineDb.getValue('test', 'row-0', 'value'), equals('Value 0'));
      expect(offlineDb.getValue('test', 'row-50', 'value'), equals('Value 50'));
      expect(offlineDb.getValue('test', 'row-99', 'value'), equals('Value 99'));
    });

    test('handles rapid saves to different columns', () async {
      for (int i = 0; i < 50; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-1',
          column: 'col_$i',
          value: 'Value $i',
        );
      }

      expect(offlineDb.messageCount, equals(50));
    });
  });

  group('Edge Cases - Duplicate and Ordering', () {
    test('handles duplicate message IDs gracefully', () async {
      // Create a message directly
      final msg1 = Message(
        id: 'duplicate-id',
        table: 'test',
        row: 'row-1',
        column: 'value',
        dataType: 'string',
        value: 'First',
        localTimestamp: HLC.now('client-1').toString(),
        userId: 'user-1',
        clientId: 'client-1',
        hasBeenApplied: false,
        hasBeenSynced: false,
      );

      await offlineDb.applyMessageToLocalMessageTable(msg1);
      await offlineDb.applyMessageToLocalDataTable(msg1);

      // Try to add another message with same ID
      final msg2 = msg1.copyWith(value: 'Second');
      await offlineDb.applyMessageToLocalMessageTable(msg2);

      // Should only have one message (duplicate prevention)
      expect(offlineDb.messageCount, equals(1));
    });

    test('handles out-of-order message delivery', () async {
      talon.syncIsEnabled = true;

      // Create messages with timestamps out of order
      final earlier = HLC(timestamp: 1000, count: 0, node: 'client-2').toString();
      final later = HLC(timestamp: 2000, count: 0, node: 'client-2').toString();

      // Deliver later timestamp first
      serverDb.simulateServerMessage(Message(
        id: 'msg-later',
        table: 'test',
        row: 'row-1',
        column: 'value',
        dataType: 'string',
        value: 'Later value',
        localTimestamp: later,
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await Future.delayed(Duration(milliseconds: 50));

      // Then deliver earlier timestamp
      serverDb.simulateServerMessage(Message(
        id: 'msg-earlier',
        table: 'test',
        row: 'row-1',
        column: 'value',
        dataType: 'string',
        value: 'Earlier value',
        localTimestamp: earlier,
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await Future.delayed(Duration(milliseconds: 50));

      // The later value should win (conflict resolution)
      expect(offlineDb.getValue('test', 'row-1', 'value'), equals('Later value'));
    });

    test('handles messages with null serverTimestamp', () async {
      final msg = Message(
        id: 'no-server-ts',
        table: 'test',
        row: 'row-1',
        column: 'value',
        dataType: 'string',
        value: 'Unsynced',
        localTimestamp: HLC.now('client-1').toString(),
        serverTimestamp: null,
        userId: 'user-1',
        clientId: 'client-1',
        hasBeenApplied: false,
        hasBeenSynced: false,
      );

      await offlineDb.applyMessageToLocalMessageTable(msg);
      await offlineDb.applyMessageToLocalDataTable(msg);

      expect(offlineDb.messageCount, equals(1));
      expect(offlineDb.unsyncedCount, equals(1));
    });
  });

  group('Edge Cases - HLC Timestamps', () {
    test('handles malformed HLC timestamp strings', () async {
      final msg = Message(
        id: 'malformed-ts',
        table: 'test',
        row: 'row-1',
        column: 'value',
        dataType: 'string',
        value: 'Test',
        localTimestamp: 'not-a-valid-hlc',
        userId: 'user-1',
        clientId: 'client-1',
        hasBeenApplied: false,
        hasBeenSynced: false,
      );

      // Parsing should return null for invalid format
      final parsed = HLC.tryParse(msg.localTimestamp);
      expect(parsed, isNull);

      // compareTimestamps should handle gracefully
      final comparison = HLC.compareTimestamps(
        msg.localTimestamp,
        HLC.now('test').toString(),
      );
      expect(comparison, equals(-1)); // Invalid is less than valid
    });

    test('handles empty HLC timestamp string', () async {
      final parsed = HLC.tryParse('');
      expect(parsed, isNull);

      final comparison = HLC.compareTimestamps('', '');
      expect(comparison, equals(0));
    });

    test('handles HLC with very large timestamp', () async {
      final large = HLC(
        timestamp: 9007199254740991, // Max safe JS integer
        count: 0,
        node: 'client-1',
      );

      final packed = large.toString();
      final restored = HLC.tryParse(packed);

      expect(restored, isNotNull);
      expect(restored!.timestamp, equals(9007199254740991));
    });

    test('handles HLC with very large count', () async {
      final large = HLC(
        timestamp: 1000,
        count: 999999999,
        node: 'client-1',
      );

      final packed = large.toString();
      final restored = HLC.tryParse(packed);

      expect(restored, isNotNull);
      expect(restored!.count, equals(999999999));
    });
  });

  group('Edge Cases - Data Types', () {
    test('handles very large integer', () async {
      final largeInt = 9007199254740991; // Max safe JS integer
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: largeInt,
      );

      expect(offlineDb.messages.first.typedValue, equals(largeInt));
    });

    test('handles negative large integer', () async {
      final negativeInt = -9007199254740991;
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: negativeInt,
      );

      expect(offlineDb.messages.first.typedValue, equals(negativeInt));
    });

    test('handles very small double', () async {
      final smallDouble = 0.000000000001;
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: smallDouble,
      );

      expect(offlineDb.messages.first.typedValue, closeTo(smallDouble, 1e-15));
    });

    test('handles infinity double', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: double.infinity,
      );

      expect(offlineDb.messages.first.typedValue, equals(double.infinity));
    });

    test('handles NaN double', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: double.nan,
      );

      expect(offlineDb.messages.first.typedValue, isNaN);
    });

    test('handles deeply nested JSON', () async {
      Map<String, dynamic> nested = {'level': 0};
      for (int i = 1; i <= 20; i++) {
        nested = {'level': i, 'child': nested};
      }

      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: nested,
      );

      final restored = offlineDb.messages.first.typedValue as Map;
      expect(restored['level'], equals(20));
    });

    test('handles empty Map', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: <String, dynamic>{},
      );

      expect(offlineDb.messages.first.typedValue, equals({}));
    });

    test('handles empty List', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: <dynamic>[],
      );

      expect(offlineDb.messages.first.typedValue, equals([]));
    });

    test('handles DateTime at epoch', () async {
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: epoch,
      );

      expect(offlineDb.messages.first.typedValue, equals(epoch));
    });

    test('handles far future DateTime', () async {
      final future = DateTime(9999, 12, 31, 23, 59, 59);
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: future,
      );

      expect(offlineDb.messages.first.typedValue, equals(future));
    });
  });
}
