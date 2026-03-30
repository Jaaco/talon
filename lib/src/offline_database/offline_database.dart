import 'dart:math';

import '../hybrid_logical_clock/hlc.dart';
import '../messages/message.dart';

/// Abstract interface for local database operations.
///
/// Implement this class to provide Talon with access to your local database
/// (e.g., sqflite, Drift, Hive).
///
/// ## Required Methods
/// You must implement these methods:
/// - [init] - Initialize your database
/// - [applyMessageToLocalDataTable] - Apply changes to your data tables
/// - [applyMessageToLocalMessageTable] - Store messages for sync tracking
/// - [getExistingTimestamp] - Query for existing message timestamps
/// - [saveLastSyncedServerTimestamp] / [readLastSyncedServerTimestamp] - Track sync progress
/// - [getUnsyncedMessages] - Get messages that need to be synced
/// - [markMessagesAsSynced] - Mark messages as successfully synced
///
/// ## Conflict Resolution
/// Conflict resolution is handled automatically by Talon using HLC timestamps.
/// You only need to implement [getExistingTimestamp] to query for existing
/// timestamps - Talon will handle the comparison logic.
abstract class OfflineDatabase {
  /// Initialize the database.
  ///
  /// Create your tables here, including the messages table.
  /// See [TalonSchema] for the recommended messages table schema.
  Future<void> init();

  /// Apply a message to the actual data table.
  ///
  /// This method is called when a message should be applied to your data.
  /// Implement the logic to UPDATE or INSERT the value into your table.
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Future<bool> applyMessageToLocalDataTable(Message message) async {
  ///   await db.rawUpdate(
  ///     'UPDATE ${message.table} SET ${message.column} = ? WHERE id = ?',
  ///     [message.value, message.row],
  ///   );
  ///   return true;
  /// }
  /// ```
  Future<bool> applyMessageToLocalDataTable(Message message);

  /// Store a message in the messages tracking table.
  ///
  /// This is used for sync tracking and conflict resolution.
  /// The message should be stored even if [applyMessageToLocalDataTable] fails.
  Future<bool> applyMessageToLocalMessageTable(Message message);

  /// Get the most recent HLC timestamp for a specific cell.
  ///
  /// Returns the `local_timestamp` of the most recent message for the given
  /// table/row/column combination, or null if no message exists.
  ///
  /// This is used by [shouldApplyMessage] to determine if an incoming
  /// message should overwrite the existing value.
  ///
  /// Example implementation:
  /// ```dart
  /// @override
  /// Future<String?> getExistingTimestamp({
  ///   required String table,
  ///   required String row,
  ///   required String column,
  /// }) async {
  ///   final result = await db.rawQuery('''
  ///     SELECT local_timestamp FROM messages
  ///     WHERE table_name = ? AND row = ? AND "column" = ?
  ///     ORDER BY local_timestamp DESC
  ///     LIMIT 1
  ///   ''', [table, row, column]);
  ///
  ///   if (result.isEmpty) return null;
  ///   return result.first['local_timestamp'] as String?;
  /// }
  /// ```
  Future<String?> getExistingTimestamp({
    required String table,
    required String row,
    required String column,
  });

  /// Save the last successfully synced server timestamp.
  ///
  /// This is used for incremental sync - only messages with a higher
  /// server timestamp will be fetched on the next sync.
  Future<void> saveLastSyncedServerTimestamp(int serverTimestamp);

  /// Read the last successfully synced server timestamp.
  ///
  /// Returns null if no sync has occurred yet.
  Future<int?> readLastSyncedServerTimestamp();

  /// Get all messages that haven't been synced to the server yet.
  ///
  /// These are messages where `hasBeenSynced = false`.
  Future<List<Message>> getUnsyncedMessages();

  /// Mark the given messages as successfully synced.
  ///
  /// Called after messages have been successfully sent to the server.
  Future<void> markMessagesAsSynced(List<String> syncedMessageIds);

  /// Determine if a message should be applied based on HLC comparison.
  ///
  /// This method is NOT abstract - Talon handles conflict resolution internally.
  /// It uses [getExistingTimestamp] to find the current timestamp, then
  /// compares using HLC ordering.
  ///
  /// Returns true if the message should be applied (newer or no existing value).
  Future<bool> shouldApplyMessage(Message message) async {
    final existingTimestamp = await getExistingTimestamp(
      table: message.table,
      row: message.row,
      column: message.column,
    );

    // No existing value for this cell - always apply
    if (existingTimestamp == null) {
      return true;
    }

    // Compare HLC timestamps - higher (later) timestamp wins
    final comparison = HLC.compareTimestamps(
      message.localTimestamp,
      existingTimestamp,
    );

    // Apply if new message has higher timestamp
    // If equal, don't apply (existing value wins ties)
    return comparison > 0;
  }

  /// Save a message received from the server.
  ///
  /// The message is always saved to the message table for tracking.
  /// It is only applied to the data table if [shouldApplyMessage] returns true.
  Future<bool> saveMessageFromServer(Message message) async {
    // Always save to message table first (for history/sync tracking)
    try {
      await applyMessageToLocalMessageTable(message);
    } catch (e) {
      return false;
    }

    // Check if this message should be applied (conflict resolution)
    final shouldApply = await shouldApplyMessage(message);

    if (shouldApply) {
      // Apply to data table
      try {
        await applyMessageToLocalDataTable(message);
      } catch (e) {
        // Message saved but not applied - this is acceptable
        // (e.g., table doesn't exist yet, schema mismatch)
      }
    }

    return true;
  }

  Future<void> saveMessagesFromServer(List<Message> messages) async {
    final futureResults = <Future<bool>>[];
    for (final message in messages) {
      final result = saveMessageFromServer(message);

      futureResults.add(result);
    }

    final result = await Future.wait(futureResults);

    final allMessagesWereSaved = !result.any((r) => r == false);

    if (allMessagesWereSaved && messages.isNotEmpty) {
      final highestServerTimestamp = messages.fold(0, (val, message) {
        if (message.serverTimestamp == null) return val;

        return max(val, message.serverTimestamp!);
      });

      await saveLastSyncedServerTimestamp(highestServerTimestamp);
    }
  }

  /// Saves a change that has just been made on the client.
  ///
  /// First applies the message to the data table, then saves it to the
  /// message table for sync tracking.
  Future<bool> saveMessageFromLocalChange(Message message) async {
    try {
      await applyMessageToLocalDataTable(message);
    } catch (e) {
      return false;
    }

    try {
      await applyMessageToLocalMessageTable(message);
    } catch (e) {
      return false;
    }

    return true;
  }
}
