import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:talon/dart_offlne_first.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart';

// todo(jacoo): user must provide a function that maps Message type dynamic to sql string type maybe
// actually, maps the String 'dataType' to a function that maps the value to it's type before it can
// be inserted into the local values database. Hopefully this is redundant in most cases
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
      await localDb.insert('messages', messageMap);

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
      ''',
    );

    final castMessages = messagesRaw.map(Message.fromMap);

    return castMessages.toList();
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

  Future<void> createTables(Database db) async {
    await db.execute('''
        DROP TABLE IF EXISTS books;
        ''');

    await db.execute('''
        DROP TABLE IF EXISTS messages;
        ''');

    await db.execute('''
        CREATE TABLE books (
          id TEXT PRIMARY KEY,
          name TEXT DEFAULT '',
          pages INTEGER DEFAULT 0,
          imageUrl TEXT
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
