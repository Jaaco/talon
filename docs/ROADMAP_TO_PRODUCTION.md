# Talon: 10-Stage Roadmap to Production

> **Goal:** Transform Talon from a working prototype (v0.0.2) to a production-ready, well-tested, thoroughly documented offline-first sync library (v1.0.0).

---

## Table of Contents

1. [Overview](#overview)
2. [Stage 1: Critical Bug Fixes](#stage-1-critical-bug-fixes)
3. [Stage 2: HLC Integration](#stage-2-hlc-integration)
4. [Stage 3: Internalize Conflict Resolution](#stage-3-internalize-conflict-resolution)
5. [Stage 4: Core Test Suite](#stage-4-core-test-suite)
6. [Stage 5: API Refinements](#stage-5-api-refinements)
7. [Stage 6: Batching Implementation](#stage-6-batching-implementation)
8. [Stage 7: Advanced Testing](#stage-7-advanced-testing)
9. [Stage 8: Documentation](#stage-8-documentation)
10. [Stage 9: Example Implementations](#stage-9-example-implementations)
11. [Stage 10: Production Polish](#stage-10-production-polish)
12. [Version Milestones](#version-milestones)
13. [Appendix: File Change Summary](#appendix-file-change-summary)

---

## Overview

### Current State (v0.0.2)
- Basic sync loop functional
- HLC implemented but not integrated
- No tests
- Single example (sqflite + Supabase combined)
- Several critical bugs

### Target State (v1.0.0)
- All bugs fixed
- HLC fully integrated
- Conflict resolution internalized (no developer footgun)
- Comprehensive test suite (unit, integration, edge cases)
- Batching for efficient sync
- Extensive documentation
- Separate, complete examples for sqflite and Supabase
- Production-ready API

### Guiding Principles

1. **Fix before adding** - Correctness before features
2. **Test as you go** - Each stage includes relevant tests
3. **Stay in scope** - Sync layer only, not an ORM
4. **Document for adoption** - Clear docs enable usage

---

## Stage 1: Critical Bug Fixes

### Aim
Fix all bugs that would cause data loss, corruption, or incorrect sync behavior. After this stage, the core sync loop should work correctly.

### Scope

#### 1.1 Fix Missing `await` Statements
**File:** `lib/src/offline_database/offline_database.dart`

| Location | Issue | Fix |
|----------|-------|-----|
| Line 28 | `applyMessageToLocalMessageTable()` not awaited | Add `await` |
| Line 34 | `applyMessageToLocalDataTable()` not awaited | Add `await` |
| Line 73 | `applyMessageToLocalDataTable()` not awaited | Add `await` |
| Line 79 | `applyMessageToLocalMessageTable()` not awaited | Add `await` |

**Before:**
```dart
Future<bool> saveMessageFromServer(Message message) async {
  try {
    applyMessageToLocalMessageTable(message);  // NOT AWAITED
  } catch (e) {
    return Future.value(false);
  }
  // ...
}
```

**After:**
```dart
Future<bool> saveMessageFromServer(Message message) async {
  try {
    await applyMessageToLocalMessageTable(message);  // AWAITED
  } catch (e) {
    return Future.value(false);
  }
  // ...
}
```

#### 1.2 Fix `runSync()` Not Awaiting
**File:** `lib/src/talon/talon.dart`

**Before:**
```dart
Future<void> runSync() async {
  final completer = Completer<void>();
  syncToServer();      // NOT AWAITED
  syncFromServer();    // NOT AWAITED
  completer.complete();
}
```

**After:**
```dart
Future<void> runSync() async {
  await syncToServer();
  await syncFromServer();
}
```

#### 1.3 Call `markMessagesAsSynced()` After Successful Sync
**File:** `lib/src/talon/talon.dart`

**Before:**
```dart
Future<void> syncToServer() async {
  // ...
  final successfullySyncedMessages = <String>[];

  for (final message in unsyncedMessages) {
    final wasSuccessful = await _serverDatabase.sendMessageToServer(message: message);
    if (wasSuccessful) {
      successfullySyncedMessages.add(message.id);
    }
  }
  // successfullySyncedMessages NEVER USED!
}
```

**After:**
```dart
Future<void> syncToServer() async {
  // ...
  final successfullySyncedMessages = <String>[];

  for (final message in unsyncedMessages) {
    final wasSuccessful = await _serverDatabase.sendMessageToServer(message: message);
    if (wasSuccessful) {
      successfullySyncedMessages.add(message.id);
    }
  }

  if (successfullySyncedMessages.isNotEmpty) {
    await _offlineDatabase.markMessagesAsSynced(successfullySyncedMessages);
  }
}
```

#### 1.4 Fix Example: `getUnsyncedMessages()` Returns All Messages
**File:** `example/sqflite_supabase_example/lib/talon_implementation/offline_database_implementation.dart`

**Before:**
```dart
@override
Future<List<Message>> getUnsyncedMessages() async {
  final messagesRaw = await localDb.rawQuery('''
    SELECT * FROM messages
  ''');
  // Returns ALL messages, not just unsynced
}
```

**After:**
```dart
@override
Future<List<Message>> getUnsyncedMessages() async {
  final messagesRaw = await localDb.rawQuery('''
    SELECT * FROM messages WHERE hasBeenSynced = 0
  ''');
  // Returns only unsynced messages
}
```

#### 1.5 Simplify Return Statements
**File:** `lib/src/offline_database/offline_database.dart`

Replace verbose `return Future.value(x)` with simple `return x`:
```dart
// Before
return Future.value(false);

// After
return false;
```

### Completion Criteria

- [ ] All four `await` statements added in `offline_database.dart`
- [ ] `runSync()` properly awaits both sync operations
- [ ] `markMessagesAsSynced()` called after successful sync
- [ ] Example `getUnsyncedMessages()` filters by `hasBeenSynced = 0`
- [ ] No `Future.value()` wrappers for simple returns
- [ ] Code compiles without errors
- [ ] Manual test: Create message → sync → verify `hasBeenSynced = 1`

### Deliverables
- Fixed `lib/src/offline_database/offline_database.dart`
- Fixed `lib/src/talon/talon.dart`
- Fixed example implementation
- Git commit: `fix: critical bugs in sync loop and message tracking`

---

## Stage 2: HLC Integration

### Aim
Replace the fragile `DateTime.now().toString()` timestamp with proper Hybrid Logical Clock timestamps. This ensures deterministic, causally-ordered conflict resolution across devices with clock skew.

### Scope

#### 2.1 Add HLC State to Talon Class
**File:** `lib/src/talon/talon.dart`

```dart
import '../hybrid_logical_clock/hlc.dart';
import '../hybrid_logical_clock/hlc.state.dart';

class Talon {
  // ... existing fields ...

  late final HLCState _hlcState;

  Talon({
    required this.userId,
    required this.clientId,
    required ServerDatabase serverDatabase,
    required OfflineDatabase offlineDatabase,
    required String Function() createNewIdFunction,
  }) {
    _serverDatabase = serverDatabase;
    _offlineDatabase = offlineDatabase;
    _createNewIdFunction = createNewIdFunction;

    // Initialize HLC with clientId as node identifier
    _hlcState = HLCState(clientId);
  }
}
```

#### 2.2 Use HLC for Message Timestamps
**File:** `lib/src/talon/talon.dart`

```dart
Future<void> saveChange({
  required String table,
  required String row,
  required String column,
  required String value,
  String dataType = '',
}) async {
  // Generate HLC timestamp
  final hlcTimestamp = _hlcState.send();

  final message = Message(
    id: _createNewIdFunction(),
    table: table,
    row: row,
    column: column,
    dataType: dataType,
    value: value,
    localTimestamp: hlcTimestamp.toString(),  // HLC, not DateTime.now()
    userId: userId,
    clientId: clientId,
    hasBeenApplied: false,
    hasBeenSynced: false,
  );

  await _offlineDatabase.saveMessageFromLocalChange(message);
  await syncToServer();
}
```

#### 2.3 Update HLC on Receiving Messages
**File:** `lib/src/talon/talon.dart`

When receiving messages from the server, update the local HLC to maintain causal ordering:

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
      // Update HLC from received messages
      for (final message in messages) {
        final receivedHlc = HLC.tryParse(message.localTimestamp);
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

Similarly update `syncFromServer()`:

```dart
Future<void> syncFromServer() async {
  if (!_syncIsEnabled) return;

  final lastSyncedServerTimestamp =
      await _offlineDatabase.readLastSyncedServerTimestamp();

  final messagesFromServer = await _serverDatabase.getMessagesFromServer(
    userId: userId,
    clientId: clientId,
    lastSyncedServerTimestamp: lastSyncedServerTimestamp,
  );

  // Update HLC from received messages
  for (final message in messagesFromServer) {
    final receivedHlc = HLC.tryParse(message.localTimestamp);
    if (receivedHlc != null) {
      _hlcState.receive(receivedHlc);
    }
  }

  await _offlineDatabase.saveMessagesFromServer(messagesFromServer);
}
```

#### 2.4 Add HLC Parsing and Comparison Utilities
**File:** `lib/src/hybrid_logical_clock/hlc.dart`

```dart
class HLC implements Comparable<HLC> {
  // ... existing implementation ...

  /// Try to parse an HLC from its packed string representation.
  /// Returns null if parsing fails.
  static HLC? tryParse(String packed) {
    try {
      // Assuming format: "timestamp:count:node" or similar
      final parts = packed.split(':');
      if (parts.length < 3) return null;

      return HLC(
        timestamp: int.parse(parts[0]),
        count: int.parse(parts[1]),
        node: parts.sublist(2).join(':'),  // Node might contain colons
      );
    } catch (e) {
      return null;
    }
  }

  /// Compare two HLC timestamp strings.
  /// Returns: negative if a < b, zero if a == b, positive if a > b.
  /// Returns 0 if either string cannot be parsed.
  static int compareTimestamps(String a, String b) {
    final hlcA = tryParse(a);
    final hlcB = tryParse(b);

    if (hlcA == null && hlcB == null) return 0;
    if (hlcA == null) return -1;
    if (hlcB == null) return 1;

    return hlcA.compareTo(hlcB);
  }
}
```

#### 2.5 Update HLC Pack Format
**File:** `lib/src/hybrid_logical_clock/hlc.utils.dart`

Ensure the pack/unpack format is consistent and parseable:

```dart
class HLCUtils {
  // ... existing implementation ...

  /// Pack HLC to string format: "timestamp:count:node"
  String pack(HLC hlc) {
    return '${hlc.timestamp}:${hlc.count}:${hlc.node}';
  }

  /// Unpack HLC from string format
  HLC unpack(String packed) {
    final parts = packed.split(':');
    if (parts.length < 3) {
      throw FormatException('Invalid HLC format: $packed');
    }

    return HLC(
      timestamp: int.parse(parts[0]),
      count: int.parse(parts[1]),
      node: parts.sublist(2).join(':'),
    );
  }
}
```

### Completion Criteria

- [ ] `HLCState` initialized in Talon constructor
- [ ] `saveChange()` uses `_hlcState.send()` for timestamps
- [ ] `syncFromServer()` calls `_hlcState.receive()` for each message
- [ ] `subscribeToServerMessages()` calls `_hlcState.receive()` for each message
- [ ] `HLC.tryParse()` static method implemented
- [ ] `HLC.compareTimestamps()` static method implemented
- [ ] Pack/unpack format is consistent and documented
- [ ] Unit tests for HLC parsing and comparison pass

### Deliverables
- Updated `lib/src/talon/talon.dart`
- Updated `lib/src/hybrid_logical_clock/hlc.dart`
- Updated `lib/src/hybrid_logical_clock/hlc.utils.dart`
- New `test/unit/hlc_test.dart`
- Git commit: `feat: integrate HLC for deterministic conflict resolution`

---

## Stage 3: Internalize Conflict Resolution

### Aim
Remove the `shouldApplyMessage()` footgun by making conflict resolution internal to Talon. Developers should not implement CRDT logic—they should only provide a simple query to get existing timestamps.

### Scope

#### 3.1 Add New Abstract Method: `getExistingTimestamp()`
**File:** `lib/src/offline_database/offline_database.dart`

```dart
abstract class OfflineDatabase {
  // ... existing abstract methods ...

  /// Get the most recent HLC timestamp for a specific cell (table/row/column).
  ///
  /// Returns null if no existing message for this cell.
  ///
  /// Implementation should query the messages table:
  /// ```sql
  /// SELECT local_timestamp FROM messages
  /// WHERE table_name = ? AND row = ? AND column = ?
  /// ORDER BY local_timestamp DESC
  /// LIMIT 1
  /// ```
  Future<String?> getExistingTimestamp({
    required String table,
    required String row,
    required String column,
  });
}
```

#### 3.2 Make `shouldApplyMessage()` Concrete (Non-Abstract)
**File:** `lib/src/offline_database/offline_database.dart`

```dart
import '../hybrid_logical_clock/hlc.dart';

abstract class OfflineDatabase {
  // ... abstract methods ...

  /// Determines if a message should be applied based on HLC comparison.
  ///
  /// This is NOT abstract—Talon owns the conflict resolution logic.
  /// Developers only need to implement [getExistingTimestamp].
  ///
  /// Returns true if the message should be applied (newer or no existing value).
  Future<bool> shouldApplyMessage(Message message) async {
    final existingTimestamp = await getExistingTimestamp(
      table: message.table,
      row: message.row,
      column: message.column,
    );

    // No existing value for this cell—always apply
    if (existingTimestamp == null) {
      return true;
    }

    // Compare HLC timestamps—higher (later) timestamp wins
    final comparison = HLC.compareTimestamps(
      message.localTimestamp,
      existingTimestamp,
    );

    // Apply if new message has higher timestamp
    // If equal, don't apply (existing value wins ties)
    return comparison > 0;
  }
}
```

#### 3.3 Update `applyMessageToLocalDataTable` Call Sites
**File:** `lib/src/offline_database/offline_database.dart`

Ensure `shouldApplyMessage()` is called before applying:

```dart
Future<bool> saveMessageFromServer(Message message) async {
  // Always save to message table (for history/sync tracking)
  try {
    await applyMessageToLocalMessageTable(message);
  } catch (e) {
    return false;
  }

  // Only apply to data table if this message wins conflict resolution
  final shouldApply = await shouldApplyMessage(message);
  if (shouldApply) {
    try {
      await applyMessageToLocalDataTable(message);
    } catch (e) {
      // Message saved but not applied—this is acceptable
      // (e.g., table doesn't exist yet, schema mismatch)
    }
  }

  return true;
}
```

#### 3.4 Update Example Implementation
**File:** `example/sqflite_supabase_example/lib/talon_implementation/offline_database_implementation.dart`

Replace the old `shouldApplyMessage()` with `getExistingTimestamp()`:

```dart
class MyOfflineDB extends OfflineDatabase {
  // ... existing methods ...

  // REMOVE THIS:
  // @override
  // Future<bool> shouldApplyMessage(Message message) async { ... }

  // ADD THIS:
  @override
  Future<String?> getExistingTimestamp({
    required String table,
    required String row,
    required String column,
  }) async {
    try {
      final result = await localDb.rawQuery('''
        SELECT local_timestamp
        FROM messages
        WHERE table_name = ? AND row = ? AND "column" = ?
        ORDER BY local_timestamp DESC
        LIMIT 1
      ''', [table, row, column]);

      if (result.isEmpty) return null;
      return result.first['local_timestamp'] as String?;
    } catch (e) {
      return null;
    }
  }

  // UPDATE THIS (remove shouldApplyMessage call, it's now internal):
  @override
  Future<bool> applyMessageToLocalDataTable(Message message) async {
    // No longer need to check shouldApplyMessage here—base class handles it
    try {
      await localDb.transaction((txn) async {
        int updatedRows = await txn.rawUpdate('''
          UPDATE ${message.table}
          SET ${message.column} = ?
          WHERE id = ?
        ''', [message.value, message.row]);

        if (updatedRows == 0) {
          await txn.rawInsert('''
            INSERT INTO ${message.table} (id, ${message.column})
            VALUES (?, ?)
          ''', [message.row, message.value]);
        }
      });
      return true;
    } catch (e) {
      return false;
    }
  }
}
```

### Completion Criteria

- [ ] `getExistingTimestamp()` added as abstract method
- [ ] `shouldApplyMessage()` is now a concrete method using HLC comparison
- [ ] `saveMessageFromServer()` correctly calls `shouldApplyMessage()` before applying
- [ ] Example implementation updated with new interface
- [ ] Old `shouldApplyMessage()` removed from example
- [ ] Integration test: Two conflicting messages → correct one wins

### Deliverables
- Updated `lib/src/offline_database/offline_database.dart`
- Updated example implementation
- New `test/integration/conflict_resolution_test.dart`
- Git commit: `feat: internalize conflict resolution, remove developer footgun`

---

## Stage 4: Core Test Suite

### Aim
Establish a comprehensive test foundation covering all core functionality. Tests should validate that Stages 1-3 work correctly and prevent regressions.

### Scope

#### 4.1 Test Directory Structure

```
test/
├── unit/
│   ├── message_test.dart          # Message model tests
│   ├── hlc_test.dart              # HLC tests
│   └── serialization_test.dart    # Value serialization tests
├── integration/
│   ├── talon_test.dart            # Core Talon class tests
│   ├── sync_flow_test.dart        # End-to-end sync tests
│   └── conflict_resolution_test.dart  # Conflict scenarios
├── mocks/
│   ├── mock_offline_database.dart
│   └── mock_server_database.dart
└── test_utils.dart                # Shared test utilities
```

#### 4.2 Mock Implementations
**File:** `test/mocks/mock_offline_database.dart`

```dart
import 'package:talon/talon.dart';

class MockOfflineDatabase extends OfflineDatabase {
  final List<Message> messages = [];
  final Map<String, Map<String, dynamic>> dataTables = {};
  int? _lastSyncedTimestamp;

  @override
  Future<void> init() async {}

  @override
  Future<bool> applyMessageToLocalDataTable(Message message) async {
    dataTables[message.table] ??= {};
    dataTables[message.table]![message.row] ??= {};
    dataTables[message.table]![message.row]![message.column] = message.value;
    return true;
  }

  @override
  Future<bool> applyMessageToLocalMessageTable(Message message) async {
    // Avoid duplicates
    if (messages.any((m) => m.id == message.id)) return true;
    messages.add(message);
    return true;
  }

  @override
  Future<String?> getExistingTimestamp({
    required String table,
    required String row,
    required String column,
  }) async {
    final matching = messages
        .where((m) => m.table == table && m.row == row && m.column == column)
        .toList();

    if (matching.isEmpty) return null;

    // Sort by HLC timestamp descending
    matching.sort((a, b) => HLC.compareTimestamps(
      b.localTimestamp,
      a.localTimestamp,
    ));

    return matching.first.localTimestamp;
  }

  @override
  Future<List<Message>> getUnsyncedMessages() async {
    return messages.where((m) => !m.hasBeenSynced).toList();
  }

  @override
  Future<void> markMessagesAsSynced(List<String> syncedMessageIds) async {
    for (int i = 0; i < messages.length; i++) {
      if (syncedMessageIds.contains(messages[i].id)) {
        messages[i] = messages[i].copyWith(hasBeenSynced: true);
      }
    }
  }

  @override
  Future<int?> readLastSyncedServerTimestamp() async => _lastSyncedTimestamp;

  @override
  Future<void> saveLastSyncedServerTimestamp(int serverTimestamp) async {
    _lastSyncedTimestamp = serverTimestamp;
  }

  // Test utilities
  void clear() {
    messages.clear();
    dataTables.clear();
    _lastSyncedTimestamp = null;
  }

  dynamic getValue(String table, String row, String column) {
    return dataTables[table]?[row]?[column];
  }
}
```

**File:** `test/mocks/mock_server_database.dart`

```dart
import 'dart:async';
import 'package:talon/talon.dart';

class MockServerDatabase extends ServerDatabase {
  final List<Message> serverMessages = [];
  int _nextServerTimestamp = 1;
  final _messageController = StreamController<Message>.broadcast();

  @override
  Future<List<Message>> getMessagesFromServer({
    required int? lastSyncedServerTimestamp,
    required String clientId,
    required String userId,
  }) async {
    return serverMessages
        .where((m) =>
            m.serverTimestamp! > (lastSyncedServerTimestamp ?? 0) &&
            m.clientId != clientId &&
            m.userId == userId)
        .toList();
  }

  @override
  Future<bool> sendMessageToServer({required Message message}) async {
    final withTimestamp = message.copyWith(
      serverTimestamp: _nextServerTimestamp++,
      hasBeenSynced: true,
    );
    serverMessages.add(withTimestamp);
    _messageController.add(withTimestamp);
    return true;
  }

  @override
  StreamSubscription subscribeToServerMessages({
    required String clientId,
    required String userId,
    required int? lastSyncedServerTimestamp,
    required void Function(List<Message>) onMessagesReceived,
  }) {
    return _messageController.stream
        .where((m) => m.clientId != clientId && m.userId == userId)
        .listen((message) => onMessagesReceived([message]));
  }

  // Test utilities
  void clear() {
    serverMessages.clear();
    _nextServerTimestamp = 1;
  }

  void simulateServerMessage(Message message) {
    final withTimestamp = message.copyWith(
      serverTimestamp: _nextServerTimestamp++,
    );
    serverMessages.add(withTimestamp);
    _messageController.add(withTimestamp);
  }

  void dispose() {
    _messageController.close();
  }
}
```

#### 4.3 Unit Tests

**File:** `test/unit/message_test.dart`

```dart
import 'package:test/test.dart';
import 'package:talon/talon.dart';

void main() {
  group('Message', () {
    test('toMap and fromMap roundtrip preserves all fields', () {
      final message = Message(
        id: 'msg-123',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        dataType: 'string',
        value: 'Buy milk',
        serverTimestamp: 42,
        localTimestamp: '1234567890:0:client-1',
        userId: 'user-1',
        clientId: 'client-1',
        hasBeenApplied: true,
        hasBeenSynced: false,
      );

      final map = message.toMap();
      final restored = Message.fromMap(map);

      expect(restored, equals(message));
    });

    test('toJson and fromJson roundtrip preserves all fields', () {
      final message = Message(/* ... */);
      final json = message.toJson();
      final restored = Message.fromJson(json);
      expect(restored, equals(message));
    });

    test('copyWith creates new instance with updated fields', () {
      final original = Message(/* ... */);
      final updated = original.copyWith(value: 'New value');

      expect(updated.value, equals('New value'));
      expect(updated.id, equals(original.id));
      expect(original.value, isNot(equals('New value')));
    });

    test('equality works correctly', () {
      final m1 = Message(/* ... */);
      final m2 = Message(/* same values ... */);
      final m3 = Message(/* different id ... */);

      expect(m1, equals(m2));
      expect(m1, isNot(equals(m3)));
    });

    test('hashCode is consistent with equality', () {
      final m1 = Message(/* ... */);
      final m2 = Message(/* same values ... */);

      expect(m1.hashCode, equals(m2.hashCode));
    });
  });
}
```

**File:** `test/unit/hlc_test.dart`

```dart
import 'package:test/test.dart';
import 'package:talon/src/hybrid_logical_clock/hlc.dart';
import 'package:talon/src/hybrid_logical_clock/hlc.state.dart';

void main() {
  group('HLC', () {
    test('now() creates HLC with current timestamp', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final hlc = HLC.now('node-1');
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(hlc.timestamp, greaterThanOrEqualTo(before));
      expect(hlc.timestamp, lessThanOrEqualTo(after));
      expect(hlc.count, equals(0));
      expect(hlc.node, equals('node-1'));
    });

    test('compareTo orders by timestamp first', () {
      final earlier = HLC(timestamp: 1000, count: 5, node: 'z');
      final later = HLC(timestamp: 2000, count: 0, node: 'a');

      expect(earlier.compareTo(later), lessThan(0));
      expect(later.compareTo(earlier), greaterThan(0));
    });

    test('compareTo orders by count when timestamps equal', () {
      final lower = HLC(timestamp: 1000, count: 1, node: 'z');
      final higher = HLC(timestamp: 1000, count: 5, node: 'a');

      expect(lower.compareTo(higher), lessThan(0));
    });

    test('compareTo orders by node when timestamp and count equal', () {
      final nodeA = HLC(timestamp: 1000, count: 1, node: 'aaa');
      final nodeZ = HLC(timestamp: 1000, count: 1, node: 'zzz');

      expect(nodeA.compareTo(nodeZ), lessThan(0));
    });

    test('tryParse successfully parses valid HLC string', () {
      final hlc = HLC.tryParse('1234567890:42:my-node');

      expect(hlc, isNotNull);
      expect(hlc!.timestamp, equals(1234567890));
      expect(hlc.count, equals(42));
      expect(hlc.node, equals('my-node'));
    });

    test('tryParse returns null for invalid format', () {
      expect(HLC.tryParse('invalid'), isNull);
      expect(HLC.tryParse('123:456'), isNull);
      expect(HLC.tryParse(''), isNull);
    });

    test('tryParse handles node with colons', () {
      final hlc = HLC.tryParse('1234567890:42:node:with:colons');

      expect(hlc, isNotNull);
      expect(hlc!.node, equals('node:with:colons'));
    });

    test('compareTimestamps works with valid strings', () {
      final earlier = '1000:0:node';
      final later = '2000:0:node';

      expect(HLC.compareTimestamps(earlier, later), lessThan(0));
      expect(HLC.compareTimestamps(later, earlier), greaterThan(0));
      expect(HLC.compareTimestamps(earlier, earlier), equals(0));
    });

    test('toString and tryParse roundtrip', () {
      final original = HLC(timestamp: 1234567890, count: 42, node: 'test-node');
      final packed = original.toString();
      final restored = HLC.tryParse(packed);

      expect(restored, isNotNull);
      expect(restored!.timestamp, equals(original.timestamp));
      expect(restored.count, equals(original.count));
      expect(restored.node, equals(original.node));
    });
  });

  group('HLCState', () {
    test('send() increments count for rapid successive calls', () {
      final state = HLCState('node-1');

      final first = state.send();
      final second = state.send();

      // If called in same millisecond, count should increment
      if (first.timestamp == second.timestamp) {
        expect(second.count, equals(first.count + 1));
      }
    });

    test('receive() updates state from remote HLC', () {
      final state = HLCState('node-1');

      // Simulate receiving a message with a future timestamp
      final futureHlc = HLC(
        timestamp: DateTime.now().millisecondsSinceEpoch + 10000,
        count: 5,
        node: 'node-2',
      );

      state.receive(futureHlc);
      final next = state.send();

      // Our next HLC should be at least as high as what we received
      expect(next.compareTo(futureHlc), greaterThan(0));
    });
  });
}
```

#### 4.4 Integration Tests

**File:** `test/integration/sync_flow_test.dart`

```dart
import 'package:test/test.dart';
import 'package:talon/talon.dart';
import '../mocks/mock_offline_database.dart';
import '../mocks/mock_server_database.dart';

void main() {
  late MockOfflineDatabase offlineDb;
  late MockServerDatabase serverDb;
  late Talon talon;

  setUp(() {
    offlineDb = MockOfflineDatabase();
    serverDb = MockServerDatabase();
    talon = Talon(
      userId: 'user-1',
      clientId: 'client-1',
      serverDatabase: serverDb,
      offlineDatabase: offlineDb,
      createNewIdFunction: () => 'msg-${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() {
    serverDb.dispose();
  });

  group('Sync Flow', () {
    test('saveChange stores message locally', () async {
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Buy milk',
      );

      expect(offlineDb.messages.length, equals(1));
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

    test('saveChange syncs to server when enabled', () async {
      talon.syncIsEnabled = true;

      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Buy milk',
      );

      expect(serverDb.serverMessages.length, equals(1));
    });

    test('messages marked as synced after successful sync', () async {
      talon.syncIsEnabled = true;

      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Buy milk',
      );

      final syncedMessages = offlineDb.messages.where((m) => m.hasBeenSynced);
      expect(syncedMessages.length, equals(1));
    });

    test('syncFromServer retrieves and applies server messages', () async {
      // Simulate message from another client
      serverDb.simulateServerMessage(Message(
        id: 'server-msg-1',
        table: 'todos',
        row: 'todo-2',
        column: 'name',
        value: 'Server todo',
        localTimestamp: '${DateTime.now().millisecondsSinceEpoch}:0:client-2',
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      talon.syncIsEnabled = true;
      await talon.syncFromServer();

      expect(offlineDb.getValue('todos', 'todo-2', 'name'), equals('Server todo'));
    });
  });
}
```

**File:** `test/integration/conflict_resolution_test.dart`

```dart
import 'package:test/test.dart';
import 'package:talon/talon.dart';
import '../mocks/mock_offline_database.dart';
import '../mocks/mock_server_database.dart';

void main() {
  late MockOfflineDatabase offlineDb;
  late MockServerDatabase serverDb;
  late Talon talon;

  setUp(() {
    offlineDb = MockOfflineDatabase();
    serverDb = MockServerDatabase();
    talon = Talon(
      userId: 'user-1',
      clientId: 'client-1',
      serverDatabase: serverDb,
      offlineDatabase: offlineDb,
      createNewIdFunction: () => 'msg-${DateTime.now().microsecondsSinceEpoch}',
    );
    talon.syncIsEnabled = true;
  });

  group('Conflict Resolution', () {
    test('later timestamp wins over earlier', () async {
      // First change
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'First value',
      );

      // Wait to ensure different timestamp
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

    test('server message with later timestamp overwrites local', () async {
      // Local change first
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Local value',
      );

      // Server message with later timestamp
      final futureTimestamp = DateTime.now().millisecondsSinceEpoch + 1000;
      serverDb.simulateServerMessage(Message(
        id: 'server-msg-1',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Server value',
        localTimestamp: '$futureTimestamp:0:client-2',
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      await talon.syncFromServer();

      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals('Server value'));
    });

    test('local message with later timestamp preserved over server', () async {
      // Server message first (earlier timestamp)
      final pastTimestamp = DateTime.now().millisecondsSinceEpoch - 10000;
      serverDb.simulateServerMessage(Message(
        id: 'server-msg-1',
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'Old server value',
        localTimestamp: '$pastTimestamp:0:client-2',
        userId: 'user-1',
        clientId: 'client-2',
        hasBeenApplied: false,
        hasBeenSynced: true,
      ));

      // Local change (later timestamp)
      await talon.saveChange(
        table: 'todos',
        row: 'todo-1',
        column: 'name',
        value: 'New local value',
      );

      // Sync from server
      await talon.syncFromServer();

      // Local value should be preserved
      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals('New local value'));
    });

    test('different columns are independent', () async {
      await talon.saveChange(table: 'todos', row: 'todo-1', column: 'name', value: 'Todo name');
      await talon.saveChange(table: 'todos', row: 'todo-1', column: 'is_done', value: '1');

      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals('Todo name'));
      expect(offlineDb.getValue('todos', 'todo-1', 'is_done'), equals('1'));
    });

    test('different rows are independent', () async {
      await talon.saveChange(table: 'todos', row: 'todo-1', column: 'name', value: 'First todo');
      await talon.saveChange(table: 'todos', row: 'todo-2', column: 'name', value: 'Second todo');

      expect(offlineDb.getValue('todos', 'todo-1', 'name'), equals('First todo'));
      expect(offlineDb.getValue('todos', 'todo-2', 'name'), equals('Second todo'));
    });
  });
}
```

### Completion Criteria

- [ ] Test directory structure created
- [ ] Mock implementations complete and functional
- [ ] All Message model tests pass
- [ ] All HLC tests pass
- [ ] All sync flow tests pass
- [ ] All conflict resolution tests pass
- [ ] Test coverage > 80% for core classes
- [ ] `dart test` runs without failures

### Deliverables
- `test/` directory with full structure
- Mock implementations
- Unit tests for Message and HLC
- Integration tests for sync flow and conflicts
- Git commit: `test: add core test suite with mocks and integration tests`

---

## Stage 5: API Refinements

### Aim
Improve the developer experience with better value handling, a cleaner notification API, and proper lifecycle management—without expanding scope into ORM territory.

### Scope

#### 5.1 Accept Dynamic Values with Auto-Serialization
**File:** `lib/src/talon/talon.dart`

```dart
import 'dart:convert';

/// Internal representation of a serialized value
class _SerializedValue {
  final String type;
  final String value;
  const _SerializedValue({required this.type, required this.value});
}

class Talon {
  // ... existing code ...

  /// Serialize a dynamic value to string representation
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
    } else if (value is DateTime) {
      return _SerializedValue(type: 'datetime', value: value.toIso8601String());
    } else if (value is Map || value is List) {
      return _SerializedValue(type: 'json', value: jsonEncode(value));
    } else {
      // Fallback: convert to string
      return _SerializedValue(type: 'string', value: value.toString());
    }
  }

  Future<void> saveChange({
    required String table,
    required String row,
    required String column,
    required dynamic value,  // Changed from String
    String? dataType,        // Now optional, auto-detected if not provided
  }) async {
    final serialized = _serializeValue(value);

    final message = Message(
      id: _createNewIdFunction(),
      table: table,
      row: row,
      column: column,
      dataType: dataType ?? serialized.type,
      value: serialized.value,
      localTimestamp: _hlcState.send().toString(),
      userId: userId,
      clientId: clientId,
      hasBeenApplied: false,
      hasBeenSynced: false,
    );

    await _offlineDatabase.saveMessageFromLocalChange(message);

    if (_syncIsEnabled) {
      await syncToServer();
    }
  }
}
```

#### 5.2 Add Value Deserialization Helper to Message
**File:** `lib/src/messages/message.dart`

```dart
import 'dart:convert';

class Message {
  // ... existing fields and methods ...

  /// Deserialize the value based on dataType.
  /// Returns the original typed value.
  ///
  /// Note: This is a convenience method for reading values.
  /// The actual database storage/retrieval is the developer's responsibility.
  dynamic get typedValue {
    switch (dataType) {
      case 'null':
      case '':
        if (value.isEmpty) return null;
        return value;
      case 'string':
        return value;
      case 'int':
        return int.tryParse(value) ?? 0;
      case 'double':
        return double.tryParse(value) ?? 0.0;
      case 'bool':
        return value == '1' || value.toLowerCase() == 'true';
      case 'datetime':
        return DateTime.tryParse(value);
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

#### 5.3 Add Stream-Based Change Notification
**File:** `lib/src/talon/talon.dart`

```dart
import 'dart:async';

/// Source of a change
enum TalonChangeSource { local, server }

/// Represents a batch of changes from a single source
class TalonChange {
  final TalonChangeSource source;
  final List<Message> messages;

  const TalonChange({
    required this.source,
    required this.messages,
  });

  /// Get messages for a specific table
  List<Message> forTable(String table) {
    return messages.where((m) => m.table == table).toList();
  }

  /// Check if any messages affect a specific table
  bool affectsTable(String table) {
    return messages.any((m) => m.table == table);
  }
}

class Talon {
  // ... existing fields ...

  final _changesController = StreamController<TalonChange>.broadcast();

  /// Stream of all changes (both local and server).
  ///
  /// Use this to react to data changes:
  /// ```dart
  /// talon.changes.listen((change) {
  ///   if (change.affectsTable('todos')) {
  ///     refreshTodoList();
  ///   }
  /// });
  /// ```
  Stream<TalonChange> get changes => _changesController.stream;

  /// Stream of only server-originated changes.
  Stream<TalonChange> get serverChanges =>
      changes.where((c) => c.source == TalonChangeSource.server);

  /// Stream of only locally-originated changes.
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

    if (_syncIsEnabled) {
      await syncToServer();
    }
  }

  // Update subscribeToServerMessages to emit server changes
  void subscribeToServerMessages() async {
    // ... existing setup ...

    _serverMessagesSubscription = _serverDatabase.subscribeToServerMessages(
      // ...
      onMessagesReceived: (List<Message> messages) async {
        // Update HLC
        for (final message in messages) {
          final receivedHlc = HLC.tryParse(message.localTimestamp);
          if (receivedHlc != null) {
            _hlcState.receive(receivedHlc);
          }
        }

        await _offlineDatabase.saveMessagesFromServer(messages);

        // Emit server changes
        if (messages.isNotEmpty) {
          _changesController.add(TalonChange(
            source: TalonChangeSource.server,
            messages: messages,
          ));
        }

        // Keep backward compatibility
        _onMessagesReceived?.call(messages);
      },
    );
  }
}
```

#### 5.4 Deprecate Callback API
**File:** `lib/src/talon/talon.dart`

```dart
@Deprecated('Use the changes stream instead. Will be removed in v2.0.0')
set onMessagesReceived(void Function(List<Message>) value) {
  _onMessagesReceived = value;

  if (!_syncIsEnabled) return;

  unsubscribeFromServerMessages();
  subscribeToServerMessages();
}
```

#### 5.5 Add Lifecycle Management
**File:** `lib/src/talon/talon.dart`

```dart
class Talon {
  // ... existing fields ...

  Timer? _periodicSyncTimer;
  bool _isDisposed = false;

  /// Start periodic background sync.
  ///
  /// Useful for ensuring sync happens even without explicit triggers.
  /// Recommended interval: 5-15 minutes.
  void startPeriodicSync({Duration interval = const Duration(minutes: 5)}) {
    _checkNotDisposed();
    stopPeriodicSync();

    _periodicSyncTimer = Timer.periodic(interval, (_) {
      if (_syncIsEnabled && !_isDisposed) {
        runSync();
      }
    });
  }

  /// Stop periodic background sync.
  void stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  /// Dispose all resources.
  ///
  /// After calling dispose, this instance should not be used.
  void dispose() {
    if (_isDisposed) return;

    _isDisposed = true;
    stopPeriodicSync();
    unsubscribeFromServerMessages();
    _changesController.close();
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw StateError('Talon instance has been disposed');
    }
  }
}
```

#### 5.6 Add Schema Constants
**File:** `lib/src/schema/talon_schema.dart` (new file)

```dart
/// Schema definitions for Talon's messages table.
///
/// Use these in your database initialization to ensure
/// consistency with Talon's expectations.
class TalonSchema {
  TalonSchema._();

  /// SQL schema for the messages table (SQLite compatible).
  ///
  /// Use in your OfflineDatabase.init():
  /// ```dart
  /// await db.execute(TalonSchema.messagesTableSql);
  /// ```
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

CREATE INDEX IF NOT EXISTS idx_talon_messages_server_ts
  ON talon_messages(server_timestamp);
''';

  /// PostgreSQL schema for server-side messages table.
  ///
  /// Includes Row Level Security policies for Supabase.
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

  /// Column names for reference
  static const List<String> columnNames = [
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

#### 5.7 Update Public Exports
**File:** `lib/talon.dart`

```dart
library talon;

// Core
export 'src/talon/talon.dart' show Talon, TalonChange, TalonChangeSource;

// Models
export 'src/messages/message.dart';

// Interfaces
export 'src/offline_database/offline_database.dart';
export 'src/server_database/server_database.dart';

// Schema helpers
export 'src/schema/talon_schema.dart';

// HLC (for advanced users)
export 'src/hybrid_logical_clock/hlc.dart' show HLC;
```

### Completion Criteria

- [ ] `saveChange()` accepts `dynamic` values
- [ ] Auto-serialization works for: null, String, int, double, bool, DateTime, Map, List
- [ ] `message.typedValue` correctly deserializes all types
- [ ] `talon.changes` stream emits `TalonChange` objects
- [ ] `TalonChange` includes source (local/server)
- [ ] `talon.serverChanges` and `talon.localChanges` filter correctly
- [ ] `onMessagesReceived` marked as deprecated
- [ ] `startPeriodicSync()` and `stopPeriodicSync()` work correctly
- [ ] `dispose()` cleans up all resources
- [ ] `TalonSchema` constants exported and documented
- [ ] All new functionality covered by tests

### Deliverables
- Updated `lib/src/talon/talon.dart`
- Updated `lib/src/messages/message.dart`
- New `lib/src/schema/talon_schema.dart`
- Updated `lib/talon.dart`
- New tests for serialization and streams
- Git commit: `feat: API refinements - dynamic values, change stream, lifecycle`

---

## Stage 6: Batching Implementation

### Aim
Implement efficient batch operations to reduce network round-trips and improve sync performance for bulk operations.

### Scope

#### 6.1 Add Batch Send to ServerDatabase Interface
**File:** `lib/src/server_database/server_database.dart`

```dart
abstract class ServerDatabase {
  // ... existing methods ...

  /// Send multiple messages to the server in a single request.
  ///
  /// Returns a list of message IDs that were successfully synced.
  /// Default implementation sends messages one-by-one (override for efficiency).
  Future<List<String>> sendMessagesToServer({
    required List<Message> messages,
  }) async {
    final successfulIds = <String>[];
    for (final message in messages) {
      final success = await sendMessageToServer(message: message);
      if (success) {
        successfulIds.add(message.id);
      }
    }
    return successfulIds;
  }
}
```

#### 6.2 Add Batch Configuration to Talon
**File:** `lib/src/talon/talon.dart`

```dart
/// Configuration for Talon sync behavior
class TalonConfig {
  /// Maximum number of messages to send in a single batch
  final int batchSize;

  /// Debounce duration for sync operations
  final Duration syncDebounce;

  /// Whether to sync immediately on saveChange or wait for debounce
  final bool immediateSyncOnSave;

  const TalonConfig({
    this.batchSize = 50,
    this.syncDebounce = const Duration(milliseconds: 500),
    this.immediateSyncOnSave = false,
  });

  static const TalonConfig defaultConfig = TalonConfig();
}

class Talon {
  // ... existing fields ...

  final TalonConfig config;
  Timer? _syncDebounceTimer;
  bool _syncPending = false;

  Talon({
    required this.userId,
    required this.clientId,
    required ServerDatabase serverDatabase,
    required OfflineDatabase offlineDatabase,
    required String Function() createNewIdFunction,
    this.config = TalonConfig.defaultConfig,
  }) {
    // ... existing init ...
  }
}
```

#### 6.3 Implement Batched Sync to Server
**File:** `lib/src/talon/talon.dart`

```dart
Future<void> syncToServer() async {
  _checkNotDisposed();
  if (!_syncIsEnabled) return;

  final unsyncedMessages = await _offlineDatabase.getUnsyncedMessages();
  if (unsyncedMessages.isEmpty) return;

  // Process in batches
  for (int i = 0; i < unsyncedMessages.length; i += config.batchSize) {
    final batch = unsyncedMessages.skip(i).take(config.batchSize).toList();

    final successfulIds = await _serverDatabase.sendMessagesToServer(
      messages: batch,
    );

    if (successfulIds.isNotEmpty) {
      await _offlineDatabase.markMessagesAsSynced(successfulIds);
    }

    // If not all succeeded, stop processing further batches
    if (successfulIds.length < batch.length) {
      break;
    }
  }
}
```

#### 6.4 Add Debounced Sync
**File:** `lib/src/talon/talon.dart`

```dart
/// Schedule a sync operation, debouncing rapid calls.
void _scheduleSyncToServer() {
  if (!_syncIsEnabled) return;

  if (config.immediateSyncOnSave) {
    syncToServer();
    return;
  }

  _syncPending = true;
  _syncDebounceTimer?.cancel();
  _syncDebounceTimer = Timer(config.syncDebounce, () {
    if (_syncPending && !_isDisposed) {
      _syncPending = false;
      syncToServer();
    }
  });
}

Future<void> saveChange({...}) async {
  // ... existing logic until sync ...

  _scheduleSyncToServer();  // Instead of direct syncToServer()
}

/// Force immediate sync, bypassing debounce.
Future<void> forceSyncToServer() async {
  _syncDebounceTimer?.cancel();
  _syncPending = false;
  await syncToServer();
}
```

#### 6.5 Add Batch Save for Multiple Changes
**File:** `lib/src/talon/talon.dart`

```dart
/// Save multiple changes atomically.
///
/// All changes are applied locally, then synced together.
/// This is more efficient than calling saveChange multiple times.
///
/// Example:
/// ```dart
/// await talon.saveChanges([
///   TalonChange(table: 'todos', row: id, column: 'name', value: 'New name'),
///   TalonChange(table: 'todos', row: id, column: 'updated_at', value: DateTime.now()),
/// ]);
/// ```
Future<void> saveChanges(List<TalonChangeData> changes) async {
  _checkNotDisposed();

  final messages = <Message>[];

  for (final change in changes) {
    final serialized = _serializeValue(change.value);
    final hlcTimestamp = _hlcState.send();

    final message = Message(
      id: _createNewIdFunction(),
      table: change.table,
      row: change.row,
      column: change.column,
      dataType: change.dataType ?? serialized.type,
      value: serialized.value,
      localTimestamp: hlcTimestamp.toString(),
      userId: userId,
      clientId: clientId,
      hasBeenApplied: false,
      hasBeenSynced: false,
    );

    messages.add(message);
  }

  // Apply all locally
  for (final message in messages) {
    await _offlineDatabase.saveMessageFromLocalChange(message);
  }

  // Emit as single batch
  _changesController.add(TalonChange(
    source: TalonChangeSource.local,
    messages: messages,
  ));

  // Schedule sync
  _scheduleSyncToServer();
}

/// Data for a single change in a batch operation
class TalonChangeData {
  final String table;
  final String row;
  final String column;
  final dynamic value;
  final String? dataType;

  const TalonChangeData({
    required this.table,
    required this.row,
    required this.column,
    required this.value,
    this.dataType,
  });
}
```

#### 6.6 Update Example: Supabase Batch Implementation
**File:** Example implementation

```dart
class MyServerDatabaseImplementation extends ServerDatabase {
  // ... existing methods ...

  @override
  Future<List<String>> sendMessagesToServer({
    required List<Message> messages,
  }) async {
    if (messages.isEmpty) return [];

    try {
      final dataList = messages.map((m) {
        final dataMap = m.toMap();
        dataMap.remove('server_timestamp');
        dataMap.remove('hasBeenSynced');
        dataMap.remove('hasBeenApplied');
        return dataMap;
      }).toList();

      await supabase.from('messages').insert(dataList);

      return messages.map((m) => m.id).toList();
    } catch (e) {
      // On batch failure, fall back to individual sends
      return super.sendMessagesToServer(messages: messages);
    }
  }
}
```

### Completion Criteria

- [ ] `sendMessagesToServer()` added to ServerDatabase interface with default implementation
- [ ] `TalonConfig` class with batch size and debounce settings
- [ ] `syncToServer()` processes messages in batches
- [ ] Debounced sync prevents excessive network calls
- [ ] `saveChanges()` batch method implemented
- [ ] `forceSyncToServer()` bypasses debounce
- [ ] Example Supabase implementation uses batch insert
- [ ] Tests for batching and debounce behavior
- [ ] Performance test: 100 rapid saves → single batched sync

### Deliverables
- Updated `lib/src/server_database/server_database.dart`
- Updated `lib/src/talon/talon.dart` with batching
- Updated example implementations
- New `test/integration/batching_test.dart`
- Git commit: `feat: implement batching for efficient sync`

---

## Stage 7: Advanced Testing

### Aim
Expand test coverage to include edge cases, error scenarios, and performance characteristics. Ensure the library is robust under adverse conditions.

### Scope

#### 7.1 Edge Case Tests
**File:** `test/edge_cases/edge_cases_test.dart`

```dart
void main() {
  group('Edge Cases', () {
    test('handles empty sync gracefully', () async {
      // No messages to sync
    });

    test('handles very long string values', () async {
      // 1MB+ string value
    });

    test('handles special characters in values', () async {
      // Unicode, emojis, SQL injection attempts
    });

    test('handles rapid successive saves to same cell', () async {
      // 100 saves to same table/row/column in quick succession
    });

    test('handles concurrent saves to different cells', () async {
      // Parallel saves should not interfere
    });

    test('handles messages with null serverTimestamp', () async {
      // Unsynced messages
    });

    test('handles duplicate message IDs gracefully', () async {
      // Same message received twice
    });

    test('handles out-of-order message delivery', () async {
      // Messages arrive in non-chronological order
    });

    test('handles malformed HLC timestamps', () async {
      // Garbage in localTimestamp field
    });

    test('handles table/column names with special characters', () async {
      // Spaces, quotes, etc.
    });
  });
}
```

#### 7.2 Error Scenario Tests
**File:** `test/error_scenarios/error_scenarios_test.dart`

```dart
void main() {
  group('Error Scenarios', () {
    test('sync continues after single message failure', () async {
      // One message fails, others should still sync
    });

    test('marks only successful messages as synced', () async {
      // Partial batch success
    });

    test('handles server database exception', () async {
      // sendMessageToServer throws
    });

    test('handles offline database exception', () async {
      // applyMessageToLocalDataTable throws
    });

    test('recovers from interrupted sync', () async {
      // Sync starts, fails midway, resumes
    });

    test('handles subscription disconnection', () async {
      // WebSocket drops, should not crash
    });

    test('throws StateError when used after dispose', () async {
      talon.dispose();
      expect(() => talon.saveChange(...), throwsStateError);
    });
  });
}
```

#### 7.3 Clock Drift Tests
**File:** `test/edge_cases/clock_drift_test.dart`

```dart
void main() {
  group('Clock Drift', () {
    test('handles local clock behind server', () async {
      // Local clock is 1 hour behind
    });

    test('handles local clock ahead of server', () async {
      // Local clock is 1 hour ahead
    });

    test('HLC corrects for clock skew via receive', () async {
      // After receiving message from future, local HLC advances
    });

    test('conflict resolution works despite clock drift', () async {
      // Two clients with 5-minute clock difference
    });
  });
}
```

#### 7.4 Performance Tests
**File:** `test/performance/performance_test.dart`

```dart
void main() {
  group('Performance', () {
    test('sync 1000 messages under 5 seconds', () async {
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 1000; i++) {
        await talon.saveChange(
          table: 'items',
          row: 'item-$i',
          column: 'value',
          value: 'Value $i',
        );
      }

      await talon.forceSyncToServer();
      stopwatch.stop();

      expect(stopwatch.elapsed.inSeconds, lessThan(5));
    });

    test('batching reduces network calls', () async {
      var networkCalls = 0;
      // Mock that counts calls

      for (int i = 0; i < 100; i++) {
        await talon.saveChange(...);
      }
      await talon.forceSyncToServer();

      // With batch size 50, should be ~2 calls, not 100
      expect(networkCalls, lessThan(5));
    });

    test('message table query performance with 100k rows', () async {
      // Insert 100k messages, measure query time
    });

    test('memory usage stays bounded during large sync', () async {
      // No memory leaks during 10k message sync
    });
  });
}
```

#### 7.5 Concurrency Tests
**File:** `test/concurrency/concurrency_test.dart`

```dart
void main() {
  group('Concurrency', () {
    test('parallel saveChange calls are safe', () async {
      await Future.wait([
        talon.saveChange(table: 't', row: 'r1', column: 'c', value: 'v1'),
        talon.saveChange(table: 't', row: 'r2', column: 'c', value: 'v2'),
        talon.saveChange(table: 't', row: 'r3', column: 'c', value: 'v3'),
      ]);

      // All should be saved
      expect(offlineDb.messages.length, equals(3));
    });

    test('syncToServer and saveChange can run concurrently', () async {
      // Start a long sync, save new changes during it
    });

    test('multiple subscriptions receive all messages', () async {
      final received1 = <TalonChange>[];
      final received2 = <TalonChange>[];

      talon.changes.listen((c) => received1.add(c));
      talon.changes.listen((c) => received2.add(c));

      await talon.saveChange(...);

      expect(received1.length, equals(1));
      expect(received2.length, equals(1));
    });
  });
}
```

#### 7.6 Test Coverage Report
Add to `pubspec.yaml`:

```yaml
dev_dependencies:
  test: ^1.24.0
  coverage: ^1.6.0
```

Add script to run coverage:

```bash
#!/bin/bash
# scripts/coverage.sh
dart pub global activate coverage
dart test --coverage=coverage
dart pub global run coverage:format_coverage \
  --lcov \
  --in=coverage \
  --out=coverage/lcov.info \
  --packages=.dart_tool/package_config.json \
  --report-on=lib
genhtml coverage/lcov.info -o coverage/html
echo "Coverage report: coverage/html/index.html"
```

### Completion Criteria

- [ ] Edge case tests: 10+ scenarios
- [ ] Error scenario tests: 7+ scenarios
- [ ] Clock drift tests: 4+ scenarios
- [ ] Performance tests: 4+ benchmarks
- [ ] Concurrency tests: 3+ scenarios
- [ ] All tests pass
- [ ] Code coverage > 90%
- [ ] No flaky tests

### Deliverables
- `test/edge_cases/` directory
- `test/error_scenarios/` directory
- `test/performance/` directory
- `test/concurrency/` directory
- Coverage script and configuration
- Git commit: `test: add advanced test suite (edge cases, errors, performance)`

---

## Stage 8: Documentation

### Aim
Create comprehensive documentation that enables developers to understand, integrate, and troubleshoot Talon. Documentation should be clear, complete, and example-driven.

### Scope

#### 8.1 API Documentation (Dartdoc)
Add dartdoc comments to all public APIs:

**Example for `lib/src/talon/talon.dart`:**

```dart
/// A lightweight offline-first sync layer for Flutter applications.
///
/// Talon handles:
/// - Saving changes locally with immediate application
/// - Syncing changes to the server when online
/// - Receiving and merging server changes with conflict resolution
/// - Notifying listeners of data changes
///
/// ## Basic Usage
///
/// ```dart
/// // Initialize
/// final talon = Talon(
///   userId: 'user-123',
///   clientId: 'device-456',
///   serverDatabase: myServerDb,
///   offlineDatabase: myOfflineDb,
///   createNewIdFunction: () => uuid.v4(),
/// );
///
/// // Enable sync
/// talon.syncIsEnabled = true;
///
/// // Save a change
/// await talon.saveChange(
///   table: 'todos',
///   row: 'todo-1',
///   column: 'name',
///   value: 'Buy milk',
/// );
///
/// // Listen for changes
/// talon.changes.listen((change) {
///   print('${change.source}: ${change.messages.length} changes');
/// });
/// ```
///
/// ## Conflict Resolution
///
/// Talon uses Hybrid Logical Clocks (HLC) for conflict resolution.
/// When the same cell (table/row/column) is modified on multiple devices,
/// the change with the latest HLC timestamp wins. This provides
/// deterministic last-write-wins semantics even with clock skew.
///
/// See also:
/// - [OfflineDatabase] for implementing local storage
/// - [ServerDatabase] for implementing server communication
/// - [TalonSchema] for database schema helpers
class Talon {
  // ...
}
```

#### 8.2 Conceptual Documentation
**File:** `docs/concepts.mdx`

Topics to cover:
- What is offline-first?
- Message-based architecture
- Hybrid Logical Clocks explained
- Conflict resolution (last-write-wins)
- Eventual consistency
- When to use Talon

#### 8.3 Integration Guide
**File:** `docs/integration.mdx`

```markdown
# Integration Guide

## Prerequisites
- Flutter 3.0+
- Dart 3.0+
- A local database (sqflite, drift, etc.)
- A backend database (Supabase, Firebase, custom API)

## Step 1: Add Dependency
```yaml
dependencies:
  talon: ^1.0.0
```

## Step 2: Create Messages Table

### Local (SQLite)
```dart
await db.execute(TalonSchema.messagesTableSql);
```

### Server (PostgreSQL/Supabase)
```sql
-- Run in Supabase SQL editor
${TalonSchema.messagesTablePostgres}
```

## Step 3: Implement OfflineDatabase
[Detailed implementation guide with full example]

## Step 4: Implement ServerDatabase
[Detailed implementation guide with full example]

## Step 5: Initialize Talon
[Configuration options explained]

## Step 6: Use in Your App
[Repository pattern example]
```

#### 8.4 Troubleshooting Guide
**File:** `docs/troubleshooting.mdx`

```markdown
# Troubleshooting

## Common Issues

### Messages not syncing
1. Check `syncIsEnabled` is true
2. Verify network connectivity
3. Check server database implementation
4. Look for errors in `sendMessageToServer`

### Conflicts not resolving correctly
1. Ensure HLC timestamps are being used
2. Check `getExistingTimestamp` implementation
3. Verify message table indexes exist

### Performance issues
1. Enable batching with `TalonConfig`
2. Add database indexes
3. Consider pruning old messages

## Debugging

### Enable verbose logging
```dart
// Add to your app
Talon.debugMode = true;
```

### Inspect message state
```dart
final unsynced = await offlineDb.getUnsyncedMessages();
print('Unsynced: ${unsynced.length}');
```
```

#### 8.5 Architecture Documentation
**File:** `docs/architecture.mdx`

Include diagrams:
- System overview
- Sync flow
- Conflict resolution flow
- Message lifecycle

#### 8.6 README Update
**File:** `README.md`

```markdown
# Talon

A lightweight, dependency-free offline-first sync layer for Flutter.

[![pub package](https://img.shields.io/pub/v/talon.svg)](https://pub.dev/packages/talon)
[![tests](https://github.com/username/talon/actions/workflows/test.yml/badge.svg)](...)
[![coverage](https://codecov.io/gh/username/talon/branch/main/graph/badge.svg)](...)

## Features

- 🔌 **Dependency-free core** - Works with any database combination
- ⚡ **Instant local writes** - Zero latency for users
- 🔄 **Automatic sync** - Background sync when online
- 🤝 **Conflict resolution** - Deterministic with HLC
- 📡 **Real-time updates** - Subscribe to server changes
- 📦 **Batching** - Efficient network usage

## Quick Start

```dart
// 1. Initialize
final talon = Talon(
  userId: auth.userId,
  clientId: deviceId,
  serverDatabase: MyServerDb(),
  offlineDatabase: MyOfflineDb(),
  createNewIdFunction: () => uuid.v4(),
);

// 2. Enable sync
talon.syncIsEnabled = true;

// 3. Save data
await talon.saveChange(
  table: 'todos',
  row: todoId,
  column: 'name',
  value: 'Buy milk',
);

// 4. Listen for changes
talon.changes.listen((change) => refreshUI());
```

## Documentation

- [Getting Started](https://docs.talon.dev/getting-started)
- [Integration Guide](https://docs.talon.dev/integration)
- [API Reference](https://pub.dev/documentation/talon/latest/)
- [Examples](https://github.com/username/talon/tree/main/example)

## Examples

- [sqflite Example](example/sqflite_example) - Local SQLite database
- [Supabase Example](example/supabase_example) - Supabase backend

## License

MIT License - see [LICENSE](LICENSE)
```

### Completion Criteria

- [ ] All public APIs have dartdoc comments
- [ ] Conceptual documentation covers core concepts
- [ ] Integration guide with step-by-step instructions
- [ ] Troubleshooting guide with common issues
- [ ] Architecture documentation with diagrams
- [ ] README with quick start, features, and links
- [ ] Documentation builds without warnings
- [ ] Examples in documentation are tested and work

### Deliverables
- Dartdoc comments on all public APIs
- `docs/concepts.mdx`
- `docs/integration.mdx`
- `docs/troubleshooting.mdx`
- `docs/architecture.mdx`
- Updated `README.md`
- Git commit: `docs: add comprehensive documentation`

---

## Stage 9: Example Implementations

### Aim
Create two complete, separate, well-documented example applications demonstrating Talon with sqflite and Supabase.

### Scope

#### 9.1 Restructure Example Directory

```
example/
├── sqflite_example/           # Standalone sqflite example
│   ├── lib/
│   │   ├── main.dart
│   │   ├── database/
│   │   │   └── offline_database.dart
│   │   ├── repositories/
│   │   │   └── todo_repository.dart
│   │   ├── models/
│   │   │   └── todo.dart
│   │   └── ui/
│   │       └── todo_screen.dart
│   ├── pubspec.yaml
│   └── README.md
│
├── supabase_example/          # Standalone Supabase example
│   ├── lib/
│   │   ├── main.dart
│   │   ├── database/
│   │   │   ├── offline_database.dart
│   │   │   └── server_database.dart
│   │   ├── repositories/
│   │   │   └── todo_repository.dart
│   │   ├── models/
│   │   │   └── todo.dart
│   │   └── ui/
│   │       ├── todo_screen.dart
│   │       └── sync_indicator.dart
│   ├── supabase/
│   │   └── migrations/
│   │       └── 001_create_messages.sql
│   ├── pubspec.yaml
│   └── README.md
│
└── README.md                  # Overview of examples
```

#### 9.2 sqflite Example

**File:** `example/sqflite_example/README.md`

```markdown
# Talon + sqflite Example

A minimal example showing Talon with local SQLite storage.
This example demonstrates offline-first data storage without a server.

## Features Demonstrated
- Local message storage
- Conflict resolution
- Change notifications

## Running
```bash
cd example/sqflite_example
flutter run
```

## Key Files
- `lib/database/offline_database.dart` - OfflineDatabase implementation
- `lib/repositories/todo_repository.dart` - Using Talon in a repository
```

**File:** `example/sqflite_example/lib/database/offline_database.dart`

Complete, well-commented implementation:

```dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:talon/talon.dart';

/// SQLite implementation of Talon's OfflineDatabase.
///
/// This implementation stores:
/// - Talon messages in 'talon_messages' table
/// - Todo data in 'todos' table
class SqliteOfflineDatabase extends OfflineDatabase {
  late final Database _db;

  /// Initialize the database.
  ///
  /// Creates tables if they don't exist.
  @override
  Future<void> init() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'talon_example.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Create Talon messages table using provided schema
        await db.execute(TalonSchema.messagesTableSql);

        // Create your application tables
        await db.execute('''
          CREATE TABLE todos (
            id TEXT PRIMARY KEY,
            name TEXT DEFAULT '',
            is_done INTEGER DEFAULT 0,
            created_at TEXT
          )
        ''');
      },
    );
  }

  /// Apply a message to the actual data table.
  ///
  /// This is where Talon messages become real data updates.
  @override
  Future<bool> applyMessageToLocalDataTable(Message message) async {
    try {
      await _db.transaction((txn) async {
        // Try to update existing row
        final updated = await txn.rawUpdate(
          'UPDATE ${message.table} SET ${message.column} = ? WHERE id = ?',
          [message.typedValue, message.row],
        );

        // If no row existed, insert new one
        if (updated == 0) {
          await txn.rawInsert(
            'INSERT INTO ${message.table} (id, ${message.column}) VALUES (?, ?)',
            [message.row, message.typedValue],
          );
        }
      });
      return true;
    } catch (e) {
      print('Error applying message: $e');
      return false;
    }
  }

  // ... complete implementation with detailed comments ...
}
```

#### 9.3 Supabase Example

**File:** `example/supabase_example/README.md`

```markdown
# Talon + Supabase Example

A complete example showing Talon with Supabase backend.

## Features Demonstrated
- Offline-first with server sync
- Real-time updates across devices
- Conflict resolution
- Batched sync

## Setup

### 1. Supabase Project
1. Create a project at supabase.com
2. Run the migration in `supabase/migrations/`
3. Copy your project URL and anon key

### 2. Configuration
Create `lib/config.dart`:
```dart
const supabaseUrl = 'https://your-project.supabase.co';
const supabaseAnonKey = 'your-anon-key';
```

### 3. Run
```bash
flutter run
```

## Testing Offline
1. Enable airplane mode
2. Make changes (they're stored locally)
3. Disable airplane mode
4. Watch changes sync automatically
```

**File:** `example/supabase_example/supabase/migrations/001_create_messages.sql`

```sql
-- Talon messages table for Supabase
-- Run this in your Supabase SQL editor

CREATE TABLE messages (
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

-- Index for sync queries
CREATE INDEX idx_messages_sync ON messages(user_id, server_timestamp);
CREATE INDEX idx_messages_client ON messages(client_id);

-- Enable RLS
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view own messages" ON messages
  FOR SELECT USING (auth.uid()::text = user_id);

CREATE POLICY "Users can insert own messages" ON messages
  FOR INSERT WITH CHECK (auth.uid()::text = user_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
```

**File:** `example/supabase_example/lib/database/server_database.dart`

Complete implementation with batching:

```dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talon/talon.dart';

/// Supabase implementation of Talon's ServerDatabase.
///
/// Features:
/// - Batch message upload
/// - Real-time subscriptions
/// - Incremental sync
class SupabaseServerDatabase extends ServerDatabase {
  final SupabaseClient _client;

  SupabaseServerDatabase(this._client);

  @override
  Future<List<Message>> getMessagesFromServer({
    required int? lastSyncedServerTimestamp,
    required String clientId,
    required String userId,
  }) async {
    try {
      final response = await _client
          .from('messages')
          .select()
          .eq('user_id', userId)
          .neq('client_id', clientId)
          .gt('server_timestamp', lastSyncedServerTimestamp ?? 0)
          .order('server_timestamp');

      return response.map((row) => Message.fromMap(row)).toList();
    } catch (e) {
      print('Error fetching messages: $e');
      return [];
    }
  }

  @override
  Future<bool> sendMessageToServer({required Message message}) async {
    final result = await sendMessagesToServer(messages: [message]);
    return result.isNotEmpty;
  }

  @override
  Future<List<String>> sendMessagesToServer({
    required List<Message> messages,
  }) async {
    if (messages.isEmpty) return [];

    try {
      final data = messages.map((m) => {
        'id': m.id,
        'table_name': m.table,
        'row': m.row,
        'column': m.column,
        'data_type': m.dataType,
        'value': m.value,
        'local_timestamp': m.localTimestamp,
        'user_id': m.userId,
        'client_id': m.clientId,
      }).toList();

      await _client.from('messages').upsert(data);

      return messages.map((m) => m.id).toList();
    } catch (e) {
      print('Error sending messages: $e');
      return [];
    }
  }

  @override
  StreamSubscription subscribeToServerMessages({
    required String clientId,
    required String userId,
    required int? lastSyncedServerTimestamp,
    required void Function(List<Message>) onMessagesReceived,
  }) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen((data) {
          final messages = data
              .map((row) => Message.fromMap(row))
              .where((m) => m.clientId != clientId)
              .where((m) =>
                  m.serverTimestamp != null &&
                  m.serverTimestamp! > (lastSyncedServerTimestamp ?? 0))
              .toList();

          if (messages.isNotEmpty) {
            onMessagesReceived(messages);
          }
        });
  }
}
```

#### 9.4 Example Tests

Each example should include tests:

**File:** `example/sqflite_example/test/offline_database_test.dart`

```dart
void main() {
  group('SqliteOfflineDatabase', () {
    test('initializes without error', () async {
      final db = SqliteOfflineDatabase();
      await db.init();
      // ...
    });

    test('applies message to data table', () async {
      // ...
    });
  });
}
```

### Completion Criteria

- [ ] sqflite example is complete and runs
- [ ] Supabase example is complete and runs
- [ ] Both examples have README with setup instructions
- [ ] Both examples have tests
- [ ] Code is well-commented
- [ ] Examples demonstrate: init, save, sync, listen
- [ ] Supabase example includes SQL migration
- [ ] Examples work on iOS, Android, and Web

### Deliverables
- `example/sqflite_example/` complete package
- `example/supabase_example/` complete package
- `example/README.md` overview
- Tests for both examples
- Git commit: `example: add complete sqflite and Supabase examples`

---

## Stage 10: Production Polish

### Aim
Final preparations for v1.0.0 release: cleanup, verification, and pub.dev requirements.

### Scope

#### 10.1 Code Cleanup
- Remove all TODO comments (complete or convert to issues)
- Remove unused code
- Ensure consistent code style
- Run `dart format` on all files
- Fix all analyzer warnings

#### 10.2 Dependency Audit
**File:** `pubspec.yaml`

```yaml
name: talon
description: A lightweight, dependency-free offline-first sync layer for Flutter.
version: 1.0.0
repository: https://github.com/username/talon
issue_tracker: https://github.com/username/talon/issues
documentation: https://docs.talon.dev

environment:
  sdk: '>=3.0.0 <4.0.0'

# No runtime dependencies - truly dependency-free!

dev_dependencies:
  lints: ^3.0.0
  test: ^1.24.0
  coverage: ^1.6.0
```

#### 10.3 Changelog
**File:** `CHANGELOG.md`

```markdown
# Changelog

## [1.0.0] - 2024-XX-XX

### Added
- Core Talon sync engine
- Hybrid Logical Clock for conflict resolution
- Stream-based change notifications
- Batched sync operations
- Dynamic value serialization
- TalonSchema helpers
- Comprehensive test suite
- Complete documentation
- sqflite example
- Supabase example

### Changed
- `shouldApplyMessage` is now internal (not abstract)
- `saveChange` accepts dynamic values
- `onMessagesReceived` deprecated in favor of `changes` stream

### Fixed
- Missing await statements in sync operations
- Messages not marked as synced
- Incorrect unsynced message query

## [0.0.2] - 2024-XX-XX
- Initial prototype release
```

#### 10.4 License Verification
**File:** `LICENSE`

Ensure MIT license is properly formatted.

#### 10.5 CI/CD Setup
**File:** `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - run: dart analyze
      - run: dart format --set-exit-if-changed .
      - run: dart test --coverage=coverage
      - uses: codecov/codecov-action@v3
        with:
          files: coverage/lcov.info

  publish-dry-run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - run: dart pub publish --dry-run
```

#### 10.6 Pre-Release Checklist

```markdown
## Pre-Release Checklist

### Code Quality
- [ ] All tests pass
- [ ] Coverage > 90%
- [ ] No analyzer warnings
- [ ] Code formatted with `dart format`
- [ ] No TODO comments remaining

### Documentation
- [ ] README is complete
- [ ] All public APIs have dartdoc
- [ ] Examples run without errors
- [ ] CHANGELOG updated

### Package Requirements
- [ ] pubspec.yaml complete
- [ ] LICENSE file present
- [ ] `dart pub publish --dry-run` succeeds
- [ ] Package scores well on pub.dev preview

### Final Verification
- [ ] Fresh clone builds successfully
- [ ] Examples work on iOS
- [ ] Examples work on Android
- [ ] Examples work on Web
- [ ] Integration test with real Supabase
```

#### 10.7 Pub.dev Publication

```bash
# Final verification
dart pub publish --dry-run

# Publish
dart pub publish
```

### Completion Criteria

- [ ] All code cleanup complete
- [ ] All tests pass
- [ ] Coverage > 90%
- [ ] No analyzer warnings
- [ ] CHANGELOG complete
- [ ] CI/CD pipeline working
- [ ] `dart pub publish --dry-run` succeeds
- [ ] Fresh clone test passes
- [ ] Examples verified on iOS, Android, Web
- [ ] Package published to pub.dev

### Deliverables
- Clean codebase
- Complete CHANGELOG
- CI/CD configuration
- Published package on pub.dev
- Git tag: `v1.0.0`

---

## Version Milestones

| Version | Stage Complete | Key Features |
|---------|----------------|--------------|
| 0.0.3 | Stage 1 | Bug fixes |
| 0.1.0 | Stage 2-3 | HLC integration, internalized conflict resolution |
| 0.2.0 | Stage 4 | Core test suite |
| 0.5.0 | Stage 5-6 | API refinements, batching |
| 0.8.0 | Stage 7-8 | Advanced tests, documentation |
| 0.9.0 | Stage 9 | Complete examples |
| 1.0.0 | Stage 10 | Production ready |

---

## Appendix: File Change Summary

### New Files
```
lib/src/schema/talon_schema.dart
test/unit/message_test.dart
test/unit/hlc_test.dart
test/unit/serialization_test.dart
test/integration/talon_test.dart
test/integration/sync_flow_test.dart
test/integration/conflict_resolution_test.dart
test/integration/batching_test.dart
test/edge_cases/edge_cases_test.dart
test/error_scenarios/error_scenarios_test.dart
test/performance/performance_test.dart
test/concurrency/concurrency_test.dart
test/mocks/mock_offline_database.dart
test/mocks/mock_server_database.dart
test/test_utils.dart
docs/concepts.mdx
docs/integration.mdx
docs/troubleshooting.mdx
docs/architecture.mdx
example/sqflite_example/
example/supabase_example/
.github/workflows/ci.yml
scripts/coverage.sh
```

### Modified Files
```
lib/talon.dart
lib/src/talon/talon.dart
lib/src/messages/message.dart
lib/src/offline_database/offline_database.dart
lib/src/server_database/server_database.dart
lib/src/hybrid_logical_clock/hlc.dart
lib/src/hybrid_logical_clock/hlc.utils.dart
pubspec.yaml
README.md
CHANGELOG.md
```

### Deleted Files
```
example/sqflite_supabase_example/ (replaced by separate examples)
test/dart_offlne_first_test.dart (empty file)
```
