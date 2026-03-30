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

    test('server message with older timestamp does not overwrite local', () async {
      talon.syncIsEnabled = true;

      // Make a local change with current timestamp
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Local value',
      );

      // Simulate receiving an older server message
      final oldTimestamp = HLC(
        timestamp: DateTime.now().millisecondsSinceEpoch - 10000,
        count: 0,
        node: 'client-2',
      ).toString();

      serverDb.simulateServerMessage(Message(
        id: 'old-server-msg',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Old server value',
        localTimestamp: oldTimestamp,
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await talon.syncFromServer();

      // Local value should remain
      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals('Local value'));
    });

    test('server message with newer timestamp overwrites local', () async {
      talon.syncIsEnabled = true;

      // Make a local change
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Local value',
      );

      // Small delay to ensure different timestamp
      await Future.delayed(Duration(milliseconds: 10));

      // Simulate receiving a newer server message
      serverDb.simulateServerMessage(Message(
        id: 'new-server-msg',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'New server value',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await talon.syncFromServer();

      // Server value should win
      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals('New server value'));
    });

    test('concurrent edits to different columns both apply', () async {
      talon.syncIsEnabled = true;

      // Local change to 'name'
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'My todo',
      );

      // Server change to 'is_done' (different column)
      serverDb.simulateServerMessage(Message(
        id: 'server-done-msg',
        table: 'todos',
        row: 'todo-1',
        column: 'is_done',
        value: '1',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await talon.syncFromServer();

      // Both changes should be applied
      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals('My todo'));
      expect(offlineDb.getValue('todos', 'todo-1', 'is_done'), equals('1'));
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

    test('HLC updates from received server messages', () async {
      talon.syncIsEnabled = true;

      // First make a local change
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Local',
      );
      final localMessage = offlineDb.messages.first;

      // Simulate receiving a message with a future timestamp
      final futureTimestamp = HLC(
        timestamp: DateTime.now().millisecondsSinceEpoch + 10000,
        count: 5,
        node: 'client-2',
      ).toString();

      serverDb.simulateServerMessage(Message(
        id: 'future-msg',
        table: 'todos',
        row: 'todo-2',
        column: 'name',
        value: 'Future',
        localTimestamp: futureTimestamp,
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await talon.syncFromServer();

      // Now make another local change
      await talon.saveChange(
        table: 'todos',
        row: 'todo-3',
        column: 'name',
        value: 'After sync',
      );

      final afterSyncMessage = offlineDb.messages.last;

      // The new local message should have a timestamp greater than both
      // the original local message and the received future message
      expect(
        HLC.compareTimestamps(afterSyncMessage.localTimestamp, localMessage.localTimestamp),
        greaterThan(0),
      );
      expect(
        HLC.compareTimestamps(afterSyncMessage.localTimestamp, futureTimestamp),
        greaterThan(0),
      );
    });

    test('rapid successive changes increment HLC count', () async {
      // Make several changes in rapid succession
      for (int i = 0; i < 5; i++) {
        await talon.saveChange(
          table: 'todos',
          row: 'todo-$i',
          column: 'name',
          value: 'Value $i',
        );
      }

      // All messages should have strictly increasing HLCs
      for (int i = 1; i < offlineDb.messages.length; i++) {
        final prev = offlineDb.messages[i - 1];
        final curr = offlineDb.messages[i];

        expect(
          HLC.compareTimestamps(curr.localTimestamp, prev.localTimestamp),
          greaterThan(0),
        );
      }
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

  group('Talon - Subscription and Callbacks', () {
    test('onMessagesReceived is called when subscription receives message', () async {
      final receivedMessages = <Message>[];
      talon.onMessagesReceived = (messages) {
        receivedMessages.addAll(messages);
      };
      talon.syncIsEnabled = true;

      // Simulate a server message arriving via subscription
      serverDb.simulateServerMessage(Message(
        id: 'sub-msg-1',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'From subscription',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      // Wait a bit for async processing
      await Future.delayed(Duration(milliseconds: 50));

      expect(receivedMessages, isNotEmpty);
      expect(receivedMessages.first.value, equals('From subscription'));
    });

    test('onMessagesReceived can be changed', () async {
      final firstCallback = <Message>[];
      final secondCallback = <Message>[];

      talon.onMessagesReceived = (messages) {
        firstCallback.addAll(messages);
      };
      talon.syncIsEnabled = true;

      // First message
      serverDb.simulateServerMessage(Message(
        id: 'msg-1',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'First',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));
      await Future.delayed(Duration(milliseconds: 50));

      // Change callback
      talon.onMessagesReceived = (messages) {
        secondCallback.addAll(messages);
      };

      // Second message
      serverDb.simulateServerMessage(Message(
        id: 'msg-2',
        table: 'todos',
        row: 'todo-2',
        column: 'name',
        value: 'Second',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));
      await Future.delayed(Duration(milliseconds: 50));

      expect(firstCallback.length, equals(1));
      expect(secondCallback.length, equals(1));
    });

    test('disabling sync stops subscription', () async {
      final receivedMessages = <Message>[];
      talon.onMessagesReceived = (messages) {
        receivedMessages.addAll(messages);
      };

      talon.syncIsEnabled = true;
      talon.syncIsEnabled = false;

      // Simulate a server message - should not be received since sync is disabled
      serverDb.simulateServerMessage(Message(
        id: 'msg-ignored',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Should be ignored',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));
      await Future.delayed(Duration(milliseconds: 50));

      expect(receivedMessages, isEmpty);
    });

    test('re-enabling sync restarts subscription', () async {
      final receivedMessages = <Message>[];
      talon.onMessagesReceived = (messages) {
        receivedMessages.addAll(messages);
      };

      talon.syncIsEnabled = true;
      talon.syncIsEnabled = false;
      talon.syncIsEnabled = true;

      serverDb.simulateServerMessage(Message(
        id: 'msg-after-reenable',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'After re-enable',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));
      await Future.delayed(Duration(milliseconds: 50));

      expect(receivedMessages, isNotEmpty);
    });
  });

  group('Talon - Edge Cases', () {
    test('saveChange with empty value', () async {
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: '',
      );

      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals(''));
    });

    test('saveChange with special characters in value', () async {
      final specialValue = 'Test with "quotes" and \'apostrophes\' and \n newlines';
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: specialValue,
      );

      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals(specialValue));
    });

    test('saveChange with unicode characters', () async {
      final unicodeValue = 'Hello 世界 🌍 مرحبا';
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: unicodeValue,
      );

      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals(unicodeValue));
    });

    test('saveChange preserves dataType', () async {
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'priority',
        value: '5',
        dataType: 'int',
      );

      expect(offlineDb.messages.first.dataType, equals('int'));
    });

    test('multiple changes to same cell preserve order', () async {
      for (int i = 0; i < 10; i++) {
        await talon.saveChange(
          table: 'todos',
          row: 'todo-1',
          column: 'counter',
          value: i.toString(),
        );
      }

      // Final value should be the last one
      expect(offlineDb.getValue('todos', 'todo-1', 'counter'), equals('9'));
    });

    test('saveChange uses unique message IDs', () async {
      final ids = <String>{};

      for (int i = 0; i < 100; i++) {
        await talon.saveChange(
          table: 'todos',
          row: 'todo-$i',
          column: 'name',
          value: 'Value $i',
        );
      }

      for (final msg in offlineDb.messages) {
        expect(ids.contains(msg.id), isFalse, reason: 'Duplicate ID found: ${msg.id}');
        ids.add(msg.id);
      }
    });

    test('syncFromServer with no new messages does nothing', () async {
      talon.syncIsEnabled = true;
      final initialCount = offlineDb.messageCount;

      await talon.syncFromServer();

      expect(offlineDb.messageCount, equals(initialCount));
    });

    test('syncToServer with no unsynced messages does nothing', () async {
      talon.syncIsEnabled = true;

      await talon.syncToServer();

      expect(serverDb.messageCount, equals(0));
    });

    test('handles server failure gracefully', () async {
      talon.syncIsEnabled = true;
      serverDb.shouldFailSend = true;

      // Should not throw
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Will fail to sync',
      );

      // Message should still be stored locally
      expect(offlineDb.messageCount, equals(1));
      expect(offlineDb.unsyncedCount, equals(1));
    });

    test('partial sync failure marks only successful messages', () async {
      talon.syncIsEnabled = true;

      // Create two messages
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'First',
      );

      // Now fail subsequent sends
      serverDb.shouldFailSend = true;

      await talon.saveChange(
        table: 'todos',
        row: 'todo-2',
        column: 'name',
        value: 'Second - will fail',
      );

      // First should be synced, second should not
      expect(offlineDb.syncedCount, equals(1));
      expect(offlineDb.unsyncedCount, equals(1));
    });

    test('large number of concurrent changes', () async {
      final futures = <Future>[];

      for (int i = 0; i < 50; i++) {
        futures.add(talon.saveChange(
          table: 'todos',
          row: 'todo-$i',
          column: 'name',
          value: 'Todo $i',
        ));
      }

      await Future.wait(futures);

      expect(offlineDb.messageCount, equals(50));
    });

    test('very long value is preserved', () async {
      final longValue = 'A' * 10000;

      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: longValue,
      );

      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals(longValue));
    });
  });

  group('Talon - Data Isolation', () {
    test('different users do not see each others data', () async {
      talon.syncIsEnabled = true;

      // Message from different user
      serverDb.simulateServerMessage(Message(
        id: 'other-user-msg',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Other user data',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-2', // Different user
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await talon.syncFromServer();

      expect(offlineDb.messageCount, equals(0));
    });

    test('same user on different client sees data', () async {
      talon.syncIsEnabled = true;

      serverDb.simulateServerMessage(Message(
        id: 'same-user-msg',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Same user, different client',
        localTimestamp: HLC.now('client-2').toString(),
        userId: 'user-1', // Same user
        clientId: 'client-2', // Different client
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await talon.syncFromServer();

      expect(offlineDb.messageCount, equals(1));
      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals('Same user, different client'));
    });
  });
}
