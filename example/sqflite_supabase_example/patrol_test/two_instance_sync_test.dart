import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:talon/talon.dart';
import 'package:uuid/uuid.dart';

import 'package:sqflite_supabase_example/main.dart' as app;
import 'package:sqflite_supabase_example/talon_implementation/server_database_implementation.dart';

/// Integration test: two-client CRUD sync via Supabase.
///
/// Client A runs as the full Flutter app (UI interactions via Patrol).
/// Client B is a headless Talon instance with a different clientId that
/// reads from the same Supabase backend, verifying that sync propagates
/// creates, updates, and deletes across independent clients.
///
/// Prerequisites:
///   - Real Supabase project with `messages` table
///   - Run with:
///       patrol test --device chrome \
///         --dart-define=SUPABASE_URL=<url> \
///         --dart-define=SUPABASE_ANON_KEY=<key>
void main() {
  late _ClientB clientB;

  patrolTest(
    'two-client CRUD sync: create, toggle done, delete',
    ($) async {
      // ── Setup ──────────────────────────────────────────────────
      final todoTitle =
          'sync-test-todo-${DateTime.now().millisecondsSinceEpoch}';

      // Start Client A (the full app).
      app.main();
      await $.pumpAndSettle();

      // Initialize Client B (headless, different clientId).
      clientB = await _ClientB.create();

      // ── Step 1: Client A creates a todo ────────────────────────
      // Enter the todo title in the input field and tap Add.
      final inputFields = find.byType(EditableText);
      await $.tester.enterText(inputFields.first, todoTitle);
      await $.pumpAndSettle();
      await $('Add').tap();
      await $.pumpAndSettle();

      // Verify it shows locally.
      expect($(todoTitle), findsOneWidget);

      // ── Step 2: Client A syncs to server ───────────────────────
      await $('Sync from server').tap();
      await $.pumpAndSettle();
      await _waitForSync();

      // ── Step 3: Client B syncs and verifies the todo exists ────
      await clientB.sync();
      final todosAfterCreate = await clientB.getTodos();
      final created = todosAfterCreate.where((t) => t['name'] == todoTitle);
      expect(created, isNotEmpty,
          reason: 'Client B should see the todo after sync');
      final todoId = created.first['id'] as String;
      expect(created.first['is_done'], anyOf(0, false),
          reason: 'New todo should not be done');

      // ── Step 4: Client A toggles the todo done ─────────────────
      final todoText = find.text(todoTitle);
      final todoRow = find.ancestor(
        of: todoText,
        matching: find.byType(Row),
      );

      // The first InkWell/GestureDetector in the row should be the checkbox.
      if (todoRow.evaluate().isNotEmpty) {
        // Tap the checkbox icon area (it's before the text in the row).
        final checkboxes = find.descendant(
          of: todoRow.first,
          matching: find.byWidgetPredicate(
            (w) => w is GestureDetector || w is InkWell,
          ),
        );
        if (checkboxes.evaluate().isNotEmpty) {
          await $.tester.tap(checkboxes.first);
          await $.pumpAndSettle();
        }
      }

      // ── Step 5: Client A syncs the toggle ──────────────────────
      await $('Sync from server').tap();
      await $.pumpAndSettle();
      await _waitForSync();

      // ── Step 6: Client B syncs and verifies todo is done ───────
      await clientB.sync();
      final todosAfterToggle = await clientB.getTodos();
      final toggled =
          todosAfterToggle.firstWhere((t) => t['id'] == todoId);
      expect(toggled['is_done'], anyOf(1, true, '1'),
          reason: 'Client B should see the todo as done after sync');

      // ── Step 7: Client A deletes the todo ──────────────────────
      // Find the delete icon button for our todo.
      final deleteButtons = find.descendant(
        of: todoRow.evaluate().isNotEmpty ? todoRow.first : todoText,
        matching: find.byIcon(Icons.delete_outline),
      );
      if (deleteButtons.evaluate().isNotEmpty) {
        await $.tester.tap(deleteButtons.first);
        await $.pumpAndSettle();
      }

      // ── Step 8: Client A syncs the deletion ────────────────────
      await $('Sync from server').tap();
      await $.pumpAndSettle();
      await _waitForSync();

      // ── Step 9: Client B syncs and verifies todo is gone ───────
      await clientB.sync();
      final todosAfterDelete = await clientB.getTodos();
      final deleted = todosAfterDelete.where(
        (t) => t['id'] == todoId && t['name'] != '__deleted__',
      );
      expect(deleted, isEmpty,
          reason:
              'Client B should not see the todo (or it should be tombstoned)');

      // ── Cleanup ────────────────────────────────────────────────
      await clientB.dispose();
    },
  );
}

/// Allow server time to persist and propagate changes.
Future<void> _waitForSync() async {
  await Future<void>.delayed(const Duration(seconds: 3));
}

/// A headless "second client" backed by its own Talon + sqflite instance.
///
/// Uses a separate database file and a distinct clientId so that Supabase
/// returns messages created by Client A.
class _ClientB {
  final Talon talon;
  final Database db;

  _ClientB._(this.talon, this.db);

  static Future<_ClientB> create() async {
    final databasePath = await getDatabasesPath();
    final dbPath = p.join(databasePath, 'client_b_test.db');

    // Delete any leftover DB from a prior run.
    await deleteDatabase(dbPath);

    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
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
            "column" TEXT NOT NULL,
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
      },
    );

    final offlineDb = _ClientBOfflineDB(db);
    final serverDb = MyServerDatabaseImplementation();
    const uuid = Uuid();

    final talon = Talon(
      userId: 'user_1',
      clientId: 'client-b-${uuid.v4()}',
      serverDatabase: serverDb,
      offlineDatabase: offlineDb,
      createNewIdFunction: () => uuid.v4(),
    );

    return _ClientB._(talon, db);
  }

  Future<void> sync() async {
    await talon.syncFromServer();
  }

  Future<List<Map<String, Object?>>> getTodos() async {
    return db.rawQuery('SELECT * FROM todos');
  }

  Future<void> dispose() async {
    talon.dispose();
    await db.close();
  }
}

/// Minimal OfflineDatabase implementation for Client B.
class _ClientBOfflineDB extends OfflineDatabase {
  final Database db;

  _ClientBOfflineDB(this.db);

  @override
  Future<void> init() async {
    // Already initialized in _ClientB.create().
  }

  @override
  Future<bool> applyMessageToLocalDataTable(Message message) async {
    try {
      await db.transaction((txn) async {
        final updated = await txn.rawUpdate(
          'UPDATE ${message.table} SET ${message.column} = ? WHERE id = ?',
          [message.value, message.row],
        );
        if (updated == 0) {
          await txn.rawInsert(
            'INSERT INTO ${message.table} (id, ${message.column}) VALUES (?, ?)',
            [message.row, message.value],
          );
        }
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> applyMessageToLocalMessageTable(Message message) async {
    try {
      await db.insert('messages', message.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<Message>> getUnsyncedMessages() async {
    final rows =
        await db.rawQuery('SELECT * FROM messages WHERE hasBeenSynced = 0');
    return rows.map(Message.fromMap).toList();
  }

  @override
  Future<void> markMessagesAsSynced(List<String> ids) async {
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE messages SET hasBeenSynced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  @override
  Future<int?> readLastSyncedServerTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('client_b_last_synced_server_timestamp');
  }

  @override
  Future<void> saveLastSyncedServerTimestamp(int serverTimestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        'client_b_last_synced_server_timestamp', serverTimestamp);
  }

  @override
  Future<String?> getExistingTimestamp({
    required String table,
    required String row,
    required String column,
  }) async {
    try {
      final result = await db.rawQuery(
        '''SELECT local_timestamp FROM messages
           WHERE table_name = ? AND row = ? AND "column" = ?
           ORDER BY local_timestamp DESC LIMIT 1''',
        [table, row, column],
      );
      if (result.isEmpty) return null;
      return result.first['local_timestamp'] as String?;
    } catch (_) {
      return null;
    }
  }
}
