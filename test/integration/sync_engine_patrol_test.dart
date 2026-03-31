import 'dart:async';

import 'package:test/test.dart';
import 'package:talon/talon.dart';

import '../mocks/mock_offline_database.dart';
import '../mocks/mock_server_database.dart';

void main() {
  group('Sync Engine Patrol Integration Test', () {
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

    group('Scenario 1: Simple Push → Sync', () {
      test('saveChange creates local message and forceSyncToServer sends it', () async {
        // Save a local change
        await talon.saveChange(
          table: 'todos',
          row: 'todo-1',
          column: 'title',
          value: 'Buy milk',
        );

        // Verify: message is in offline DB
        expect(offlineDb.messageCount, equals(1));
        expect(offlineDb.getValue('todos', 'todo-1', 'title'), equals('Buy milk'));

        // Force sync to server
        talon.syncIsEnabled = true;
        await talon.forceSyncToServer();

        // Verify: message is on server with serverTimestamp
        expect(serverDb.messageCount, equals(1));
        final serverMessages = serverDb.serverMessages;
        expect(serverMessages.first.serverTimestamp, isNotNull);

        // Verify: local message is marked as synced
        final unsynced = await offlineDb.getUnsyncedMessages();
        expect(unsynced.isEmpty, isTrue);
      });

      test('receives serverTimestamp after sync', () async {
        await talon.saveChange(
          table: 'todos',
          row: 'todo-1',
          column: 'title',
          value: 'Buy milk',
        );

        talon.syncIsEnabled = true;
        await talon.forceSyncToServer();

        // Verify the server assigned a timestamp
        expect(serverDb.messageCount, equals(1));
        expect(serverDb.serverMessages.first.serverTimestamp, equals(1));
      });
    });

    group('Scenario 2: Server Change → Sync Down', () {
      test('subscription receives message from other client', () async {
        talon.syncIsEnabled = true;

        // Simulate server message from different client
        serverDb.simulateServerMessage(Message(
          id: 'server-msg-1',
          table: 'todos',
          row: 'todo-2',
          column: 'title',
          dataType: 'string',
          value: 'Buy eggs',
          localTimestamp: HLC.now('client-2').toString(),
          userId: 'user-1',
          clientId: 'client-2',
          hasBeenApplied: false,
          hasBeenSynced: true,
        ));

        // Give subscription time to process
        await Future.delayed(Duration(milliseconds: 50));

        // Verify: change is in offline DB and applied
        expect(offlineDb.getValue('todos', 'todo-2', 'title'), equals('Buy eggs'));
        expect(offlineDb.messageCount, equals(1));
      });

      test('ignores messages from own client', () async {
        talon.syncIsEnabled = true;

        // Simulate message from our own client (should be ignored)
        serverDb.simulateServerMessage(Message(
          id: 'own-msg',
          table: 'todos',
          row: 'todo-1',
          column: 'title',
          dataType: 'string',
          value: 'Should be ignored',
          localTimestamp: HLC.now('client-1').toString(),
          userId: 'user-1',
          clientId: 'client-1',
          hasBeenApplied: false,
          hasBeenSynced: true,
        ));

        await Future.delayed(Duration(milliseconds: 50));

        // Verify: nothing was applied (own messages are filtered)
        expect(offlineDb.getValue('todos', 'todo-1', 'title'), isNull);
      });
    });

    group('Scenario 3: CRDT Merge (Overlapping Edits)', () {
      test('newer message wins over older in conflict', () async {
        final olderTimestamp = HLC(
          timestamp: 1000,
          count: 0,
          node: 'client-2',
        ).toString();

        final newerTimestamp = HLC(
          timestamp: 2000,
          count: 0,
          node: 'client-1',
        ).toString();

        // Simulate older message from server
        serverDb.simulateServerMessage(Message(
          id: 'old-msg',
          table: 'todos',
          row: 'todo-1',
          column: 'title',
          dataType: 'string',
          value: 'Old value',
          localTimestamp: olderTimestamp,
          userId: 'user-1',
          clientId: 'client-2',
          hasBeenApplied: false,
          hasBeenSynced: true,
        ));

        talon.syncIsEnabled = true;
        await Future.delayed(Duration(milliseconds: 50));

        // Verify older message is applied (first one wins when both are received)
        expect(offlineDb.getValue('todos', 'todo-1', 'title'), equals('Old value'));

        // Simulate newer message from server
        serverDb.simulateServerMessage(Message(
          id: 'new-msg',
          table: 'todos',
          row: 'todo-1',
          column: 'title',
          dataType: 'string',
          value: 'New value',
          localTimestamp: newerTimestamp,
          userId: 'user-1',
          clientId: 'client-2',
          hasBeenApplied: false,
          hasBeenSynced: true,
        ));

        await Future.delayed(Duration(milliseconds: 50));

        // Verify newer message overwrites (last-write-wins)
        expect(offlineDb.getValue('todos', 'todo-1', 'title'), equals('New value'));

        // Verify both messages are stored in message table
        expect(offlineDb.messageCount, equals(2));
      });

      test('conflicting local vs server change resolves to latest HLC', () async {
        // Make a local change with a fixed timestamp
        final localMsg = Message(
          id: 'msg-0',
          table: 'todos',
          row: 'todo-1',
          column: 'title',
          dataType: 'string',
          value: 'Local value',
          localTimestamp: HLC(timestamp: 1500, count: 0, node: 'client-1').toString(),
          userId: 'user-1',
          clientId: 'client-1',
          hasBeenApplied: true,
          hasBeenSynced: false,
        );

        await offlineDb.applyMessageToLocalDataTable(localMsg);
        await offlineDb.applyMessageToLocalMessageTable(localMsg);

        // Simulate newer server message
        serverDb.simulateServerMessage(Message(
          id: 'server-msg',
          table: 'todos',
          row: 'todo-1',
          column: 'title',
          dataType: 'string',
          value: 'Server value',
          localTimestamp: HLC(timestamp: 2000, count: 0, node: 'client-2').toString(),
          userId: 'user-1',
          clientId: 'client-2',
          hasBeenApplied: false,
          hasBeenSynced: true,
        ));

        talon.syncIsEnabled = true;
        await Future.delayed(Duration(milliseconds: 50));

        // Server message (T=2000) should win over local (T=1500)
        expect(offlineDb.getValue('todos', 'todo-1', 'title'), equals('Server value'));
      });
    });

    group('Scenario 4: Batching & Debounce', () {
      test('batches messages correctly with batchSize=2', () async {
        final batchTalon = Talon(
          userId: 'user-1',
          clientId: 'client-1',
          serverDatabase: serverDb,
          offlineDatabase: offlineDb,
          createNewIdFunction: () => 'msg-${messageIdCounter++}',
          config: const TalonConfig(batchSize: 2),
        );

        // Save 5 messages rapidly
        for (int i = 0; i < 5; i++) {
          await batchTalon.saveChange(
            table: 'todos',
            row: 'todo-$i',
            column: 'title',
            value: 'Item $i',
          );
        }

        batchTalon.syncIsEnabled = true;
        await batchTalon.forceSyncToServer();

        // Verify: all 5 messages are on server
        // With batchSize=2, should be sent as 3 batches: (2, 2, 1)
        expect(serverDb.messageCount, equals(5));

        // Verify: all are marked synced locally
        final unsynced = await offlineDb.getUnsyncedMessages();
        expect(unsynced.isEmpty, isTrue);

        batchTalon.dispose();
      });

      test('flushes mid-batch messages when sync triggered', () async {
        final batchTalon = Talon(
          userId: 'user-1',
          clientId: 'client-1',
          serverDatabase: serverDb,
          offlineDatabase: offlineDb,
          createNewIdFunction: () => 'msg-${messageIdCounter++}',
          config: const TalonConfig(batchSize: 3),
        );

        // Save 4 messages
        for (int i = 0; i < 4; i++) {
          await batchTalon.saveChange(
            table: 'todos',
            row: 'todo-$i',
            column: 'title',
            value: 'Item $i',
          );
        }

        batchTalon.syncIsEnabled = true;
        await batchTalon.forceSyncToServer();

        // All 4 should be sent (batch 1: 3, batch 2: 1)
        expect(serverDb.messageCount, equals(4));

        batchTalon.dispose();
      });

      test('marks all batched messages as synced after successful send', () async {
        final batchTalon = Talon(
          userId: 'user-1',
          clientId: 'client-1',
          serverDatabase: serverDb,
          offlineDatabase: offlineDb,
          createNewIdFunction: () => 'msg-${messageIdCounter++}',
          config: const TalonConfig(batchSize: 2),
        );

        // Save 3 messages
        await batchTalon.saveChange(
          table: 'todos',
          row: 'todo-1',
          column: 'title',
          value: 'Item 1',
        );
        await batchTalon.saveChange(
          table: 'todos',
          row: 'todo-2',
          column: 'title',
          value: 'Item 2',
        );
        await batchTalon.saveChange(
          table: 'todos',
          row: 'todo-3',
          column: 'title',
          value: 'Item 3',
        );

        // Before sync
        var unsynced = await offlineDb.getUnsyncedMessages();
        expect(unsynced.length, equals(3));

        // Sync
        batchTalon.syncIsEnabled = true;
        await batchTalon.forceSyncToServer();

        // After sync
        unsynced = await offlineDb.getUnsyncedMessages();
        expect(unsynced.isEmpty, isTrue);

        batchTalon.dispose();
      });
    });

    group('Integration: Multi-Scenario Flow', () {
      test('complete workflow: push, sync-down, merge, batch', () async {
        talon.syncIsEnabled = true;

        // Step 1: Save local change
        await talon.saveChange(
          table: 'todos',
          row: 'todo-1',
          column: 'title',
          value: 'Local todo',
        );

        // Step 2: Sync to server
        await talon.forceSyncToServer();
        expect(serverDb.messageCount, equals(1));

        // Step 3: Receive competing change from server (older timestamp)
        serverDb.simulateServerMessage(Message(
          id: 'server-msg-1',
          table: 'todos',
          row: 'todo-2',
          column: 'title',
          dataType: 'string',
          value: 'Server todo',
          localTimestamp: HLC(timestamp: 500, count: 0, node: 'client-2').toString(),
          userId: 'user-1',
          clientId: 'client-2',
          hasBeenApplied: false,
          hasBeenSynced: true,
        ));

        await Future.delayed(Duration(milliseconds: 50));

        // Step 4: Save multiple messages
        await talon.saveChange(
          table: 'todos',
          row: 'todo-3',
          column: 'title',
          value: 'Another local',
        );
        await talon.saveChange(
          table: 'todos',
          row: 'todo-4',
          column: 'title',
          value: 'Yet another',
        );

        // Step 5: Final sync
        await talon.forceSyncToServer();

        // Verify: all local messages are on server
        expect(serverDb.messageCount, equals(4)); // 1 original + 1 server + 2 new

        // Verify: local state is correct
        expect(offlineDb.getValue('todos', 'todo-1', 'title'), equals('Local todo'));
        expect(offlineDb.getValue('todos', 'todo-2', 'title'), equals('Server todo'));
        expect(offlineDb.getValue('todos', 'todo-3', 'title'), equals('Another local'));
        expect(offlineDb.getValue('todos', 'todo-4', 'title'), equals('Yet another'));

        // Verify: no unsynced messages remain
        final unsynced = await offlineDb.getUnsyncedMessages();
        expect(unsynced.isEmpty, isTrue);
      });
    });
  });
}
