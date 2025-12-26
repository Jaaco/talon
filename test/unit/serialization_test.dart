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

  group('Value Serialization', () {
    test('serializes null value', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: null,
      );

      final msg = offlineDb.messages.first;
      expect(msg.dataType, equals('null'));
      expect(msg.value, equals(''));
      expect(msg.typedValue, isNull);
    });

    test('serializes string value', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 'hello world',
      );

      final msg = offlineDb.messages.first;
      expect(msg.dataType, equals('string'));
      expect(msg.value, equals('hello world'));
      expect(msg.typedValue, equals('hello world'));
    });

    test('serializes int value', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 42,
      );

      final msg = offlineDb.messages.first;
      expect(msg.dataType, equals('int'));
      expect(msg.value, equals('42'));
      expect(msg.typedValue, equals(42));
    });

    test('serializes negative int', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: -123,
      );

      final msg = offlineDb.messages.first;
      expect(msg.typedValue, equals(-123));
    });

    test('serializes double value', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: 3.14159,
      );

      final msg = offlineDb.messages.first;
      expect(msg.dataType, equals('double'));
      expect(msg.typedValue, closeTo(3.14159, 0.00001));
    });

    test('serializes bool true', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: true,
      );

      final msg = offlineDb.messages.first;
      expect(msg.dataType, equals('bool'));
      expect(msg.value, equals('1'));
      expect(msg.typedValue, isTrue);
    });

    test('serializes bool false', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: false,
      );

      final msg = offlineDb.messages.first;
      expect(msg.dataType, equals('bool'));
      expect(msg.value, equals('0'));
      expect(msg.typedValue, isFalse);
    });

    test('serializes DateTime value', () async {
      final now = DateTime(2024, 1, 15, 10, 30, 45);
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: now,
      );

      final msg = offlineDb.messages.first;
      expect(msg.dataType, equals('datetime'));
      expect(msg.typedValue, equals(now));
    });

    test('serializes Map value as JSON', () async {
      final map = {'name': 'John', 'age': 30, 'active': true};
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: map,
      );

      final msg = offlineDb.messages.first;
      expect(msg.dataType, equals('json'));
      expect(msg.typedValue, equals(map));
    });

    test('serializes List value as JSON', () async {
      final list = [1, 2, 3, 'four', true];
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: list,
      );

      final msg = offlineDb.messages.first;
      expect(msg.dataType, equals('json'));
      expect(msg.typedValue, equals(list));
    });

    test('serializes nested JSON structures', () async {
      final nested = {
        'users': [
          {'name': 'Alice', 'scores': [90, 85, 92]},
          {'name': 'Bob', 'scores': [88, 91, 87]},
        ],
        'metadata': {'version': 1, 'active': true}
      };
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: nested,
      );

      final msg = offlineDb.messages.first;
      expect(msg.typedValue, equals(nested));
    });

    test('allows manual dataType override', () async {
      await talon.saveChange(
        table: 'test',
        row: 'row-1',
        column: 'value',
        value: '42',
        dataType: 'custom',
      );

      final msg = offlineDb.messages.first;
      expect(msg.dataType, equals('custom'));
      expect(msg.value, equals('42'));
    });
  });

  group('Message.typedValue edge cases', () {
    test('handles empty string with empty dataType', () {
      final msg = Message(
        id: 'test',
        table: 'test',
        row: 'row',
        column: 'col',
        dataType: '',
        value: '',
        localTimestamp: 'ts',
        userId: 'user',
        clientId: 'client',
        hasBeenApplied: false,
        hasBeenSynced: false,
      );

      expect(msg.typedValue, isNull);
    });

    test('handles non-empty string with empty dataType', () {
      final msg = Message(
        id: 'test',
        table: 'test',
        row: 'row',
        column: 'col',
        dataType: '',
        value: 'some value',
        localTimestamp: 'ts',
        userId: 'user',
        clientId: 'client',
        hasBeenApplied: false,
        hasBeenSynced: false,
      );

      expect(msg.typedValue, equals('some value'));
    });

    test('handles invalid int gracefully', () {
      final msg = Message(
        id: 'test',
        table: 'test',
        row: 'row',
        column: 'col',
        dataType: 'int',
        value: 'not a number',
        localTimestamp: 'ts',
        userId: 'user',
        clientId: 'client',
        hasBeenApplied: false,
        hasBeenSynced: false,
      );

      expect(msg.typedValue, equals(0));
    });

    test('handles invalid double gracefully', () {
      final msg = Message(
        id: 'test',
        table: 'test',
        row: 'row',
        column: 'col',
        dataType: 'double',
        value: 'invalid',
        localTimestamp: 'ts',
        userId: 'user',
        clientId: 'client',
        hasBeenApplied: false,
        hasBeenSynced: false,
      );

      expect(msg.typedValue, equals(0.0));
    });

    test('handles invalid JSON gracefully', () {
      final msg = Message(
        id: 'test',
        table: 'test',
        row: 'row',
        column: 'col',
        dataType: 'json',
        value: 'not valid json',
        localTimestamp: 'ts',
        userId: 'user',
        clientId: 'client',
        hasBeenApplied: false,
        hasBeenSynced: false,
      );

      expect(msg.typedValue, equals('not valid json'));
    });

    test('handles unknown dataType as string', () {
      final msg = Message(
        id: 'test',
        table: 'test',
        row: 'row',
        column: 'col',
        dataType: 'custom_type',
        value: 'some value',
        localTimestamp: 'ts',
        userId: 'user',
        clientId: 'client',
        hasBeenApplied: false,
        hasBeenSynced: false,
      );

      expect(msg.typedValue, equals('some value'));
    });

    test('bool accepts "true" string', () {
      final msg = Message(
        id: 'test',
        table: 'test',
        row: 'row',
        column: 'col',
        dataType: 'bool',
        value: 'true',
        localTimestamp: 'ts',
        userId: 'user',
        clientId: 'client',
        hasBeenApplied: false,
        hasBeenSynced: false,
      );

      expect(msg.typedValue, isTrue);
    });

    test('bool accepts "TRUE" string (case insensitive)', () {
      final msg = Message(
        id: 'test',
        table: 'test',
        row: 'row',
        column: 'col',
        dataType: 'bool',
        value: 'TRUE',
        localTimestamp: 'ts',
        userId: 'user',
        clientId: 'client',
        hasBeenApplied: false,
        hasBeenSynced: false,
      );

      expect(msg.typedValue, isTrue);
    });
  });
}
