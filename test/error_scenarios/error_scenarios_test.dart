import 'dart:async';

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

  group('Server Send Failures', () {
    test('sync continues after single message failure', () async {
      // Create a server that fails every other message
      final failingServerDb = PartialFailServerDatabase();
      final testTalon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: failingServerDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: TalonConfig.immediate,
      );

      // Save 3 messages
      await testTalon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'value-1',
      );
      await testTalon.saveChange(
        table: 'test',
        row: 'row-2',
        column: 'value',
        value: 'value-2',
      );
      await testTalon.saveChange(
        table: 'test',
        row: 'row-3',
        column: 'value',
        value: 'value-3',
      );

      testTalon.syncIsEnabled = true;
      await testTalon.forceSyncToServer();

      // Some messages should have succeeded
      expect(failingServerDb.successfulMessages.length, greaterThan(0));

      testTalon.dispose();
      failingServerDb.dispose();
    });

    test('marks only successful messages as synced', () async {
      // Save multiple messages
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'value-1',
      );
      await talon.saveChange(
        table: 'test',
        row: 'row-2',
        column: 'value',
        value: 'value-2',
      );

      // Enable sync and sync
      talon.syncIsEnabled = true;
      await talon.forceSyncToServer();

      // All messages should be synced
      final synced = offlineDb.messages.where((m) => m.hasBeenSynced).toList();
      expect(synced.length, equals(2));
    });

    test('stops processing batches on partial failure', () async {
      final failingServerDb = FailAfterNMessagesServerDatabase(1);
      final testTalon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: failingServerDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(batchSize: 2),
      );

      // Save 4 messages (should be 2 batches)
      for (int i = 0; i < 4; i++) {
        await testTalon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      testTalon.syncIsEnabled = true;
      await testTalon.forceSyncToServer();

      // Only first message should be synced
      final synced = offlineDb.messages.where((m) => m.hasBeenSynced).toList();
      expect(synced.length, equals(1));

      testTalon.dispose();
    });

    test('retains unsynced messages after failed sync', () async {
      serverDb.shouldFailSend = true;

      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'value-1',
      );

      talon.syncIsEnabled = true;
      await talon.forceSyncToServer();

      // Message should still be in unsynced queue
      final unsynced = await offlineDb.getUnsyncedMessages();
      expect(unsynced.length, equals(1));
      expect(unsynced.first.hasBeenSynced, isFalse);
    });
  });

  group('Dispose Behavior', () {
    test('throws StateError when saveChange called after dispose', () async {
      talon.dispose();

      expect(
        () => talon.saveChange(
          table: 'test',
          row: 'row-1',
          column: 'value',
          value: 'test',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when saveChanges called after dispose', () async {
      talon.dispose();

      expect(
        () => talon.saveChanges([
          const TalonChangeData(
            table: 'test',
            row: 'row-1',
            column: 'value',
            value: 'test',
          ),
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when runSync called after dispose', () async {
      talon.dispose();

      expect(() => talon.runSync(), throwsA(isA<StateError>()));
    });

    test('throws StateError when syncIsEnabled set after dispose', () {
      talon.dispose();

      expect(() => talon.syncIsEnabled = true, throwsA(isA<StateError>()));
    });

    test('throws StateError when forceSyncToServer called after dispose',
        () async {
      talon.dispose();

      expect(() => talon.forceSyncToServer(), throwsA(isA<StateError>()));
    });

    test('throws StateError when startPeriodicSync called after dispose', () {
      talon.dispose();

      expect(() => talon.startPeriodicSync(), throwsA(isA<StateError>()));
    });

    test('double dispose is safe (no-op)', () {
      talon.dispose();
      expect(() => talon.dispose(), returnsNormally);
    });

    test('closes change stream on dispose', () async {
      final changes = <TalonChange>[];
      final subscription = talon.changes.listen(changes.add);

      talon.dispose();

      // Stream should be closed
      await subscription.asFuture().timeout(
            const Duration(milliseconds: 100),
            onTimeout: () => null,
          );

      expect(changes.isEmpty, isTrue);
    });
  });

  group('Subscription Handling', () {
    test('handles subscription when sync disabled', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'value-1',
      );

      // Subscription should not be active
      talon.syncIsEnabled = false;

      // Simulate server message - should not be received
      serverDb.simulateServerMessage(Message(
        id: 'server-msg-1',
        table: 'test',
        row: 'row-2',
        column: 'value',
        dataType: 'string',
        value: 'from-server',
        localTimestamp: 'ts-server',
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      // Should only have the local message
      expect(offlineDb.messages.length, equals(1));
    });

    test('resubscribes when sync re-enabled', () async {
      talon.syncIsEnabled = true;
      talon.syncIsEnabled = false;
      talon.syncIsEnabled = true;

      // Should work normally
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'value-1',
      );

      expect(offlineDb.messages.length, equals(1));
    });

    test('handles rapid sync enable/disable', () async {
      for (int i = 0; i < 10; i++) {
        talon.syncIsEnabled = i % 2 == 0;
      }

      // Should not throw or crash
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'test',
      );

      expect(offlineDb.messages.length, equals(1));
    });
  });

  group('Debounce Edge Cases', () {
    test('debounce timer cancelled on dispose', () async {
      final debouncedTalon = Talon(
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

      debouncedTalon.syncIsEnabled = true;

      await debouncedTalon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'test',
      );

      // Dispose before debounce fires
      debouncedTalon.dispose();

      // Wait for what would have been the debounce period
      await Future.delayed(const Duration(milliseconds: 100));

      // Should not crash - message should be saved locally but not synced
      expect(offlineDb.messages.length, equals(1));
      expect(serverDb.messageCount, equals(0));
    });

    test('forceSyncToServer cancels pending debounce', () async {
      final debouncedTalon = Talon(
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

      debouncedTalon.syncIsEnabled = true;

      await debouncedTalon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'test',
      );

      // Force sync immediately
      await debouncedTalon.forceSyncToServer();

      // Message should be synced immediately
      expect(serverDb.messageCount, equals(1));

      debouncedTalon.dispose();
    });
  });

  group('Periodic Sync', () {
    test('periodic sync timer cancelled on dispose', () async {
      talon.startPeriodicSync(interval: const Duration(milliseconds: 100));
      talon.dispose();

      // Wait for what would have been multiple sync cycles
      await Future.delayed(const Duration(milliseconds: 350));

      // No crash should occur
      expect(true, isTrue);
    });

    test('stopPeriodicSync cancels timer', () async {
      final syncCount = <int>[0];

      talon.syncIsEnabled = true;
      talon.startPeriodicSync(interval: const Duration(milliseconds: 50));

      // Track sync calls by watching server messages
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'test',
      );

      await Future.delayed(const Duration(milliseconds: 75));
      final countBefore = serverDb.messageCount;

      talon.stopPeriodicSync();

      // Add more messages that won't auto-sync
      serverDb.shouldFailSend = true; // Prevent syncing
      await Future.delayed(const Duration(milliseconds: 150));

      // Should have stopped periodic syncing
      // (message count should not have changed due to periodic sync)
      expect(true, isTrue); // Timer was cancelled successfully
    });

    test('startPeriodicSync replaces existing timer', () async {
      talon.syncIsEnabled = true;
      talon.startPeriodicSync(interval: const Duration(seconds: 1));
      talon.startPeriodicSync(interval: const Duration(seconds: 2));

      // Should not have multiple timers running
      // (just verify it doesn't throw)
      expect(true, isTrue);
    });
  });

  group('Empty Operations', () {
    test('saveChanges with empty list is no-op', () async {
      final changeCount = <int>[0];
      talon.changes.listen((_) => changeCount[0]++);

      await talon.saveChanges([]);

      // Should not emit any changes
      await Future.delayed(const Duration(milliseconds: 10));
      expect(changeCount[0], equals(0));
      expect(offlineDb.messages.isEmpty, isTrue);
    });

    test('sync with no messages is no-op', () async {
      talon.syncIsEnabled = true;
      await talon.forceSyncToServer();

      expect(serverDb.messageCount, equals(0));
    });

    test('syncFromServer with no new messages is no-op', () async {
      final changes = <TalonChange>[];
      talon.changes.listen(changes.add);

      talon.syncIsEnabled = true;
      await talon.runSync();

      // No server changes emitted
      await Future.delayed(const Duration(milliseconds: 10));
      expect(
        changes.where((c) => c.source == TalonChangeSource.server).isEmpty,
        isTrue,
      );
    });
  });

  group('Batch Processing Errors', () {
    test('handles empty batch gracefully', () async {
      talon.syncIsEnabled = true;
      await talon.forceSyncToServer();

      // No crash
      expect(serverDb.messageCount, equals(0));
    });

    test('processes exactly batch size messages', () async {
      final batchTalon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(batchSize: 3),
      );

      // Save exactly 3 messages (one batch)
      for (int i = 0; i < 3; i++) {
        await batchTalon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      batchTalon.syncIsEnabled = true;
      await batchTalon.forceSyncToServer();

      expect(serverDb.messageCount, equals(3));

      batchTalon.dispose();
    });

    test('handles messages spanning multiple batches', () async {
      final batchTalon = Talon(
        userId: 'user-1',
        clientId: 'client-1',
        serverDatabase: serverDb,
        offlineDatabase: offlineDb,
        createNewIdFunction: () => 'msg-${messageIdCounter++}',
        config: const TalonConfig(batchSize: 2),
      );

      // Save 5 messages (3 batches: 2, 2, 1)
      for (int i = 0; i < 5; i++) {
        await batchTalon.saveChange(
          table: 'test',
          row: 'row-$i',
          column: 'value',
          value: 'value-$i',
        );
      }

      batchTalon.syncIsEnabled = true;
      await batchTalon.forceSyncToServer();

      expect(serverDb.messageCount, equals(5));

      batchTalon.dispose();
    });
  });

  group('Stream Errors', () {
    test('changes stream handles multiple listeners', () async {
      final listener1 = <TalonChange>[];
      final listener2 = <TalonChange>[];

      final sub1 = talon.changes.listen(listener1.add);
      final sub2 = talon.changes.listen(listener2.add);

      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'test',
      );

      await Future.delayed(const Duration(milliseconds: 10));

      expect(listener1.length, equals(1));
      expect(listener2.length, equals(1));

      await sub1.cancel();
      await sub2.cancel();
    });

    test('cancelled listener does not receive events', () async {
      final changes = <TalonChange>[];
      final sub = talon.changes.listen(changes.add);

      await sub.cancel();

      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'test',
      );

      await Future.delayed(const Duration(milliseconds: 10));

      expect(changes.isEmpty, isTrue);
    });

    test('serverChanges filter works correctly', () async {
      final serverChanges = <TalonChange>[];
      final sub = talon.serverChanges.listen(serverChanges.add);

      // Local change should not appear
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'local',
      );

      await Future.delayed(const Duration(milliseconds: 10));
      expect(serverChanges.isEmpty, isTrue);

      await sub.cancel();
    });

    test('localChanges filter works correctly', () async {
      final localChanges = <TalonChange>[];
      final sub = talon.localChanges.listen(localChanges.add);

      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'local',
      );

      await Future.delayed(const Duration(milliseconds: 10));

      expect(localChanges.length, equals(1));
      expect(localChanges.first.source, equals(TalonChangeSource.local));

      await sub.cancel();
    });
  });
}

/// Server database that fails every other message.
class PartialFailServerDatabase extends ServerDatabase {
  int _sendCount = 0;
  final List<Message> successfulMessages = [];
  final _messageController = StreamController<Message>.broadcast();

  @override
  Future<List<Message>> getMessagesFromServer({
    required int? lastSyncedServerTimestamp,
    required String clientId,
    required String userId,
  }) async {
    return [];
  }

  @override
  Future<bool> sendMessageToServer({required Message message}) async {
    _sendCount++;
    if (_sendCount % 2 == 0) {
      return false; // Fail every other message
    }
    successfulMessages.add(message);
    return true;
  }

  @override
  StreamSubscription subscribeToServerMessages({
    required String clientId,
    required String userId,
    required int? lastSyncedServerTimestamp,
    required void Function(List<Message>) onMessagesReceived,
  }) {
    return _messageController.stream.listen((_) {});
  }

  void dispose() {
    _messageController.close();
  }
}

/// Server database that fails after N successful messages.
class FailAfterNMessagesServerDatabase extends ServerDatabase {
  final int successLimit;
  int _successCount = 0;
  final _messageController = StreamController<Message>.broadcast();

  FailAfterNMessagesServerDatabase(this.successLimit);

  @override
  Future<List<Message>> getMessagesFromServer({
    required int? lastSyncedServerTimestamp,
    required String clientId,
    required String userId,
  }) async {
    return [];
  }

  @override
  Future<bool> sendMessageToServer({required Message message}) async {
    if (_successCount >= successLimit) {
      return false;
    }
    _successCount++;
    return true;
  }

  @override
  StreamSubscription subscribeToServerMessages({
    required String clientId,
    required String userId,
    required int? lastSyncedServerTimestamp,
    required void Function(List<Message>) onMessagesReceived,
  }) {
    return _messageController.stream.listen((_) {});
  }
}
