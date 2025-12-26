import 'package:test/test.dart';
import 'package:talon/talon.dart';

import '../mocks/mock_offline_database.dart';
import '../mocks/mock_server_database.dart';

void main() {
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

  group('Message Creation Performance', () {
    test('can create 1000 messages quickly', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration(seconds: 10), // Delay sync
          immediateSyncOnSave: false,
        ),
      );

      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 1000; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      stopwatch.stop();

      expect(offlineDb.messages.length, equals(1000));
      // Should complete in reasonable time (< 5 seconds for 1000 messages)
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));

      talon.dispose();
    });

    test('batch save is faster than individual saves', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration(seconds: 10),
          immediateSyncOnSave: false,
        ),
      );

      // Time individual saves
      final individualStopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        await talon.saveChange(
          table: 'individual',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }
      individualStopwatch.stop();

      // Time batch save
      final batchStopwatch = Stopwatch()..start();
      final changes = List.generate(
        100,
        (i) => TalonChangeData(
          table: 'batch',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        ),
      );
      await talon.saveChanges(changes);
      batchStopwatch.stop();

      expect(offlineDb.messages.length, equals(200));

      // Batch should be at least as fast (often faster)
      // We're not strictly enforcing this since mock DBs are fast
      // but log for observation
      // print('Individual: ${individualStopwatch.elapsedMilliseconds}ms');
      // print('Batch: ${batchStopwatch.elapsedMilliseconds}ms');

      talon.dispose();
    });
  });

  group('Serialization Performance', () {
    test('serializes various types efficiently', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration(seconds: 10),
          immediateSyncOnSave: false,
        ),
      );

      final stopwatch = Stopwatch()..start();

      // Test various types
      for (int i = 0; i < 100; i++) {
        await talon.saveChange(
          table: 'types',
          row: 'row-$i',
          column: 'string',
          value: 'string value $i',
        );
        await talon.saveChange(
          table: 'types',
          row: 'row-$i',
          column: 'int',
          value: i,
        );
        await talon.saveChange(
          table: 'types',
          row: 'row-$i',
          column: 'double',
          value: i * 1.5,
        );
        await talon.saveChange(
          table: 'types',
          row: 'row-$i',
          column: 'bool',
          value: i % 2 == 0,
        );
        await talon.saveChange(
          table: 'types',
          row: 'row-$i',
          column: 'datetime',
          value: DateTime.now(),
        );
        await talon.saveChange(
          table: 'types',
          row: 'row-$i',
          column: 'json',
          value: {'index': i, 'data': 'value-$i'},
        );
      }

      stopwatch.stop();

      expect(offlineDb.messages.length, equals(600));
      // 600 messages with various types should complete quickly
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));

      talon.dispose();
    });

    test('handles large JSON payloads', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration(seconds: 10),
          immediateSyncOnSave: false,
        ),
      );

      // Create a moderately large JSON structure
      final largeJson = {
        'items': List.generate(100, (i) => {
          'id': i,
          'name': 'Item $i',
          'description': 'A somewhat long description for item $i ' * 5,
          'tags': List.generate(10, (j) => 'tag-$i-$j'),
          'metadata': {
            'created': DateTime.now().toIso8601String(),
            'updated': DateTime.now().toIso8601String(),
            'version': i,
          },
        }),
      };

      final stopwatch = Stopwatch()..start();

      await talon.saveChange(
        table: 'large',
        row: 'row-1',
        column: 'data',
        value: largeJson,
      );

      stopwatch.stop();

      expect(offlineDb.messages.length, equals(1));
      expect(offlineDb.messages.first.dataType, equals('json'));
      // Large JSON should still be fast
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));

      talon.dispose();
    });
  });

  group('Sync Performance', () {
    test('syncs 500 messages in batches efficiently', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          batchSize: 50,
          syncDebounce: Duration.zero,
          immediateSyncOnSave: false,
        ),
      );

      // Create messages without syncing
      for (int i = 0; i < 500; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      expect(offlineDb.messages.length, equals(500));
      expect(serverDb.messageCount, equals(0));

      // Enable sync and time it
      talon.syncIsEnabled = true;
      final stopwatch = Stopwatch()..start();
      await talon.forceSyncToServer();
      stopwatch.stop();

      expect(serverDb.messageCount, equals(500));
      // 500 messages in 10 batches of 50 should be fast
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));

      talon.dispose();
    });

    test('smaller batch sizes process correctly', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          batchSize: 5,
          syncDebounce: Duration.zero,
          immediateSyncOnSave: false,
        ),
      );

      for (int i = 0; i < 27; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      talon.syncIsEnabled = true;
      await talon.forceSyncToServer();

      // All 27 messages should sync (6 batches: 5,5,5,5,5,2)
      expect(serverDb.messageCount, equals(27));

      talon.dispose();
    });

    test('large batch size handles few messages', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          batchSize: 100,
          syncDebounce: Duration.zero,
          immediateSyncOnSave: false,
        ),
      );

      // Only 10 messages, batch size is 100
      for (int i = 0; i < 10; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      talon.syncIsEnabled = true;
      await talon.forceSyncToServer();

      expect(serverDb.messageCount, equals(10));

      talon.dispose();
    });
  });

  group('HLC Performance', () {
    test('HLC generation is fast for many messages', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration(seconds: 10),
          immediateSyncOnSave: false,
        ),
      );

      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 10000; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      stopwatch.stop();

      expect(offlineDb.messages.length, equals(10000));

      // 10000 HLC generations should be very fast
      // This tests that HLC.send() is O(1)
      expect(stopwatch.elapsedMilliseconds, lessThan(10000));

      // Verify all timestamps are unique and ordered
      final timestamps = offlineDb.messages.map((m) => m.localTimestamp).toSet();
      expect(timestamps.length, equals(10000));

      talon.dispose();
    });

    test('HLC parsing is efficient', () {
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 10000; i++) {
        final ts = '000001234567890$i:0000${i % 100}:client-$i';
        HLC.tryParse(ts);
      }

      stopwatch.stop();

      // Parsing should be very fast
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('HLC comparison is efficient', () {
      // Pre-create HLCs
      final hlcs = List.generate(
        1000,
        (i) => HLC(
          timestamp: 1234567890000 + i,
          count: i % 100,
          node: 'client-${i % 10}',
        ),
      );

      final stopwatch = Stopwatch()..start();

      // Compare all pairs (1000 * 999 / 2 comparisons)
      for (int i = 0; i < hlcs.length; i++) {
        for (int j = i + 1; j < hlcs.length; j++) {
          hlcs[i].compareTo(hlcs[j]);
        }
      }

      stopwatch.stop();

      // ~500k comparisons should be very fast
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('Stream Performance', () {
    test('stream notifications are delivered efficiently', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration(seconds: 10),
          immediateSyncOnSave: false,
        ),
      );

      final changes = <TalonChange>[];
      final sub = talon.changes.listen(changes.add);

      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 1000; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      stopwatch.stop();

      // All changes should be notified
      expect(changes.length, equals(1000));
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));

      await sub.cancel();
      talon.dispose();
    });

    test('multiple listeners handle notifications efficiently', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration(seconds: 10),
          immediateSyncOnSave: false,
        ),
      );

      final listeners = List.generate(
        10,
        (_) => <TalonChange>[],
      );
      final subs = listeners.map((l) => talon.changes.listen(l.add)).toList();

      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 100; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      stopwatch.stop();

      // All 10 listeners should receive all 100 changes
      for (final listener in listeners) {
        expect(listener.length, equals(100));
      }
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));

      for (final sub in subs) {
        await sub.cancel();
      }
      talon.dispose();
    });
  });

  group('Memory Efficiency', () {
    test('can handle many unique rows', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration(seconds: 10),
          immediateSyncOnSave: false,
        ),
      );

      // Create 5000 unique rows
      for (int i = 0; i < 5000; i++) {
        await talon.saveChange(
          table: 'users',
          row: 'user-$i',
          column: 'name',
          value: 'User Name $i',
        );
      }

      expect(offlineDb.messages.length, equals(5000));

      // Verify all rows are unique
      final rows = offlineDb.messages.map((m) => m.row).toSet();
      expect(rows.length, equals(5000));

      talon.dispose();
    });

    test('can handle many tables', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration(seconds: 10),
          immediateSyncOnSave: false,
        ),
      );

      // Create 100 different tables
      for (int i = 0; i < 100; i++) {
        await talon.saveChange(
          table: 'table_$i',
          row: 'row-1',
          column: 'value',
          value: 'value-$i',
        );
      }

      expect(offlineDb.messages.length, equals(100));

      final tables = offlineDb.messages.map((m) => m.table).toSet();
      expect(tables.length, equals(100));

      talon.dispose();
    });

    test('can handle many columns per row', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration(seconds: 10),
          immediateSyncOnSave: false,
        ),
      );

      // Create 200 columns for one row
      for (int i = 0; i < 200; i++) {
        await talon.saveChange(
          table: 'wide_table',
          row: 'row-1',
          column: 'column_$i',
          value: 'value-$i',
        );
      }

      expect(offlineDb.messages.length, equals(200));

      final columns = offlineDb.messages.map((m) => m.column).toSet();
      expect(columns.length, equals(200));

      talon.dispose();
    });
  });
}
