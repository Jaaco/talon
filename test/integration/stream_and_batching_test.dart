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

  group('TalonChange Stream', () {
    test('emits local changes', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      final changes = <TalonChange>[];
      final sub = talon.changes.listen(changes.add);

      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Test',
      );

      await Future.delayed(Duration(milliseconds: 10));

      expect(changes.length, equals(1));
      expect(changes.first.source, equals(TalonChangeSource.local));
      expect(changes.first.messages.length, equals(1));
      expect(changes.first.affectsTable('todos'), isTrue);
      expect(changes.first.affectsTable('other'), isFalse);

      await sub.cancel();
      talon.dispose();
    });

    test('emits server changes', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );
      talon.syncIsEnabled = true;

      final changes = <TalonChange>[];
      final sub = talon.changes.listen(changes.add);

      // Simulate server message
      serverDb.simulateServerMessage(Message(
        id: 'server-msg',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'From server',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-1',
        clientId: 'client-2',
        dataType: 'string',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await Future.delayed(Duration(milliseconds: 50));

      final serverChanges = changes.where((c) => c.source == TalonChangeSource.server).toList();
      expect(serverChanges.length, greaterThanOrEqualTo(1));

      await sub.cancel();
      talon.dispose();
    });

    test('localChanges stream filters correctly', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );
      talon.syncIsEnabled = true;

      final localChanges = <TalonChange>[];
      final sub = talon.localChanges.listen(localChanges.add);

      // Make local change
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Local',
      );

      // Simulate server change
      serverDb.simulateServerMessage(Message(
        id: 'server-msg',
        table: 'todos',
        row: 'todo-2',
        column: 'name',
        value: 'Server',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-1',
        clientId: 'client-2',
        dataType: 'string',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await Future.delayed(Duration(milliseconds: 50));

      // Only local changes should be in the stream
      expect(localChanges.length, equals(1));
      expect(localChanges.first.source, equals(TalonChangeSource.local));

      await sub.cancel();
      talon.dispose();
    });

    test('serverChanges stream filters correctly', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );
      talon.syncIsEnabled = true;

      final serverChanges = <TalonChange>[];
      final sub = talon.serverChanges.listen(serverChanges.add);

      // Make local change
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Local',
      );

      // Simulate server change
      serverDb.simulateServerMessage(Message(
        id: 'server-msg',
        table: 'todos',
        row: 'todo-2',
        column: 'name',
        value: 'Server',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-1',
        clientId: 'client-2',
        dataType: 'string',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await Future.delayed(Duration(milliseconds: 50));

      // Only server changes should be in the stream
      expect(serverChanges.length, greaterThanOrEqualTo(1));
      for (final change in serverChanges) {
        expect(change.source, equals(TalonChangeSource.server));
      }

      await sub.cancel();
      talon.dispose();
    });

    test('TalonChange.forTable returns filtered messages', () {
      final change = TalonChange(
        source: TalonChangeSource.local,
        messages: [
          Message(
            id: 'msg-1',
            table: 'todos',
            row: 'r1',
            column: 'c1',
            dataType: '',
            value: 'v1',
            localTimestamp: 'ts',
            userId: 'u',
            clientId: 'c',
            hasBeenApplied: false,
            hasBeenSynced: false,
          ),
          Message(
            id: 'msg-2',
            table: 'users',
            row: 'r2',
            column: 'c2',
            dataType: '',
            value: 'v2',
            localTimestamp: 'ts',
            userId: 'u',
            clientId: 'c',
            hasBeenApplied: false,
            hasBeenSynced: false,
          ),
          Message(
            id: 'msg-3',
            table: 'todos',
            row: 'r3',
            column: 'c3',
            dataType: '',
            value: 'v3',
            localTimestamp: 'ts',
            userId: 'u',
            clientId: 'c',
            hasBeenApplied: false,
            hasBeenSynced: false,
          ),
        ],
      );

      final todoMessages = change.forTable('todos');
      expect(todoMessages.length, equals(2));
      expect(todoMessages.every((m) => m.table == 'todos'), isTrue);
    });

    test('TalonChange.affectsRow works correctly', () {
      final change = TalonChange(
        source: TalonChangeSource.local,
        messages: [
          Message(
            id: 'msg-1',
            table: 'todos',
            row: 'todo-1',
            column: 'name',
            dataType: '',
            value: 'v1',
            localTimestamp: 'ts',
            userId: 'u',
            clientId: 'c',
            hasBeenApplied: false,
            hasBeenSynced: false,
          ),
        ],
      );

      expect(change.affectsRow('todos', 'todo-1'), isTrue);
      expect(change.affectsRow('todos', 'todo-2'), isFalse);
      expect(change.affectsRow('users', 'todo-1'), isFalse);
    });
  });

  group('Batch Operations (saveChanges)', () {
    test('saveChanges saves multiple messages', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      await talon.saveChanges([
        TalonChangeData(table: 'todos', row: 'todo-1', column: 'name', value: 'First'),
        TalonChangeData(table: 'todos', row: 'todo-1', column: 'done', value: false),
        TalonChangeData(table: 'todos', row: 'todo-1', column: 'priority', value: 1),
      ]);

      expect(offlineDb.messageCount, equals(3));
      talon.dispose();
    });

    test('saveChanges emits single batch change event', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      final changes = <TalonChange>[];
      final sub = talon.changes.listen(changes.add);

      await talon.saveChanges([
        TalonChangeData(table: 'todos', row: 'todo-1', column: 'name', value: 'First'),
        TalonChangeData(table: 'todos', row: 'todo-1', column: 'done', value: false),
        TalonChangeData(table: 'todos', row: 'todo-1', column: 'priority', value: 1),
      ]);

      await Future.delayed(Duration(milliseconds: 10));

      // Should be one batch with 3 messages, not 3 separate events
      expect(changes.length, equals(1));
      expect(changes.first.messages.length, equals(3));

      await sub.cancel();
      talon.dispose();
    });

    test('saveChanges with empty list does nothing', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      final changes = <TalonChange>[];
      final sub = talon.changes.listen(changes.add);

      await talon.saveChanges([]);

      await Future.delayed(Duration(milliseconds: 10));

      expect(changes, isEmpty);
      expect(offlineDb.messageCount, equals(0));

      await sub.cancel();
      talon.dispose();
    });

    test('saveChanges respects custom dataType', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      await talon.saveChanges([
        TalonChangeData(
          table: 'todos',
          row: 'todo-1',
          column: 'custom_field',
          value: 'value',
          dataType: 'custom',
        ),
      ]);

      expect(offlineDb.messages.first.dataType, equals('custom'));
      talon.dispose();
    });
  });

  group('Lifecycle Management', () {
    test('dispose prevents further operations', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
      );

      talon.dispose();

      expect(
        () => talon.saveChange(
          table: 'todos',
          row: 'todo-1',
          column: 'name',
          value: 'Test',
        ),
        throwsStateError,
      );
    });

    test('dispose can be called multiple times safely', () {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
      );

      talon.dispose();
      talon.dispose(); // Should not throw
    });

    test('startPeriodicSync and stopPeriodicSync work', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
      );
      talon.syncIsEnabled = true;

      talon.startPeriodicSync(interval: Duration(milliseconds: 100));

      // Wait for at least one tick
      await Future.delayed(Duration(milliseconds: 150));

      talon.stopPeriodicSync();
      talon.dispose();
    });

    test('forceSyncToServer bypasses debounce', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig(syncDebounce: Duration(seconds: 10)), // Long debounce
      );
      talon.syncIsEnabled = true;

      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Test',
      );

      // Message saved but not synced due to debounce
      expect(offlineDb.unsyncedCount, equals(1));

      // Force sync
      await talon.forceSyncToServer();

      // Now it should be synced
      expect(offlineDb.syncedCount, equals(1));

      talon.dispose();
    });
  });

  group('TalonConfig', () {
    test('immediate config syncs without debounce', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );
      talon.syncIsEnabled = true;

      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Test',
      );

      // Should be synced immediately
      expect(offlineDb.syncedCount, equals(1));

      talon.dispose();
    });

    test('debounce delays sync', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig(syncDebounce: Duration(milliseconds: 200)),
      );
      talon.syncIsEnabled = true;

      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Test',
      );

      // Not synced yet
      expect(offlineDb.unsyncedCount, equals(1));

      // Wait for debounce
      await Future.delayed(Duration(milliseconds: 300));

      // Now synced
      expect(offlineDb.syncedCount, equals(1));

      talon.dispose();
    });

    test('batching processes in chunks', () async {
      final talon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig(batchSize: 10, immediateSyncOnSave: true),
      );
      talon.syncIsEnabled = true;

      // Save 25 messages
      for (int i = 0; i < 25; i++) {
        await talon.saveChange(
          table: 'todos',
          row: 'todo-$i',
          column: 'name',
          value: 'Todo $i',
        );
      }

      // All should be synced
      expect(offlineDb.syncedCount, equals(25));

      talon.dispose();
    });
  });
}
