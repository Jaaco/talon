/// Talon - A lightweight offline-first sync layer for Flutter.
///
/// Talon provides a dependency-free synchronization layer that works with
/// any local database (sqflite, Drift, etc.) and any remote backend
/// (Supabase, Firebase, custom APIs).
///
/// ## Features
/// - Immediate local writes with zero latency
/// - Automatic background sync when online
/// - Conflict resolution using Hybrid Logical Clocks (HLC)
/// - Real-time updates via server subscriptions
/// - Batching for efficient network usage
/// - Stream-based change notifications
///
/// ## Usage
/// ```dart
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
/// // Save changes (accepts any value type)
/// await talon.saveChange(
///   table: 'todos',
///   row: 'todo-1',
///   column: 'name',
///   value: 'Buy milk',
/// );
///
/// // Listen for changes
/// talon.changes.listen((change) {
///   if (change.affectsTable('todos')) {
///     refreshTodoList();
///   }
/// });
///
/// // Cleanup when done
/// talon.dispose();
/// ```
library talon;

// Core
export 'src/talon/talon.dart'
    show Talon, TalonChange, TalonChangeSource, TalonChangeData, TalonConfig;

// Interfaces (implement these for your database)
export 'src/offline_database/offline_database.dart';
export 'src/server_database/server_database.dart';

// Models
export 'src/messages/message.dart';

// Schema helpers
export 'src/schema/talon_schema.dart';

// HLC (for advanced users who need direct access)
export 'src/hybrid_logical_clock/hlc.dart' show HLC;
