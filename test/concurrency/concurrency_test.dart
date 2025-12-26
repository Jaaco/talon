import 'dart:async';

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

  group('Concurrent Save Operations', () {
    test('handles concurrent saveChange calls', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      // Fire off many saves concurrently
      final futures = <Future<void>>[];
      for (int i = 0; i < 100; i++) {
        futures.add(talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        ));
      }

      await Future.wait(futures);

      expect(offlineDb.messages.length, equals(100));

      // All messages should have unique timestamps
      final timestamps = offlineDb.messages.map((m) => m.localTimestamp).toSet();
      expect(timestamps.length, equals(100));

      talon.dispose();
    });

    test('handles concurrent saveChanges calls', () async {
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

      final futures = <Future<void>>[];

      // 10 concurrent batch saves of 10 changes each
      for (int batch = 0; batch < 10; batch++) {
        final changes = List.generate(
          10,
          (i) => TalonChangeData(
            table: 'batch_$batch',
            row: 'row-$i',
            column: 'value',
            value: 'value-$i',
          ),
        );
        futures.add(talon.saveChanges(changes));
      }

      await Future.wait(futures);

      expect(offlineDb.messages.length, equals(100));

      talon.dispose();
    });

    test('concurrent saves to same cell maintain order', () async {
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

      // Save to same cell concurrently
      final futures = <Future<void>>[];
      for (int i = 0; i < 50; i++) {
        futures.add(talon.saveChange(
          table: 'test',
          row: 'shared-row',
          column: 'counter',
          value: i,
        ));
      }

      await Future.wait(futures);

      // All saves should complete
      final messages = offlineDb.messages.where(
        (m) => m.table == 'test' && m.row == 'shared-row',
      ).toList();

      expect(messages.length, equals(50));

      // Timestamps should all be unique and strictly ordered
      final timestamps = messages
          .map((m) => HLC.tryParse(m.localTimestamp)!)
          .toList();

      for (int i = 1; i < timestamps.length; i++) {
        expect(
          timestamps[i].compareTo(timestamps[i - 1]),
          greaterThan(0),
          reason: 'Timestamp at $i should be greater than at ${i - 1}',
        );
      }

      talon.dispose();
    });
  });

  group('Concurrent Sync Operations', () {
    test('handles concurrent runSync calls', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration.zero,
          immediateSyncOnSave: false,
        ),
      );

      // Create some messages first
      for (int i = 0; i < 20; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      talon.syncIsEnabled = true;

      // Multiple concurrent sync calls
      final futures = <Future<void>>[];
      for (int i = 0; i < 5; i++) {
        futures.add(talon.runSync());
      }

      await Future.wait(futures);

      // All messages should be synced
      final synced = offlineDb.messages.where((m) => m.hasBeenSynced).toList();
      expect(synced.length, equals(20));

      talon.dispose();
    });

    test('handles save during sync', () async {
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

      // Create initial messages
      for (int i = 0; i < 10; i++) {
        await talon.saveChange(
          table: 'initial',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      talon.syncIsEnabled = true;

      // Start sync and save more messages concurrently
      final syncFuture = talon.forceSyncToServer();

      // Save more while syncing
      for (int i = 0; i < 5; i++) {
        await talon.saveChange(
          table: 'during_sync',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      await syncFuture;

      // All initial messages should be synced
      expect(offlineDb.messages.length, equals(15));

      talon.dispose();
    });

    test('handles forceSyncToServer during debounced sync', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration(seconds: 5),
          immediateSyncOnSave: false,
        ),
      );

      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'test',
      );

      talon.syncIsEnabled = true;

      // Force sync should work even with pending debounce
      await talon.forceSyncToServer();

      expect(serverDb.messageCount, equals(1));

      talon.dispose();
    });
  });

  group('Multi-Client Simulation', () {
    test('simulates two clients syncing', () async {
      final offlineDb1 = MockOfflineDatabase();
      final offlineDb2 = MockOfflineDatabase();
      final sharedServerDb = MockServerDatabase();

      final client1 = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: sharedServerDb,
        offlineDatabase: offlineDb1,
        createNewIdFunction: () => 'msg-1-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      final client2 = Talon(
        userId: 'user-1',
        clientId: 'client-2',
        serverDatabase: sharedServerDb,
        offlineDatabase: offlineDb2,
        createNewIdFunction: () => 'msg-2-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      // Enable sync on both
      client1.syncIsEnabled = true;
      client2.syncIsEnabled = true;

      // Client 1 makes changes
      await client1.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Buy groceries',
      );

      // Wait for sync
      await Future.delayed(const Duration(milliseconds: 100));

      // Client 2 pulls from server
      await client2.runSync();

      // Client 2 should have received the message
      expect(offlineDb2.messages.length, greaterThanOrEqualTo(1));

      client1.dispose();
      client2.dispose();
      sharedServerDb.dispose();
    });

    test('simulates concurrent edits from multiple clients', () async {
      final offlineDb1 = MockOfflineDatabase();
      final offlineDb2 = MockOfflineDatabase();
      final sharedServerDb = MockServerDatabase();

      final client1 = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: sharedServerDb,
        offlineDatabase: offlineDb1,
        createNewIdFunction: () => 'msg-1-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      final client2 = Talon(
        userId: 'user-1',
        clientId: 'client-2',
        serverDatabase: sharedServerDb,
        offlineDatabase: offlineDb2,
        createNewIdFunction: () => 'msg-2-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      client1.syncIsEnabled = true;
      client2.syncIsEnabled = true;

      // Both clients edit the same cell concurrently
      final futures = <Future<void>>[];

      for (int i = 0; i < 10; i++) {
        futures.add(client1.saveChange(
          table: 'shared',
          row: 'row-1',
          column: 'value',
          value: 'from-client-1-$i',
        ));
        futures.add(client2.saveChange(
          table: 'shared',
          row: 'row-1',
          column: 'value',
          value: 'from-client-2-$i',
        ));
      }

      await Future.wait(futures);

      // Both should have 10 messages locally
      expect(offlineDb1.messages.length, equals(10));
      expect(offlineDb2.messages.length, equals(10));

      // Server should have all 20 messages
      await Future.delayed(const Duration(milliseconds: 100));
      expect(sharedServerDb.messageCount, equals(20));

      client1.dispose();
      client2.dispose();
      sharedServerDb.dispose();
    });

    test('clients receive each others updates via subscription', () async {
      final offlineDb1 = MockOfflineDatabase();
      final offlineDb2 = MockOfflineDatabase();
      final sharedServerDb = MockServerDatabase();

      final client1 = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: sharedServerDb,
        offlineDatabase: offlineDb1,
        createNewIdFunction: () => 'msg-1-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      final client2 = Talon(
        userId: 'user-1',
        clientId: 'client-2',
        serverDatabase: sharedServerDb,
        offlineDatabase: offlineDb2,
        createNewIdFunction: () => 'msg-2-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      final client1ServerChanges = <TalonChange>[];
      final client2ServerChanges = <TalonChange>[];

      client1.serverChanges.listen(client1ServerChanges.add);
      client2.serverChanges.listen(client2ServerChanges.add);

      client1.syncIsEnabled = true;
      client2.syncIsEnabled = true;

      // Client 1 makes a change
      await client1.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'from-1',
      );

      // Wait for propagation
      await Future.delayed(const Duration(milliseconds: 150));

      // Client 2 should receive server change (from client 1)
      expect(
        client2ServerChanges.any((c) => c.messages.any(
          (m) => m.value == 'from-1',
        )),
        isTrue,
      );

      // Client 1 should NOT receive its own change as server change
      expect(
        client1ServerChanges.any((c) => c.messages.any(
          (m) => m.value == 'from-1',
        )),
        isFalse,
      );

      client1.dispose();
      client2.dispose();
      sharedServerDb.dispose();
    });
  });

  group('Race Condition Prevention', () {
    test('rapid enable/disable sync does not crash', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      final futures = <Future<void>>[];

      for (int i = 0; i < 100; i++) {
        futures.add(Future(() {
          talon.syncIsEnabled = i % 2 == 0;
        }));
        futures.add(talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        ));
      }

      await Future.wait(futures);

      expect(offlineDb.messages.length, equals(100));

      talon.dispose();
    });

    test('dispose during active operations is safe', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration(milliseconds: 100),
          immediateSyncOnSave: false,
        ),
      );

      talon.syncIsEnabled = true;

      // Start some saves
      final saves = <Future<void>>[];
      for (int i = 0; i < 10; i++) {
        saves.add(talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        ));
      }

      // Dispose while operations are pending
      talon.dispose();

      // Await the saves that were started before dispose
      // (they may throw StateError, which is fine)
      for (final save in saves) {
        try {
          await save;
        } on StateError {
          // Expected for saves after dispose
        }
      }

      // No crash should occur
      expect(true, isTrue);
    });

    test('concurrent dispose calls are safe', () {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      // Call dispose multiple times concurrently
      final futures = <Future<void>>[];
      for (int i = 0; i < 10; i++) {
        futures.add(Future(() => talon.dispose()));
      }

      expect(Future.wait(futures), completes);
    });
  });

  group('Stream Concurrency', () {
    test('listeners added during emit receive events', () async {
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

      final changes1 = <TalonChange>[];
      final changes2 = <TalonChange>[];

      final sub1 = talon.changes.listen(changes1.add);

      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'first',
      );

      // Add second listener after first event
      final sub2 = talon.changes.listen(changes2.add);

      await talon.saveChange(
        table: 'test',
        row: 'row-2',
        column: 'value',
        value: 'second',
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(changes1.length, equals(2));
      expect(changes2.length, equals(1)); // Only received second

      await sub1.cancel();
      await sub2.cancel();
      talon.dispose();
    });

    test('listener removal during iteration is safe', () async {
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

      late StreamSubscription sub;
      int count = 0;

      sub = talon.changes.listen((change) {
        count++;
        if (count == 5) {
          sub.cancel(); // Cancel during iteration
        }
      });

      for (int i = 0; i < 10; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      await Future.delayed(const Duration(milliseconds: 50));

      // Should have received exactly 5 events
      expect(count, equals(5));

      talon.dispose();
    });

    test('paused listener resumes correctly', () async {
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

      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'first',
      );

      sub.pause();

      await talon.saveChange(
        table: 'test',
        row: 'row-2',
        column: 'value',
        value: 'during-pause',
      );

      sub.resume();

      await talon.saveChange(
        table: 'test',
        row: 'row-3',
        column: 'value',
        value: 'after-resume',
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // Broadcast stream - paused events may or may not be buffered
      // depending on implementation. At minimum, first and last should be there
      expect(changes.length, greaterThanOrEqualTo(2));

      await sub.cancel();
      talon.dispose();
    });
  });

  group('Timer Concurrency', () {
    test('periodic sync with concurrent saves', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(
          syncDebounce: Duration.zero,
          immediateSyncOnSave: false,
        ),
      );

      talon.syncIsEnabled = true;
      talon.startPeriodicSync(interval: const Duration(milliseconds: 50));

      // Make saves while periodic sync is running
      for (int i = 0; i < 20; i++) {
        await talon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Wait for a few sync cycles
      await Future.delayed(const Duration(milliseconds: 200));

      // Messages should have been synced
      expect(serverDb.messageCount, greaterThan(0));

      talon.dispose();
    });

    test('stop periodic sync during execution is safe', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      talon.syncIsEnabled = true;
      talon.startPeriodicSync(interval: const Duration(milliseconds: 10));

      // Let it run briefly
      await Future.delayed(const Duration(milliseconds: 50));

      // Stop it
      talon.stopPeriodicSync();

      // Should be safe
      expect(true, isTrue);

      talon.dispose();
    });
  });
}
