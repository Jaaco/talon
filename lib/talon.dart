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
/// await talon.saveChange(
///   table: 'todos',
///   row: 'todo-1',
///   column: 'name',
///   value: 'Buy milk',
/// );
/// ```
library talon;

// Core
export 'src/talon/talon.dart';

// Interfaces (implement these for your database)
export 'src/offline_database/offline_database.dart';
export 'src/server_database/server_database.dart';

// Models
export 'src/messages/message.dart';

// HLC (for advanced users who need direct access)
export 'src/hybrid_logical_clock/hlc.dart' show HLC;
