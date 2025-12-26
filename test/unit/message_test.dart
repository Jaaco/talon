import 'package:test/test.dart';
import 'package:talon/talon.dart';

void main() {
  group('Message', () {
    Message createTestMessage({
      String id = 'msg-123',
      String table = 'todos',
      String row = 'todo-1',
      String column = 'name',
      String dataType = 'string',
      String value = 'Buy milk',
      int? serverTimestamp = 42,
      String localTimestamp = '000001234567890:00000:client-1',
      String userId = 'user-1',
      String clientId = 'client-1',
      bool hasBeenApplied = true,
      bool hasBeenSynced = false,
    }) {
      return Message(
        id: id,
        table: table,
        row: row,
        column: column,
        dataType: dataType,
        value: value,
        serverTimestamp: serverTimestamp,
        localTimestamp: localTimestamp,
        userId: userId,
        clientId: clientId,
        hasBeenApplied: hasBeenApplied,
        hasBeenSynced: hasBeenSynced,
      );
    }

    test('toMap and fromMap roundtrip preserves all fields', () {
      final message = createTestMessage();

      final map = message.toMap();
      final restored = Message.fromMap(map);

      expect(restored.id, equals(message.id));
      expect(restored.table, equals(message.table));
      expect(restored.row, equals(message.row));
      expect(restored.column, equals(message.column));
      expect(restored.dataType, equals(message.dataType));
      expect(restored.value, equals(message.value));
      expect(restored.serverTimestamp, equals(message.serverTimestamp));
      expect(restored.localTimestamp, equals(message.localTimestamp));
      expect(restored.userId, equals(message.userId));
      expect(restored.clientId, equals(message.clientId));
      expect(restored.hasBeenApplied, equals(message.hasBeenApplied));
      expect(restored.hasBeenSynced, equals(message.hasBeenSynced));
    });

    test('toMap handles null serverTimestamp', () {
      final message = createTestMessage(serverTimestamp: null);

      final map = message.toMap();
      final restored = Message.fromMap(map);

      expect(restored.serverTimestamp, isNull);
    });

    test('toJson and fromJson roundtrip preserves all fields', () {
      final message = createTestMessage();

      final json = message.toJson();
      final restored = Message.fromJson(json);

      expect(restored, equals(message));
    });

    test('copyWith creates new instance with updated fields', () {
      final original = createTestMessage();
      final updated = original.copyWith(value: 'New value', hasBeenSynced: true);

      expect(updated.value, equals('New value'));
      expect(updated.hasBeenSynced, isTrue);
      expect(updated.id, equals(original.id));
      expect(updated.table, equals(original.table));
      // Original unchanged
      expect(original.value, equals('Buy milk'));
      expect(original.hasBeenSynced, isFalse);
    });

    test('copyWith with no arguments returns equal message', () {
      final original = createTestMessage();
      final copy = original.copyWith();

      expect(copy, equals(original));
      expect(identical(copy, original), isFalse);
    });

    test('equality works correctly', () {
      final m1 = createTestMessage();
      final m2 = createTestMessage();
      final m3 = createTestMessage(id: 'different-id');

      expect(m1, equals(m2));
      expect(m1, isNot(equals(m3)));
    });

    test('hashCode is consistent with equality', () {
      final m1 = createTestMessage();
      final m2 = createTestMessage();

      expect(m1.hashCode, equals(m2.hashCode));
    });

    test('toString returns readable representation', () {
      final message = createTestMessage();
      final str = message.toString();

      expect(str, contains('Message'));
      expect(str, contains('msg-123'));
      expect(str, contains('todos'));
    });

    test('hasBeenApplied and hasBeenSynced are stored as integers in map', () {
      final message = createTestMessage(hasBeenApplied: true, hasBeenSynced: false);
      final map = message.toMap();

      expect(map['hasBeenApplied'], equals(1));
      expect(map['hasBeenSynced'], equals(0));
    });

    test('fromMap correctly interprets integer booleans', () {
      final map = {
        'id': 'test',
        'table_name': 'todos',
        'row': 'row-1',
        'column': 'name',
        'data_type': 'string',
        'value': 'test value',
        'server_timestamp': null,
        'local_timestamp': '000001234567890:00000:node',
        'user_id': 'user-1',
        'client_id': 'client-1',
        'hasBeenApplied': 1,
        'hasBeenSynced': 0,
      };

      final message = Message.fromMap(map);

      expect(message.hasBeenApplied, isTrue);
      expect(message.hasBeenSynced, isFalse);
    });
  });
}
