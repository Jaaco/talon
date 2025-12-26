# Talon

A lightweight, dependency-free sync layer for building offline-first Flutter apps.

[![pub package](https://img.shields.io/pub/v/talon.svg)](https://pub.dev/packages/talon)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Features

- **Offline-first**: Changes are saved locally first, then synced when online
- **Conflict resolution**: Automatic last-write-wins using Hybrid Logical Clocks (HLC)
- **Backend agnostic**: Works with Supabase, Firebase, custom APIs, or any backend
- **Database agnostic**: Works with sqflite, Drift, Hive, or any local database
- **Zero dependencies**: No external packages required
- **Type-safe**: Full support for all Dart types with automatic serialization
- **Real-time**: Subscribe to server changes for live updates
- **Batched sync**: Efficient network usage with configurable batch sizes

## Quick Start

### Installation

```yaml
dependencies:
  talon: ^0.0.2
```

### Basic Usage

```dart
// 1. Create a Talon instance
final talon = Talon(
  userId: 'user-123',
  clientId: 'device-456',
  serverDatabase: myServerDb,      // Your ServerDatabase implementation
  offlineDatabase: myOfflineDb,    // Your OfflineDatabase implementation
  createNewIdFunction: () => uuid.v4(),
);

// 2. Enable sync
talon.syncIsEnabled = true;

// 3. Save changes - they're applied locally immediately and synced automatically
await talon.saveChange(
  table: 'todos',
  row: 'todo-1',
  column: 'name',
  value: 'Buy milk',  // Accepts any type: String, int, bool, DateTime, Map, List
);

// 4. Listen for changes (local and server)
talon.changes.listen((change) {
  if (change.affectsTable('todos')) {
    refreshTodoList();
  }
});

// 5. Clean up when done
talon.dispose();
```

## How It Works

Talon uses a **message-based sync** architecture. Every change is stored as a `Message` containing:

| Field | Description |
|-------|-------------|
| `table` | Which table was changed |
| `row` | Which row (primary key) |
| `column` | Which column/field |
| `value` | The new value |
| `localTimestamp` | HLC timestamp for conflict resolution |
| `userId` | Who made the change |
| `clientId` | Which device |

### Conflict Resolution

When the same cell (table/row/column) is modified on multiple devices, Talon uses **Hybrid Logical Clocks (HLC)** to determine which change wins:

```
Device A: Sets todo.name = "Buy groceries" at HLC 1000:0:device-a
Device B: Sets todo.name = "Buy milk" at HLC 1001:0:device-b
                                              ↑
                                    Later timestamp wins
Result: todo.name = "Buy milk"
```

HLC ensures correct ordering even when device clocks are out of sync.

## Implementation Guide

### 1. Implement OfflineDatabase

Create a class that extends `OfflineDatabase` to connect Talon to your local database:

```dart
class SqliteOfflineDatabase extends OfflineDatabase {
  final Database db;

  SqliteOfflineDatabase(this.db);

  @override
  Future<void> init() async {
    // Create the messages table
    await db.execute(TalonSchema.messagesTableSql);
    // Create your data tables...
  }

  @override
  Future<bool> applyMessageToLocalDataTable(Message message) async {
    await db.rawUpdate(
      'UPDATE ${message.table} SET ${message.column} = ? WHERE id = ?',
      [message.value, message.row],
    );
    return true;
  }

  @override
  Future<bool> applyMessageToLocalMessageTable(Message message) async {
    await db.insert('talon_messages', message.toMap());
    return true;
  }

  @override
  Future<String?> getExistingTimestamp({
    required String table,
    required String row,
    required String column,
  }) async {
    final result = await db.rawQuery('''
      SELECT local_timestamp FROM talon_messages
      WHERE table_name = ? AND row = ? AND "column" = ?
      ORDER BY local_timestamp DESC LIMIT 1
    ''', [table, row, column]);
    return result.isEmpty ? null : result.first['local_timestamp'] as String?;
  }

  @override
  Future<List<Message>> getUnsyncedMessages() async {
    final rows = await db.query('talon_messages',
      where: 'hasBeenSynced = 0');
    return rows.map((r) => Message.fromMap(r)).toList();
  }

  @override
  Future<void> markMessagesAsSynced(List<String> ids) async {
    await db.rawUpdate(
      'UPDATE talon_messages SET hasBeenSynced = 1 WHERE id IN (${ids.map((_) => '?').join(',')})',
      ids,
    );
  }

  @override
  Future<int?> readLastSyncedServerTimestamp() async {
    // Read from shared preferences or database
  }

  @override
  Future<void> saveLastSyncedServerTimestamp(int timestamp) async {
    // Save to shared preferences or database
  }
}
```

### 2. Implement ServerDatabase

Create a class that extends `ServerDatabase` to connect Talon to your backend:

```dart
class SupabaseServerDatabase extends ServerDatabase {
  final SupabaseClient supabase;

  SupabaseServerDatabase(this.supabase);

  @override
  Future<List<Message>> getMessagesFromServer({
    required int? lastSyncedServerTimestamp,
    required String clientId,
    required String userId,
  }) async {
    final response = await supabase
        .from('messages')
        .select()
        .eq('user_id', userId)
        .neq('client_id', clientId)  // Don't fetch own messages
        .gt('server_timestamp', lastSyncedServerTimestamp ?? 0)
        .order('server_timestamp');
    return response.map((row) => Message.fromMap(row)).toList();
  }

  @override
  Future<bool> sendMessageToServer({required Message message}) async {
    try {
      await supabase.from('messages').insert(message.toMap()
        ..remove('hasBeenApplied')
        ..remove('hasBeenSynced'));
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  StreamSubscription subscribeToServerMessages({
    required String clientId,
    required String userId,
    required int? lastSyncedServerTimestamp,
    required void Function(List<Message>) onMessagesReceived,
  }) {
    return supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .neq('client_id', clientId)
        .listen((rows) {
          final messages = rows.map((r) => Message.fromMap(r)).toList();
          onMessagesReceived(messages);
        });
  }
}
```

### 3. Database Schema

Use the provided schema helpers:

**SQLite (local):**
```dart
await db.execute(TalonSchema.messagesTableSql);
```

**PostgreSQL/Supabase (server):**
```sql
-- Run TalonSchema.messagesTablePostgres in Supabase SQL editor
-- Includes Row Level Security policies
```

## Advanced Usage

### Batch Saves

Save multiple changes atomically:

```dart
await talon.saveChanges([
  TalonChangeData(table: 'todos', row: id, column: 'name', value: 'New name'),
  TalonChangeData(table: 'todos', row: id, column: 'updated_at', value: DateTime.now()),
]);
```

### Configuration

Customize sync behavior:

```dart
final talon = Talon(
  // ... required params
  config: TalonConfig(
    batchSize: 50,                          // Messages per sync batch
    syncDebounce: Duration(milliseconds: 500), // Debounce rapid saves
    immediateSyncOnSave: false,             // Wait for debounce
  ),
);
```

### Periodic Sync

Enable background sync:

```dart
talon.startPeriodicSync(interval: Duration(minutes: 5));

// Later...
talon.stopPeriodicSync();
```

### Stream Filtering

Listen to specific change types:

```dart
// Only local changes
talon.localChanges.listen((change) { ... });

// Only server changes
talon.serverChanges.listen((change) { ... });

// Filter by table
talon.changes.listen((change) {
  if (change.affectsTable('todos')) {
    final todoMessages = change.forTable('todos');
    // Process todo changes
  }
});
```

## Philosophy

Talon is intentionally a **thin sync layer**, not an ORM. It handles:

- Message creation and storage
- Sync orchestration
- Conflict resolution

You handle:

- Database schema design
- Query building
- Data access patterns

This gives you full control and understanding of your data layer.

## Documentation

Full documentation available at [docs.page/jaaco/talon](https://docs.page/jaaco/talon)

## License

MIT License - see [LICENSE](LICENSE) for details.
