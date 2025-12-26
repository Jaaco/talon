import 'package:test/test.dart';
import 'package:talon/talon.dart';

import '../mocks/mock_offline_database.dart';

void main() {
  late MockOfflineDatabase db;

  setUp(() {
    db = MockOfflineDatabase();
  });

  tearDown(() {
    db.clear();
  });

  Message createMessage({
    String id = 'msg-1',
    String table = 'todos',
    String row = 'row-1',
    String column = 'name',
    String value = 'Test value',
    String? localTimestamp,
    String clientId = 'client-1',
    String userId = 'user-1',
    int? serverTimestamp,
    bool hasBeenApplied = false,
    bool hasBeenSynced = false,
  }) {
    return Message(
      id: id,
      table: table,
      row: row,
      column: column,
      dataType: 'string',
      value: value,
      localTimestamp: localTimestamp ?? HLC.now(clientId).toString(),
      clientId: clientId,
      userId: userId,
      serverTimestamp: serverTimestamp,
      hasBeenApplied: hasBeenApplied,
      hasBeenSynced: hasBeenSynced,
    );
  }

  group('OfflineDatabase - shouldApplyMessage', () {
    test('returns true when no existing message exists', () async {
      final message = createMessage();

      final shouldApply = await db.shouldApplyMessage(message);

      expect(shouldApply, isTrue);
    });

    test('returns true when incoming message has higher timestamp', () async {
      // Store an earlier message
      final earlier = createMessage(
        localTimestamp: HLC(timestamp: 1000, count: 0, node: 'a').toString(),
      );
      await db.applyMessageToLocalMessageTable(earlier);

      // Try to apply a later message
      final later = createMessage(
        id: 'msg-2',
        localTimestamp: HLC(timestamp: 2000, count: 0, node: 'a').toString(),
      );

      final shouldApply = await db.shouldApplyMessage(later);

      expect(shouldApply, isTrue);
    });

    test('returns false when incoming message has lower timestamp', () async {
      // Store a later message
      final later = createMessage(
        localTimestamp: HLC(timestamp: 2000, count: 0, node: 'a').toString(),
      );
      await db.applyMessageToLocalMessageTable(later);

      // Try to apply an earlier message
      final earlier = createMessage(
        id: 'msg-2',
        localTimestamp: HLC(timestamp: 1000, count: 0, node: 'a').toString(),
      );

      final shouldApply = await db.shouldApplyMessage(earlier);

      expect(shouldApply, isFalse);
    });

    test('returns false when timestamps are equal (existing wins ties)', () async {
      final timestamp = HLC(timestamp: 1000, count: 0, node: 'a').toString();

      final existing = createMessage(localTimestamp: timestamp);
      await db.applyMessageToLocalMessageTable(existing);

      final incoming = createMessage(id: 'msg-2', localTimestamp: timestamp);

      final shouldApply = await db.shouldApplyMessage(incoming);

      expect(shouldApply, isFalse);
    });

    test('uses count as tiebreaker when timestamps equal', () async {
      // Store message with lower count
      final lower = createMessage(
        localTimestamp: HLC(timestamp: 1000, count: 0, node: 'a').toString(),
      );
      await db.applyMessageToLocalMessageTable(lower);

      // Try to apply message with higher count (should win)
      final higher = createMessage(
        id: 'msg-2',
        localTimestamp: HLC(timestamp: 1000, count: 5, node: 'a').toString(),
      );

      final shouldApply = await db.shouldApplyMessage(higher);

      expect(shouldApply, isTrue);
    });

    test('uses node as final tiebreaker', () async {
      // Store message with node 'z'
      final nodeZ = createMessage(
        localTimestamp: HLC(timestamp: 1000, count: 0, node: 'zzz').toString(),
      );
      await db.applyMessageToLocalMessageTable(nodeZ);

      // Try to apply message with node 'a' (lexicographically less, should lose)
      final nodeA = createMessage(
        id: 'msg-2',
        localTimestamp: HLC(timestamp: 1000, count: 0, node: 'aaa').toString(),
      );

      final shouldApply = await db.shouldApplyMessage(nodeA);

      expect(shouldApply, isFalse);
    });

    test('only compares messages for same table/row/column', () async {
      // Store message for column 'name'
      final nameMessage = createMessage(
        column: 'name',
        localTimestamp: HLC(timestamp: 2000, count: 0, node: 'a').toString(),
      );
      await db.applyMessageToLocalMessageTable(nameMessage);

      // Apply message for different column - should succeed even with earlier timestamp
      final descMessage = createMessage(
        id: 'msg-2',
        column: 'description',
        localTimestamp: HLC(timestamp: 1000, count: 0, node: 'a').toString(),
      );

      final shouldApply = await db.shouldApplyMessage(descMessage);

      expect(shouldApply, isTrue);
    });

    test('compares against most recent message for cell', () async {
      // Store multiple messages for same cell
      final first = createMessage(
        id: 'msg-1',
        localTimestamp: HLC(timestamp: 1000, count: 0, node: 'a').toString(),
      );
      final second = createMessage(
        id: 'msg-2',
        localTimestamp: HLC(timestamp: 3000, count: 0, node: 'a').toString(),
      );
      final third = createMessage(
        id: 'msg-3',
        localTimestamp: HLC(timestamp: 2000, count: 0, node: 'a').toString(),
      );

      await db.applyMessageToLocalMessageTable(first);
      await db.applyMessageToLocalMessageTable(second);
      await db.applyMessageToLocalMessageTable(third);

      // Incoming at 2500 should lose to the 3000 message
      final incoming = createMessage(
        id: 'msg-4',
        localTimestamp: HLC(timestamp: 2500, count: 0, node: 'a').toString(),
      );

      final shouldApply = await db.shouldApplyMessage(incoming);

      expect(shouldApply, isFalse);
    });
  });

  group('OfflineDatabase - saveMessageFromServer', () {
    test('saves message to message table', () async {
      final message = createMessage(serverTimestamp: 1);

      await db.saveMessageFromServer(message);

      expect(db.messageCount, equals(1));
    });

    test('applies message to data table when no existing value', () async {
      final message = createMessage(serverTimestamp: 1, value: 'New value');

      await db.saveMessageFromServer(message);

      expect(db.getValue('todos', 'row-1', 'name'), equals('New value'));
    });

    test('applies message when newer than existing', () async {
      // Store an older message
      final older = createMessage(
        localTimestamp: HLC(timestamp: 1000, count: 0, node: 'a').toString(),
        value: 'Old value',
      );
      await db.saveMessageFromServer(older);

      // Apply newer message
      final newer = createMessage(
        id: 'msg-2',
        localTimestamp: HLC(timestamp: 2000, count: 0, node: 'a').toString(),
        value: 'New value',
        serverTimestamp: 2,
      );
      await db.saveMessageFromServer(newer);

      expect(db.getValue('todos', 'row-1', 'name'), equals('New value'));
    });

    test('does not apply message when older than existing', () async {
      // Store a newer message
      final newer = createMessage(
        localTimestamp: HLC(timestamp: 2000, count: 0, node: 'a').toString(),
        value: 'Newer value',
      );
      await db.saveMessageFromServer(newer);

      // Try to apply older message
      final older = createMessage(
        id: 'msg-2',
        localTimestamp: HLC(timestamp: 1000, count: 0, node: 'a').toString(),
        value: 'Old value',
        serverTimestamp: 2,
      );
      await db.saveMessageFromServer(older);

      // Value should remain from newer message
      expect(db.getValue('todos', 'row-1', 'name'), equals('Newer value'));
      // But both messages should be in the message table
      expect(db.messageCount, equals(2));
    });

    test('still stores message in message table even when not applied', () async {
      // Store newer message
      final newer = createMessage(
        localTimestamp: HLC(timestamp: 2000, count: 0, node: 'a').toString(),
      );
      await db.saveMessageFromServer(newer);

      // Older message should still be stored for history
      final older = createMessage(
        id: 'msg-2',
        localTimestamp: HLC(timestamp: 1000, count: 0, node: 'a').toString(),
        serverTimestamp: 2,
      );
      await db.saveMessageFromServer(older);

      expect(db.messageCount, equals(2));
    });
  });

  group('OfflineDatabase - saveMessagesFromServer', () {
    test('saves multiple messages', () async {
      final messages = [
        createMessage(id: 'msg-1', row: 'row-1', serverTimestamp: 1),
        createMessage(id: 'msg-2', row: 'row-2', serverTimestamp: 2),
        createMessage(id: 'msg-3', row: 'row-3', serverTimestamp: 3),
      ];

      await db.saveMessagesFromServer(messages);

      expect(db.messageCount, equals(3));
    });

    test('updates last synced timestamp to highest value', () async {
      final messages = [
        createMessage(id: 'msg-1', serverTimestamp: 5),
        createMessage(id: 'msg-2', serverTimestamp: 10),
        createMessage(id: 'msg-3', serverTimestamp: 3),
      ];

      await db.saveMessagesFromServer(messages);

      final lastSynced = await db.readLastSyncedServerTimestamp();
      expect(lastSynced, equals(10));
    });

    test('does not update timestamp if all messages have null serverTimestamp', () async {
      await db.saveLastSyncedServerTimestamp(5);

      final messages = [
        createMessage(id: 'msg-1', serverTimestamp: null),
        createMessage(id: 'msg-2', serverTimestamp: null),
      ];

      await db.saveMessagesFromServer(messages);

      final lastSynced = await db.readLastSyncedServerTimestamp();
      expect(lastSynced, equals(5));
    });

    test('handles empty message list', () async {
      await db.saveLastSyncedServerTimestamp(5);

      await db.saveMessagesFromServer([]);

      final lastSynced = await db.readLastSyncedServerTimestamp();
      expect(lastSynced, equals(5));
    });
  });

  group('OfflineDatabase - saveMessageFromLocalChange', () {
    test('applies to data table first, then message table', () async {
      final message = createMessage(value: 'Local change');

      final result = await db.saveMessageFromLocalChange(message);

      expect(result, isTrue);
      expect(db.getValue('todos', 'row-1', 'name'), equals('Local change'));
      expect(db.messageCount, equals(1));
    });
  });

  group('OfflineDatabase - getExistingTimestamp', () {
    test('returns null when no messages exist', () async {
      final timestamp = await db.getExistingTimestamp(
        table: 'todos',
        row: 'row-1',
        column: 'name',
      );

      expect(timestamp, isNull);
    });

    test('returns most recent timestamp for cell', () async {
      final first = HLC(timestamp: 1000, count: 0, node: 'a').toString();
      final second = HLC(timestamp: 2000, count: 0, node: 'a').toString();
      final third = HLC(timestamp: 1500, count: 0, node: 'a').toString();

      await db.applyMessageToLocalMessageTable(
        createMessage(id: 'msg-1', localTimestamp: first),
      );
      await db.applyMessageToLocalMessageTable(
        createMessage(id: 'msg-2', localTimestamp: second),
      );
      await db.applyMessageToLocalMessageTable(
        createMessage(id: 'msg-3', localTimestamp: third),
      );

      final timestamp = await db.getExistingTimestamp(
        table: 'todos',
        row: 'row-1',
        column: 'name',
      );

      expect(timestamp, equals(second));
    });
  });
}
