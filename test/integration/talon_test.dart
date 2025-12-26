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
    );
  });

  tearDown(() {
    serverDb.dispose();
  });

  group('Talon - Basic Operations', () {
    test('saveChange stores message locally', () async {
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Buy milk',
      );

      expect(offlineDb.messageCount, equals(1));
      expect(offlineDb.messages.first.table, equals('todos'));
      expect(offlineDb.messages.first.value, equals('Buy milk'));
    });

    test('saveChange applies value to data table', () async {
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Buy milk',
      );

      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals('Buy milk'));
    });

    test('saveChange uses HLC timestamp', () async {
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Buy milk',
      );

      final message = offlineDb.messages.first;
      final hlc = HLC.tryParse(message.localTimestamp);

      expect(hlc, isNotNull);
      expect(hlc!.node, equals('client-1'));
    });

    test('saveChange does not sync when sync disabled', () async {
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Buy milk',
      );

      expect(serverDb.messageCount, equals(0));
    });

    test('saveChange syncs to server when enabled', () async {
      talon.syncIsEnabled = true;

      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Buy milk',
      );

      expect(serverDb.messageCount, equals(1));
    });

    test('messages marked as synced after successful sync', () async {
      talon.syncIsEnabled = true;

      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Buy milk',
      );

      expect(offlineDb.syncedCount, equals(1));
      expect(offlineDb.unsyncedCount, equals(0));
    });
  });

  group('Talon - Sync from Server', () {
    test('syncFromServer retrieves and applies server messages', () async {
      // Simulate message from another client
      serverDb.simulateServerMessage(Message(
        id: 'server-msg-1',
        table: 'todos',
        row: 'todo-2',
        column: 'name',
        value: 'Server todo',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      talon.syncIsEnabled = true;
      await talon.syncFromServer();

      expect(offlineDb.getValue('todos', 'todo-2', 'name'), equals('Server todo'));
    });

    test('syncFromServer ignores messages from same client', () async {
      // Message from our own client
      serverDb.simulateServerMessage(Message(
        id: 'my-msg-1',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'My todo',
        localTimestamp: HLC.now('client-1').toString(),
        userId: 'user-1',
        clientId: 'client-1', // Same as our client
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      talon.syncIsEnabled = true;
      await talon.syncFromServer();

      // Should not be in our local messages
      expect(offlineDb.messageCount, equals(0));
    });

    test('syncFromServer ignores messages from other users', () async {
      serverDb.simulateServerMessage(Message(
        id: 'other-user-msg',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Other user todo',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-2', // Different user
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      talon.syncIsEnabled = true;
      await talon.syncFromServer();

      expect(offlineDb.messageCount, equals(0));
    });
  });

  group('Talon - Conflict Resolution', () {
    test('later HLC timestamp wins over earlier', () async {
      talon.syncIsEnabled = true;

      // First change
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'First value',
      );

      // Small delay to ensure different timestamp
      await Future.delayed(Duration(milliseconds: 10));

      // Second change (should win)
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Second value',
      );

      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals('Second value'));
    });

    test('different columns are independent', () async {
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Todo name',
      );
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'is_done',
        value: '1',
      );

      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals('Todo name'));
      expect(offlineDb.getValue('todos', 'todo-1', 'is_done'), equals('1'));
    });

    test('different rows are independent', () async {
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'First todo',
      );
      await talon.saveChange(
        table: 'todos',
        row: 'todo-2',
        column: 'name',
        value: 'Second todo',
      );

      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals('First todo'));
      expect(offlineDb.getValue('todos', 'todo-2', 'name'), equals('Second todo'));
    });
  });

  group('Talon - HLC Updates', () {
    test('HLC advances with each saveChange', () async {
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'First',
      );
      await talon.saveChange(
        table: 'todos',
        row: 'todo-2',
        column: 'name',
        value: 'Second',
      );

      final first = offlineDb.messages[0];
      final second = offlineDb.messages[1];

      expect(
        HLC.compareTimestamps(second.localTimestamp, first.localTimestamp),
        greaterThan(0),
      );
    });
  });

  group('Talon - Error Handling', () {
    test('sync continues even if server send fails', () async {
      serverDb.shouldFailSend = true;
      talon.syncIsEnabled = true;

      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Buy milk',
      );

      // Message should be stored locally but not synced
      expect(offlineDb.messageCount, equals(1));
      expect(offlineDb.unsyncedCount, equals(1));
      expect(serverDb.messageCount, equals(0));
    });
  });

  group('Talon - runSync', () {
    test('runSync calls both syncToServer and syncFromServer', () async {
      talon.syncIsEnabled = true;

      // Create local message
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Local todo',
      );

      // Create server message from another client
      serverDb.simulateServerMessage(Message(
        id: 'server-msg',
        table: 'todos',
        row: 'todo-2',
        column: 'name',
        value: 'Server todo',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await talon.runSync();

      // Local message should be synced
      expect(offlineDb.syncedCount, greaterThan(0));
      // Server message should be applied
      expect(offlineDb.getValue('todos', 'todo-2', 'name'), equals('Server todo'));
    });
  });
}
