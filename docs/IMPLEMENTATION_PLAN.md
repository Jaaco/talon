# Talon Implementation Plan

> **Philosophy:** Talon is a thin sync layer, not an ORM. It handles writes, accepts server data deterministically, and notifies about changes. The developer owns their database, schema, and queries.

---

## Table of Contents

1. [Overview](#overview)
2. [Phase 1: Critical Bug Fixes](#phase-1-critical-bug-fixes)
3. [Phase 2: HLC Integration](#phase-2-hlc-integration)
4. [Phase 3: API Improvements](#phase-3-api-improvements)
5. [Phase 4: Internalize Conflict Resolution](#phase-4-internalize-conflict-resolution)
6. [Phase 5: Developer Experience](#phase-5-developer-experience)
7. [Phase 6: Testing & Validation](#phase-6-testing--validation)
8. [File-by-File Changes](#file-by-file-changes)
9. [Migration Guide](#migration-guide)

---

## Overview

### Current State
- Version: 0.0.2
- Core sync loop: Functional but incomplete
- HLC: Implemented but not integrated
- Tests: None
- Critical bugs: Several

### Target State
- Version: 1.0.0
- Core sync loop: Complete and reliable
- HLC: Fully integrated for deterministic conflict resolution
- Tests: Comprehensive coverage
- API: Clean, minimal, focused

### Guiding Principles

1. **Stay in scope** - Sync layer only, not an ORM
2. **Remove footguns** - Developers shouldn't implement CRDT logic
3. **Finish what's started** - HLC exists, wire it up
4. **Fix before adding** - Bug fixes before new features
5. **Document by example** - Recommend setups, don't own them

---

## Phase 1: Critical Bug Fixes

**Priority:** Immediate
**Estimated complexity:** Low

### 1.1 Fix Missing `await` Statements

**File:** `lib/src/offline_database/offline_database.dart`

```dart
// Lines 28, 34: Missing await in saveMessageFromServer()
Future<bool> saveMessageFromServer(Message message) async {
  try {
    await applyMessageToLocalMessageTable(message);  // Add await
  } catch (e) {
    return Future.value(false);
  }

  try {
    await applyMessageToLocalDataTable(message);     // Add await
  } catch (e) {
    // Intentionally continue - message is saved even if apply fails
  }

  return Future.value(true);
}

// Lines 73, 79: Missing await in saveMessageFromLocalChange()
Future<bool> saveMessageFromLocalChange(Message message) async {
  try {
    await applyMessageToLocalDataTable(message);      // Add await
  } catch (e) {
    return Future.value(false);
  }

  try {
    await applyMessageToLocalMessageTable(message);   // Add await
  } catch (e) {
    return Future.value(false);
  }

  return Future.value(true);
}
```

### 1.2 Call `markMessagesAsSynced()` After Successful Sync

**File:** `lib/src/talon/talon.dart`

```dart
// Current: successfullySyncedMessages is collected but never used
Future<void> syncToServer() async {
  if (!_syncIsEnabled) return;

  final unsyncedMessages = await _offlineDatabase.getUnsyncedMessages();
  final successfullySyncedMessages = <String>[];

  for (final message in unsyncedMessages) {
    final wasSuccessful =
        await _serverDatabase.sendMessageToServer(message: message);

    if (wasSuccessful) {
      successfullySyncedMessages.add(message.id);
    }
  }

  // ADD THIS: Actually mark messages as synced
  if (successfullySyncedMessages.isNotEmpty) {
    await _offlineDatabase.markMessagesAsSynced(successfullySyncedMessages);
  }
}
```

### 1.3 Fix `getUnsyncedMessages()` Query

**File:** `example/.../offline_database_implementation.dart`

The current implementation returns ALL messages, not just unsynced ones:

```dart
// Current (wrong): Returns all messages
@override
Future<List<Message>> getUnsyncedMessages() async {
  final messagesRaw = await localDb.rawQuery('''
    SELECT * FROM messages
  ''');
  // ...
}

// Fixed: Only return unsynced messages
@override
Future<List<Message>> getUnsyncedMessages() async {
  final messagesRaw = await localDb.rawQuery('''
    SELECT * FROM messages WHERE hasBeenSynced = 0
  ''');
  // ...
}
```

### 1.4 Fix `runSync()` - Missing `await`

**File:** `lib/src/talon/talon.dart`

```dart
// Current: Doesn't await, completer is pointless
Future<void> runSync() async {
  final completer = Completer<void>();
  syncToServer();      // Not awaited!
  syncFromServer();    // Not awaited!
  completer.complete();
}

// Fixed: Proper sequential sync
Future<void> runSync() async {
  await syncToServer();
  await syncFromServer();
}
```

---

## Phase 2: HLC Integration

**Priority:** High
**Estimated complexity:** Medium

### 2.1 Add HLC State to Talon Class

**File:** `lib/src/talon/talon.dart`

```dart
import '../hybrid_logical_clock/hlc.dart';
import '../hybrid_logical_clock/hlc.state.dart';

class Talon {
  // Existing fields...

  late final HLCState _hlcState;

  Talon({
    required this.userId,
    required this.clientId,
    // ...
  }) {
    // ... existing init

    // Initialize HLC with clientId as node identifier
    _hlcState = HLCState(clientId);
  }
}
```

### 2.2 Use HLC for Local Timestamps

**File:** `lib/src/talon/talon.dart`

```dart
Future<void> saveChange({
  required String table,
  required String row,
  required String column,
  required String value,
  String dataType = '',
}) async {
  // Generate HLC timestamp for this event
  final hlcTimestamp = _hlcState.send();

  final message = Message(
    id: _createNewIdFunction(),
    table: table,
    row: row,
    column: column,
    dataType: dataType,
    value: value,
    localTimestamp: hlcTimestamp.toString(),  // HLC instead of DateTime.now()
    userId: userId,
    clientId: clientId,
    hasBeenApplied: false,
    hasBeenSynced: false,
  );

  await _offlineDatabase.saveMessageFromLocalChange(message);
  await syncToServer();
}
```

### 2.3 Update HLC on Receiving Server Messages

**File:** `lib/src/talon/talon.dart`

```dart
void subscribeToServerMessages() async {
  _serverMessagesSubscription?.cancel();

  final lastSyncedServerTimestamp =
      await _offlineDatabase.readLastSyncedServerTimestamp();

  _serverMessagesSubscription = _serverDatabase.subscribeToServerMessages(
    clientId: clientId,
    userId: userId,
    lastSyncedServerTimestamp: lastSyncedServerTimestamp,
    onMessagesReceived: (List<Message> messages) async {
      // Update HLC based on received messages
      for (final message in messages) {
        final receivedHlc = HLC.parse(message.localTimestamp);
        if (receivedHlc != null) {
          _hlcState.receive(receivedHlc);
        }
      }

      await _offlineDatabase.saveMessagesFromServer(messages);
      _onMessagesReceived?.call(messages);
    },
  );
}
```

### 2.4 Add HLC Parsing Utility

**File:** `lib/src/hybrid_logical_clock/hlc.dart`

```dart
class HLC implements Comparable<HLC> {
  // ... existing code ...

  /// Parse an HLC from its string representation
  /// Returns null if parsing fails
  static HLC? parse(String packed) {
    try {
      return HLCUtils('').unpack(packed);
    } catch (e) {
      return null;
    }
  }

  /// Compare two HLC timestamp strings
  /// Returns: negative if a < b, zero if a == b, positive if a > b
  static int compareStrings(String a, String b) {
    final hlcA = parse(a);
    final hlcB = parse(b);

    if (hlcA == null && hlcB == null) return 0;
    if (hlcA == null) return -1;
    if (hlcB == null) return 1;

    return hlcA.compareTo(hlcB);
  }
}
```

---

## Phase 3: API Improvements

**Priority:** Medium
**Estimated complexity:** Medium

### 3.1 Accept Dynamic Values with Auto-Serialization

**File:** `lib/src/talon/talon.dart`

```dart
Future<void> saveChange({
  required String table,
  required String row,
  required String column,
  required dynamic value,  // Changed from String
  String? dataType,        // Now optional, auto-detected
}) async {
  final serialized = _serializeValue(value);

  final message = Message(
    // ...
    dataType: dataType ?? serialized.type,
    value: serialized.value,
    // ...
  );

  // ...
}

/// Internal value serialization
_SerializedValue _serializeValue(dynamic value) {
  if (value == null) {
    return _SerializedValue(type: 'null', value: '');
  } else if (value is String) {
    return _SerializedValue(type: 'string', value: value);
  } else if (value is int) {
    return _SerializedValue(type: 'int', value: value.toString());
  } else if (value is double) {
    return _SerializedValue(type: 'double', value: value.toString());
  } else if (value is bool) {
    return _SerializedValue(type: 'bool', value: value ? '1' : '0');
  } else if (value is Map || value is List) {
    return _SerializedValue(type: 'json', value: jsonEncode(value));
  } else {
    return _SerializedValue(type: 'string', value: value.toString());
  }
}

class _SerializedValue {
  final String type;
  final String value;
  _SerializedValue({required this.type, required this.value});
}
```

### 3.2 Add Value Deserialization Utility

**File:** `lib/src/messages/message.dart`

```dart
class Message {
  // ... existing fields and methods ...

  /// Deserialize the value based on dataType
  /// Returns the original typed value
  dynamic get typedValue {
    switch (dataType) {
      case 'null':
        return null;
      case 'string':
        return value;
      case 'int':
        return int.tryParse(value) ?? 0;
      case 'double':
        return double.tryParse(value) ?? 0.0;
      case 'bool':
        return value == '1' || value.toLowerCase() == 'true';
      case 'json':
        try {
          return jsonDecode(value);
        } catch (e) {
          return value;
        }
      default:
        return value;
    }
  }
}
```

### 3.3 Add Change Stream with Source Information

**File:** `lib/src/talon/talon.dart`

```dart
import 'dart:async';

enum TalonChangeSource { local, server }

class TalonChange {
  final TalonChangeSource source;
  final List<Message> messages;

  const TalonChange({
    required this.source,
    required this.messages,
  });
}

class Talon {
  // ... existing fields ...

  final _changesController = StreamController<TalonChange>.broadcast();

  /// Stream of all changes (local and server)
  Stream<TalonChange> get changes => _changesController.stream;

  /// Stream of only server changes
  Stream<TalonChange> get serverChanges =>
      changes.where((c) => c.source == TalonChangeSource.server);

  /// Stream of only local changes
  Stream<TalonChange> get localChanges =>
      changes.where((c) => c.source == TalonChangeSource.local);

  // Update saveChange to emit local changes
  Future<void> saveChange({...}) async {
    // ... existing logic ...

    await _offlineDatabase.saveMessageFromLocalChange(message);

    // Emit local change
    _changesController.add(TalonChange(
      source: TalonChangeSource.local,
      messages: [message],
    ));

    await syncToServer();
  }

  // Update subscribeToServerMessages to emit server changes
  void subscribeToServerMessages() async {
    // ... existing setup ...

    _serverMessagesSubscription = _serverDatabase.subscribeToServerMessages(
      // ...
      onMessagesReceived: (List<Message> messages) async {
        // ... existing logic ...

        // Emit server changes
        _changesController.add(TalonChange(
          source: TalonChangeSource.server,
          messages: messages,
        ));

        // Keep backward compatibility
        _onMessagesReceived?.call(messages);
      },
    );
  }

  /// Dispose resources
  void dispose() {
    _serverMessagesSubscription?.cancel();
    _changesController.close();
  }
}
```

### 3.4 Deprecate Callback in Favor of Stream

**File:** `lib/src/talon/talon.dart`

```dart
@Deprecated('Use the changes stream instead')
set onMessagesReceived(void Function(List<Message>) value) {
  _onMessagesReceived = value;
  // ... existing logic ...
}
```

---

## Phase 4: Internalize Conflict Resolution

**Priority:** High
**Estimated complexity:** Medium

### 4.1 Change `shouldApplyMessage()` from Abstract to Concrete

**File:** `lib/src/offline_database/offline_database.dart`

```dart
abstract class OfflineDatabase {
  // ... existing abstract methods ...

  /// Get the existing HLC timestamp for a specific cell
  /// Returns null if no existing value
  ///
  /// Implementation should query the messages table:
  /// ```sql
  /// SELECT local_timestamp FROM messages
  /// WHERE table_name = ? AND row = ? AND column = ?
  /// ORDER BY local_timestamp DESC LIMIT 1
  /// ```
  Future<String?> getExistingTimestamp({
    required String table,
    required String row,
    required String column,
  });

  /// Determines if a message should be applied based on HLC comparison
  ///
  /// This is NOT abstract - Talon owns the conflict resolution logic.
  /// Developers only need to implement getExistingTimestamp().
  @nonVirtual
  Future<bool> shouldApplyMessage(Message message) async {
    final existingTimestamp = await getExistingTimestamp(
      table: message.table,
      row: message.row,
      column: message.column,
    );

    // No existing value - always apply
    if (existingTimestamp == null) {
      return true;
    }

    // Compare HLC timestamps - higher timestamp wins
    final comparison = HLC.compareStrings(
      message.localTimestamp,
      existingTimestamp,
    );

    // Apply if new message has higher (later) timestamp
    return comparison > 0;
  }
}
```

### 4.2 Update OfflineDatabase Interface

**File:** `lib/src/offline_database/offline_database.dart`

Remove `shouldApplyMessage` from abstract methods that developers must implement:

```dart
abstract class OfflineDatabase {
  /// Initialize the database
  Future<void> init();

  /// Apply a message to the actual data table
  /// Called only after shouldApplyMessage returns true
  Future<bool> applyMessageToLocalDataTable(Message message);

  /// Store a message in the messages tracking table
  Future<bool> applyMessageToLocalMessageTable(Message message);

  /// Save the last synced server timestamp for incremental sync
  Future<void> saveLastSyncedServerTimestamp(int serverTimestamp);

  /// Read the last synced server timestamp
  Future<int?> readLastSyncedServerTimestamp();

  /// Get all messages that haven't been synced to the server
  Future<List<Message>> getUnsyncedMessages();

  /// Mark messages as successfully synced
  Future<void> markMessagesAsSynced(List<String> syncedMessageIds);

  /// NEW: Get existing timestamp for conflict resolution
  /// Talon uses this internally for shouldApplyMessage()
  Future<String?> getExistingTimestamp({
    required String table,
    required String row,
    required String column,
  });

  // shouldApplyMessage is now concrete, not abstract
  // saveMessageFromServer is concrete (uses shouldApplyMessage)
  // saveMessagesFromServer is concrete
  // saveMessageFromLocalChange is concrete
}
```

---

## Phase 5: Developer Experience

**Priority:** Medium
**Estimated complexity:** Low

### 5.1 Export Messages Table Schema

**File:** `lib/src/schema/talon_schema.dart` (new file)

```dart
/// Schema definitions for Talon's messages table.
///
/// Developers should use these in their database initialization
/// to ensure consistency with Talon's expectations.
class TalonSchema {
  TalonSchema._();

  /// SQL schema for the messages table (SQLite compatible)
  static const String messagesTableSql = '''
CREATE TABLE IF NOT EXISTS talon_messages (
  id TEXT PRIMARY KEY,
  table_name TEXT NOT NULL,
  row TEXT NOT NULL,
  "column" TEXT NOT NULL,
  data_type TEXT NOT NULL DEFAULT '',
  value TEXT NOT NULL,
  server_timestamp INTEGER,
  local_timestamp TEXT NOT NULL,
  user_id TEXT NOT NULL,
  client_id TEXT NOT NULL,
  has_been_applied INTEGER NOT NULL DEFAULT 0 CHECK (has_been_applied IN (0, 1)),
  has_been_synced INTEGER NOT NULL DEFAULT 0 CHECK (has_been_synced IN (0, 1))
);

CREATE INDEX IF NOT EXISTS idx_talon_messages_sync
  ON talon_messages(has_been_synced);

CREATE INDEX IF NOT EXISTS idx_talon_messages_lookup
  ON talon_messages(table_name, row, "column");
''';

  /// Column definitions for use with Drift
  static const String messagesTableDrift = '''
class TalonMessages extends Table {
  TextColumn get id => text()();
  TextColumn get tableName => text()();
  TextColumn get row => text()();
  TextColumn get column => text()();
  TextColumn get dataType => text().withDefault(const Constant(''))();
  TextColumn get value => text()();
  IntColumn get serverTimestamp => integer().nullable()();
  TextColumn get localTimestamp => text()();
  TextColumn get userId => text()();
  TextColumn get clientId => text()();
  BoolColumn get hasBeenApplied => boolean().withDefault(const Constant(false))();
  BoolColumn get hasBeenSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
''';

  /// PostgreSQL schema for server-side messages table (Supabase, etc.)
  static const String messagesTablePostgres = '''
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  table_name TEXT NOT NULL,
  row TEXT NOT NULL,
  "column" TEXT NOT NULL,
  data_type TEXT NOT NULL DEFAULT '',
  value TEXT NOT NULL,
  server_timestamp BIGINT GENERATED ALWAYS AS IDENTITY,
  local_timestamp TEXT NOT NULL,
  user_id TEXT NOT NULL,
  client_id TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_sync
  ON messages(user_id, server_timestamp);

CREATE INDEX IF NOT EXISTS idx_messages_client
  ON messages(client_id);

-- Enable Row Level Security
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Users can only see their own messages
CREATE POLICY "Users can view own messages" ON messages
  FOR SELECT USING (auth.uid()::text = user_id);

-- Users can only insert their own messages
CREATE POLICY "Users can insert own messages" ON messages
  FOR INSERT WITH CHECK (auth.uid()::text = user_id);
''';

  /// Required columns for the messages table
  static const List<String> requiredColumns = [
    'id',
    'table_name',
    'row',
    'column',
    'data_type',
    'value',
    'server_timestamp',
    'local_timestamp',
    'user_id',
    'client_id',
    'has_been_applied',
    'has_been_synced',
  ];
}
```

### 5.2 Update Public Exports

**File:** `lib/talon.dart`

```dart
library talon;

// Core
export 'src/talon/talon.dart';

// Models
export 'src/messages/message.dart';

// Interfaces
export 'src/offline_database/offline_database.dart';
export 'src/server_database/server_database.dart';

// Schema helpers
export 'src/schema/talon_schema.dart';

// HLC (for advanced users who need direct access)
export 'src/hybrid_logical_clock/hlc.dart' show HLC;
```

### 5.3 Implement `startPeriodicSync()`

**File:** `lib/src/talon/talon.dart`

```dart
Timer? _periodicSyncTimer;

/// Start periodic background sync
///
/// This is useful for ensuring sync happens even if the app
/// doesn't explicitly trigger it. Recommended interval: 5-15 minutes.
void startPeriodicSync({Duration interval = const Duration(minutes: 5)}) {
  stopPeriodicSync();

  _periodicSyncTimer = Timer.periodic(interval, (_) {
    if (_syncIsEnabled) {
      runSync();
    }
  });
}

/// Stop periodic background sync
void stopPeriodicSync() {
  _periodicSyncTimer?.cancel();
  _periodicSyncTimer = null;
}

/// Dispose all resources
void dispose() {
  stopPeriodicSync();
  unsubscribeFromServerMessages();
  _changesController.close();
}
```

---

## Phase 6: Testing & Validation

**Priority:** Critical
**Estimated complexity:** High

### 6.1 Unit Tests Structure

**Directory:** `test/`

```
test/
├── unit/
│   ├── message_test.dart
│   ├── hlc_test.dart
│   ├── talon_test.dart
│   └── serialization_test.dart
├── integration/
│   ├── sync_flow_test.dart
│   ├── conflict_resolution_test.dart
│   └── offline_online_test.dart
├── mocks/
│   ├── mock_offline_database.dart
│   └── mock_server_database.dart
└── talon_test.dart  (main entry point)
```

### 6.2 Critical Test Cases

```dart
// test/unit/hlc_test.dart
void main() {
  group('HLC', () {
    test('send() increments local clock', () { ... });
    test('receive() updates clock from remote', () { ... });
    test('compareTo() orders correctly', () { ... });
    test('handles clock drift', () { ... });
    test('pack/unpack roundtrip', () { ... });
  });
}

// test/unit/message_test.dart
void main() {
  group('Message', () {
    test('toMap/fromMap roundtrip', () { ... });
    test('toJson/fromJson roundtrip', () { ... });
    test('typedValue deserializes correctly', () { ... });
    test('equality works correctly', () { ... });
  });
}

// test/integration/conflict_resolution_test.dart
void main() {
  group('Conflict Resolution', () {
    test('later timestamp wins', () { ... });
    test('same timestamp uses node comparison', () { ... });
    test('concurrent edits resolve deterministically', () { ... });
    test('offline edits merge correctly on reconnect', () { ... });
  });
}

// test/integration/sync_flow_test.dart
void main() {
  group('Sync Flow', () {
    test('local change syncs to server', () { ... });
    test('server change applies locally', () { ... });
    test('unsynced messages retry on reconnect', () { ... });
    test('messages marked as synced after success', () { ... });
  });
}
```

### 6.3 Mock Implementations

**File:** `test/mocks/mock_offline_database.dart`

```dart
class MockOfflineDatabase extends OfflineDatabase {
  final List<Message> messages = [];
  int? lastSyncedTimestamp;

  @override
  Future<void> init() async {}

  @override
  Future<bool> applyMessageToLocalDataTable(Message message) async {
    return true;
  }

  @override
  Future<bool> applyMessageToLocalMessageTable(Message message) async {
    messages.add(message);
    return true;
  }

  @override
  Future<String?> getExistingTimestamp({
    required String table,
    required String row,
    required String column,
  }) async {
    final existing = messages
        .where((m) => m.table == table && m.row == row && m.column == column)
        .toList();

    if (existing.isEmpty) return null;

    existing.sort((a, b) => HLC.compareStrings(b.localTimestamp, a.localTimestamp));
    return existing.first.localTimestamp;
  }

  // ... other implementations
}
```

---

## File-by-File Changes

### Summary of All File Modifications

| File | Type | Changes |
|------|------|---------|
| `lib/src/talon/talon.dart` | Modify | HLC integration, change stream, fix bugs, periodic sync |
| `lib/src/messages/message.dart` | Modify | Add `typedValue` getter |
| `lib/src/offline_database/offline_database.dart` | Modify | Fix awaits, internalize `shouldApplyMessage`, add `getExistingTimestamp` |
| `lib/src/hybrid_logical_clock/hlc.dart` | Modify | Add `parse()` and `compareStrings()` static methods |
| `lib/src/schema/talon_schema.dart` | Create | Schema constants |
| `lib/talon.dart` | Modify | Export new schema file |
| `test/**` | Create | All test files |
| `example/**/offline_database_implementation.dart` | Modify | Fix query, implement new interface |

---

## Migration Guide

### For Existing Users (0.0.2 → 1.0.0)

#### Breaking Changes

1. **`shouldApplyMessage()` is no longer abstract**

   Before:
   ```dart
   @override
   Future<bool> shouldApplyMessage(Message message) async {
     // Your implementation
   }
   ```

   After:
   ```dart
   @override
   Future<String?> getExistingTimestamp({
     required String table,
     required String row,
     required String column,
   }) async {
     final result = await db.rawQuery('''
       SELECT local_timestamp FROM messages
       WHERE table_name = ? AND row = ? AND column = ?
       ORDER BY local_timestamp DESC LIMIT 1
     ''', [table, row, column]);

     return result.isEmpty ? null : result.first['local_timestamp'] as String;
   }
   ```

2. **`saveChange()` value parameter type changed**

   Before:
   ```dart
   await talon.saveChange(
     column: 'is_done',
     value: isDone ? '1' : '0',  // String only
   );
   ```

   After:
   ```dart
   await talon.saveChange(
     column: 'is_done',
     value: isDone,  // Any type
   );
   ```

3. **`onMessagesReceived` is deprecated**

   Before:
   ```dart
   talon.onMessagesReceived = (messages) {
     refreshUI();
   };
   ```

   After:
   ```dart
   talon.changes.listen((change) {
     refreshUI();
   });
   ```

#### Non-Breaking Additions

- `talon.changes` stream with `TalonChangeSource`
- `talon.serverChanges` and `talon.localChanges` filtered streams
- `message.typedValue` getter
- `TalonSchema` constants
- `talon.startPeriodicSync()` and `talon.stopPeriodicSync()`
- `talon.dispose()`

---

## Timeline Estimate

| Phase | Complexity | Dependencies |
|-------|------------|--------------|
| Phase 1: Bug Fixes | Low | None |
| Phase 2: HLC Integration | Medium | Phase 1 |
| Phase 3: API Improvements | Medium | Phase 1 |
| Phase 4: Internalize Conflict Resolution | Medium | Phase 2 |
| Phase 5: Developer Experience | Low | Phase 3, 4 |
| Phase 6: Testing | High | All phases |

**Recommended order:** 1 → 2 → 4 → 3 → 5 → 6

This order prioritizes correctness (bug fixes, HLC, conflict resolution) before convenience (API improvements, DX).
