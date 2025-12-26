import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart';
import 'package:talon/talon.dart';

/// Example implementation of [OfflineDatabase] using sqflite.
///
/// This demonstrates how to implement the required methods for Talon.
/// Note: Conflict resolution is handled automatically by the base class -
/// you only need to implement [getExistingTimestamp].
class MyOfflineDB extends OfflineDatabase {
  late final Database localDb;

  @override
  Future<void> init() async {
    final databasePath = await getDatabasesPath();

    final dbPath = join(databasePath, 'example_app.db');

    localDb = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        createTables(db);
      },
    );
  }

  /// Apply a message to the data table.
  ///
  /// Note: You don't need to check shouldApplyMessage() here - the base class
  /// handles conflict resolution before calling this method.
  @override
  Future<bool> applyMessageToLocalDataTable(Message message) async {
    try {
      // Use a transaction to ensure atomicity
      await localDb.transaction((txn) async {
        // First, try to update the row
        int updatedRows = await txn.rawUpdate(
          '''
        UPDATE ${message.table}
        SET ${message.column} = ?
        WHERE id = ?;
        ''',
          [message.value, message.row],
        );

        // If no rows were updated, insert a new row
        if (updatedRows == 0) {
          await txn.rawInsert(
            '''
          INSERT INTO ${message.table} (id, ${message.column})
          VALUES (?, ?);
          ''',
            [message.row, message.value],
          );
        }
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> applyMessageToLocalMessageTable(Message message) async {
    final messageMap = message.toMap();

    try {
      await localDb.insert(
        'messages',
        messageMap,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<List<Message>> getUnsyncedMessages() async {
    final messagesRaw = await localDb.rawQuery(
      '''
        SELECT *
        FROM messages
        WHERE hasBeenSynced = 0
      ''',
    );

    return messagesRaw.map(Message.fromMap).toList();
  }

  @override
  Future<void> markMessagesAsSynced(List<String> syncedMessageIds) async {
    // todo(jacoo): use constants in query strings for field names
    final placeholders = List.filled(syncedMessageIds.length, '?').join(', ');

    final query = '''
      UPDATE messages
      SET hasBeenSynced = 1
      WHERE id IN ($placeholders);
    ''';

    await localDb.rawUpdate(query, syncedMessageIds);
  }

  @override
  Future<int?> readLastSyncedServerTimestamp() async {
    final sharedPrefs = await SharedPreferences.getInstance();

    final timestamp = sharedPrefs.getInt('last_synced_server_timestamp');

    return timestamp;
  }

  @override
  Future<void> saveLastSyncedServerTimestamp(int serverTimestamp) async {
    final sharedPrefs = await SharedPreferences.getInstance();

    sharedPrefs.setInt('last_synced_server_timestamp', serverTimestamp);
  }

  /// Get the existing timestamp for a specific cell.
  ///
  /// This is used by the base class for conflict resolution.
  /// Returns the most recent HLC timestamp for the given table/row/column.
  @override
  Future<String?> getExistingTimestamp({
    required String table,
    required String row,
    required String column,
  }) async {
    try {
      final result = await localDb.rawQuery(
        '''
        SELECT local_timestamp
        FROM messages
        WHERE table_name = ? AND row = ? AND "column" = ?
        ORDER BY local_timestamp DESC
        LIMIT 1;
        ''',
        [table, row, column],
      );

      if (result.isEmpty) return null;
      return result.first['local_timestamp'] as String?;
    } catch (e) {
      return null;
    }
  }

  Future<void> createTables(Database db) async {
    await db.execute('''
        DROP TABLE IF EXISTS todos;
        ''');

    await db.execute('''
        DROP TABLE IF EXISTS books;
        ''');

    await db.execute('''
        DROP TABLE IF EXISTS messages;
        ''');

    await db.execute('''
        CREATE TABLE todos (
          id TEXT PRIMARY KEY,
          name TEXT DEFAULT '',
          is_done BOOLEAN DEFAULT 0
        );
      ''');

    await db.execute('''
      CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    table_name TEXT NOT NULL,
    row TEXT NOT NULL,
    column TEXT NOT NULL,
    data_type TEXT NOT NULL,
    value TEXT NOT NULL,
    server_timestamp INTEGER,
    local_timestamp TEXT NOT NULL,
    user_id TEXT NOT NULL,
    client_id TEXT NOT NULL,
    hasBeenApplied BOOLEAN NOT NULL CHECK (hasBeenApplied IN (0, 1)),
    hasBeenSynced BOOLEAN NOT NULL CHECK (hasBeenSynced IN (0, 1))
);
     ''');
  }

  void resetDatabase() async {
    createTables(localDb);

    saveLastSyncedServerTimestamp(-1);
  }

  Future<List<Map<String, Object?>>> runQuery(String query) async {
    return await localDb.rawQuery(query);
  }
}
