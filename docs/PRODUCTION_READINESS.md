# Talon Production Readiness Checklist

> A comprehensive list of features, fixes, and requirements needed before Talon can be considered production-ready (v1.0.0).

---

## Status Legend

- [ ] Not started
- [~] In progress / Partially complete
- [x] Complete

---

## 1. Critical Bugs (Must Fix)

### 1.1 Code Correctness

- [ ] **Missing `await` statements** - `offline_database.dart` lines 28, 34, 73, 79
- [ ] **`markMessagesAsSynced()` never called** - `talon.dart` line 80 collects IDs but doesn't use them
- [ ] **`runSync()` doesn't await** - `talon.dart` lines 61-62, sync operations run in parallel without waiting
- [ ] **`getUnsyncedMessages()` returns all messages** - Example implementation missing `WHERE hasBeenSynced = 0`
- [ ] **HLC not integrated** - `talon.dart` line 136 uses `DateTime.now().toString()` instead of HLC

### 1.2 Data Integrity

- [ ] **No transaction safety** - Multiple messages can partially apply
- [ ] **No duplicate message detection** - Same message could be applied twice
- [ ] **No message ordering guarantee** - Batch operations don't preserve order
- [ ] **Server timestamp validation missing** - `validateServerTimestamp()` is empty stub

---

## 2. Core Functionality (Must Have)

### 2.1 Sync Engine

- [x] Basic sync to server
- [x] Basic sync from server
- [x] Real-time subscription to server changes
- [ ] **Retry logic for failed syncs** - Currently fails silently
- [ ] **Batch message upload** - Currently sends one-by-one
- [ ] **Incremental sync validation** - Detect and recover from missed messages
- [ ] **Sync status reporting** - No way to know if sync succeeded/failed
- [ ] **Network connectivity detection** - No automatic online/offline detection

### 2.2 Conflict Resolution

- [~] HLC implementation exists
- [ ] **HLC integration into message creation**
- [ ] **HLC integration into conflict comparison**
- [ ] **Deterministic tie-breaking** - When HLC timestamps are equal
- [ ] **Conflict notification** - Let developers know when conflicts occur

### 2.3 Offline Support

- [x] Messages stored locally
- [x] Messages queued for sync
- [ ] **Offline duration handling** - Very long offline periods (months)
- [ ] **Storage limits** - No strategy for message table growth
- [ ] **Message pruning** - No way to clean up old synced messages

### 2.4 Change Notification

- [~] Callback-based notification exists
- [ ] **Stream-based API** - More idiomatic Dart
- [ ] **Source identification** - Distinguish local vs server changes
- [ ] **Table filtering** - Subscribe to specific tables only
- [ ] **Batched notifications** - Avoid UI thrashing on bulk sync

---

## 3. API Completeness (Should Have)

### 3.1 Value Handling

- [ ] **Accept dynamic values** - Currently strings only
- [ ] **Auto-serialization** - bool, int, double, Map, List
- [ ] **Type preservation** - `dataType` field used properly
- [ ] **Deserialization helper** - `message.typedValue` getter

### 3.2 Lifecycle Management

- [ ] **`dispose()` method** - Clean up subscriptions and timers
- [ ] **`startPeriodicSync()`** - Currently empty stub
- [ ] **`stopPeriodicSync()`** - Timer management
- [ ] **Graceful shutdown** - Flush pending syncs before dispose

### 3.3 Configuration

- [ ] **Sync debouncing** - Avoid syncing on every keystroke
- [ ] **Batch size configuration** - Control upload chunk size
- [ ] **Retry configuration** - Max retries, backoff strategy
- [ ] **Logging/debugging hooks** - Visibility into sync operations

### 3.4 Error Handling

- [ ] **Typed exceptions** - `TalonSyncException`, `TalonConflictException`
- [ ] **Error recovery callbacks** - Let app handle failures
- [ ] **Partial sync recovery** - Resume from where it failed
- [ ] **Corrupted message handling** - Skip or quarantine bad messages

---

## 4. Interface Design (Should Have)

### 4.1 OfflineDatabase

- [x] `init()`
- [x] `applyMessageToLocalDataTable()`
- [x] `applyMessageToLocalMessageTable()`
- [x] `saveLastSyncedServerTimestamp()`
- [x] `readLastSyncedServerTimestamp()`
- [x] `getUnsyncedMessages()`
- [x] `markMessagesAsSynced()`
- [ ] **`getExistingTimestamp()`** - New method for internalized conflict resolution
- [ ] **Remove `shouldApplyMessage()` from abstract** - Make it internal

### 4.2 ServerDatabase

- [x] `getMessagesFromServer()`
- [x] `sendMessageToServer()`
- [x] `subscribeToServerMessages()`
- [ ] **`sendMessagesToServer()` (batch)** - Reduce round trips
- [ ] **`unsubscribe()` return value** - Currently returns `StreamSubscription`

### 4.3 Message Model

- [x] Core fields
- [x] Serialization
- [x] Equality
- [ ] **`typedValue` getter**
- [ ] **`fromServerJson()` factory** - Preset `hasBeenSynced = true`
- [ ] **`fromLocalJson()` factory** - Preset `hasBeenApplied = true`
- [ ] **Validation** - Ensure required fields present

---

## 5. Developer Experience (Nice to Have)

### 5.1 Schema Helpers

- [ ] **`TalonSchema.messagesTableSql`** - SQLite schema
- [ ] **`TalonSchema.messagesTablePostgres`** - PostgreSQL schema
- [ ] **`TalonSchema.messagesTableDrift`** - Drift table definition
- [ ] **Schema validation utility** - Check if table matches expected schema

### 5.2 Documentation

- [~] Conceptual documentation (`docs/index.mdx`)
- [ ] **API documentation** - Dartdoc comments on all public APIs
- [ ] **Integration guides** - sqflite, Drift, Supabase, Firebase
- [ ] **Troubleshooting guide** - Common issues and solutions
- [ ] **Architecture diagram** - Visual overview
- [ ] **Example: Multi-table app** - Beyond simple todo
- [ ] **Example: Conflict handling UI** - Show conflicts to users
- [ ] **Migration guide** - From other sync solutions

### 5.3 Debugging Tools

- [ ] **Sync status inspector** - View pending/synced messages
- [ ] **Message timeline visualizer** - Debug conflict resolution
- [ ] **Verbose logging mode** - Detailed sync logs
- [ ] **Test utilities** - Helpers for unit testing Talon integrations

---

## 6. Testing (Must Have)

### 6.1 Unit Tests

- [ ] **Message model tests** - Serialization, equality, copyWith
- [ ] **HLC tests** - Ordering, pack/unpack, drift handling
- [ ] **Talon core tests** - saveChange, sync methods
- [ ] **Serialization tests** - All data types

### 6.2 Integration Tests

- [ ] **Full sync flow** - Local change → server → other client
- [ ] **Conflict resolution** - Concurrent edits resolve correctly
- [ ] **Offline/online transitions** - Queue, reconnect, sync
- [ ] **Long offline period** - Bulk sync on reconnect
- [ ] **Subscription reconnection** - Handle dropped connections

### 6.3 Edge Case Tests

- [ ] **Empty sync** - No messages to sync
- [ ] **Large message** - Very long string values
- [ ] **Rapid changes** - Many changes in quick succession
- [ ] **Duplicate messages** - Same message received twice
- [ ] **Out-of-order messages** - Server delivers messages non-sequentially
- [ ] **Clock skew** - Local clock significantly off
- [ ] **Partial batch failure** - Some messages fail to sync

### 6.4 Performance Tests

- [ ] **Sync 1000 messages** - Bulk operation performance
- [ ] **10 concurrent clients** - Multi-device scenario
- [ ] **Message table with 100k rows** - Query performance
- [ ] **Memory usage** - No leaks during extended operation

---

## 7. Security Considerations (Should Address)

### 7.1 Data Protection

- [ ] **No sensitive data in logs** - Ensure values aren't logged
- [ ] **SQL injection prevention** - Document parameterized queries
- [ ] **Message tampering detection** - Optional message signing

### 7.2 Authentication

- [ ] **Document auth requirements** - userId must be validated server-side
- [ ] **Document RLS patterns** - Row Level Security examples
- [ ] **Token refresh handling** - What happens when auth expires mid-sync

### 7.3 Privacy

- [ ] **Document data residency** - Messages table contains all historical data
- [ ] **Deletion strategy** - How to handle "right to be forgotten"
- [ ] **Encryption at rest** - Document local DB encryption options

---

## 8. Platform Compatibility (Should Verify)

### 8.1 Flutter Platforms

- [ ] **iOS** - Tested and working
- [ ] **Android** - Tested and working
- [ ] **Web** - Tested (IndexedDB considerations)
- [ ] **macOS** - Tested
- [ ] **Windows** - Tested
- [ ] **Linux** - Tested

### 8.2 Backend Compatibility

- [ ] **Supabase** - Example provided and tested
- [ ] **Firebase Firestore** - Example provided
- [ ] **Firebase Realtime Database** - Example provided
- [ ] **Custom REST API** - Example provided
- [ ] **GraphQL** - Example provided

### 8.3 Local Database Compatibility

- [ ] **sqflite** - Example provided and tested
- [ ] **Drift (moor)** - Example provided
- [ ] **Hive** - Example provided
- [ ] **Isar** - Example provided
- [ ] **ObjectBox** - Example provided

---

## 9. Package Quality (Must Have for pub.dev)

### 9.1 Pub.dev Requirements

- [x] `pubspec.yaml` complete
- [x] `LICENSE` file
- [x] `README.md`
- [x] `CHANGELOG.md`
- [ ] **Example in `example/` directory** - Currently in subdirectory
- [ ] **Dartdoc coverage > 80%**
- [ ] **No analyzer warnings**
- [ ] **All tests passing**

### 9.2 Package Metadata

- [x] Repository URL
- [x] Homepage/documentation URL
- [ ] **Issue tracker URL**
- [ ] **Funding links** (optional)
- [ ] **Screenshots** (optional)
- [ ] **Topics/tags**

### 9.3 Version Management

- [ ] **Semantic versioning** - MAJOR.MINOR.PATCH
- [ ] **Breaking change documentation**
- [ ] **Deprecation warnings** - Before removing APIs
- [ ] **Migration guides** - For each major version

---

## 10. Post-1.0 Considerations (Future)

### 10.1 Advanced Features

- [ ] **Selective sync** - Sync only certain tables/rows
- [ ] **Compression** - Reduce message size for large values
- [ ] **Message expiry** - Auto-delete messages after N days
- [ ] **Sync priorities** - Some changes sync before others
- [ ] **Offline queue management** - Reorder, cancel pending changes

### 10.2 Ecosystem

- [ ] **`talon_sqflite` adapter package**
- [ ] **`talon_drift` adapter package**
- [ ] **`talon_supabase` adapter package**
- [ ] **`talon_firebase` adapter package**
- [ ] **DevTools extension** - Visualize sync state
- [ ] **Code generation** - Type-safe repositories

### 10.3 Enterprise Features

- [ ] **Multi-tenant support** - Multiple users per device
- [ ] **Workspace/team sync** - Shared data between users
- [ ] **Audit logging** - Who changed what when
- [ ] **Sync quotas** - Limit messages per user/time period

---

## Production Readiness Summary

### Minimum Viable Production (v0.5.0)

| Category | Items Required |
|----------|---------------|
| Critical Bugs | All 9 items |
| Core Functionality | Sync engine (5), Conflict resolution (4) |
| Testing | Unit tests (4), Integration tests (3) |
| **Total** | **~25 items** |

### Solid Production (v1.0.0)

| Category | Items Required |
|----------|---------------|
| All of v0.5.0 | ~25 items |
| API Completeness | All 16 items |
| Interface Design | All 12 items |
| Testing | All items |
| Package Quality | All pub.dev items |
| **Total** | **~60 items** |

### Current State Assessment

```
Critical Bugs:        0/9  complete  [░░░░░░░░░░] 0%
Core Functionality:   6/18 complete  [███░░░░░░░] 33%
API Completeness:     0/16 complete  [░░░░░░░░░░] 0%
Interface Design:     7/14 complete  [█████░░░░░] 50%
Developer Experience: 1/15 complete  [░░░░░░░░░░] 7%
Testing:              0/22 complete  [░░░░░░░░░░] 0%
Security:             0/8  complete  [░░░░░░░░░░] 0%
Package Quality:      5/12 complete  [████░░░░░░] 42%
─────────────────────────────────────────────────
Overall:              19/114         [██░░░░░░░░] 17%
```

---

## Priority Order for Production

1. **Critical bugs** - Data integrity depends on this
2. **HLC integration** - Correct conflict resolution
3. **Core testing** - Validate the fixes work
4. **Conflict resolution internalization** - Remove developer footgun
5. **API improvements** - Better developer experience
6. **Documentation** - Enable adoption
7. **Additional tests** - Edge cases and performance
8. **Package polish** - pub.dev requirements

---

## Definition of Done

A feature is considered "done" when:

1. Code is implemented
2. Unit tests pass
3. Integration tests pass (if applicable)
4. Dartdoc comments added
5. Example updated (if applicable)
6. CHANGELOG updated
7. No analyzer warnings
