import 'dart:math';

import '../messages/message.dart';

/// Abstract interface for local database operations.
///
/// Implement this class to provide Talon with access to your local database
/// (e.g., sqflite, Drift, Hive).
abstract class OfflineDatabase {
  /// Initialize the database here.
  Future<void> init();

  /// Apply a message to the database.
  Future<bool> applyMessageToLocalDataTable(Message message);

  /// Apply a message to the message table
  Future<bool> applyMessageToLocalMessageTable(Message message);

  Future<void> saveLastSyncedServerTimestamp(int serverTimestamp);

  Future<int?> readLastSyncedServerTimestamp();

  Future<List<Message>> getUnsyncedMessages();

  Future<void> markMessagesAsSynced(List<String> syncedMessageIds);

  Future<bool> shouldApplyMessage(Message message);

  Future<bool> saveMessageFromServer(Message message) async {
    // Always save to message table first (for history/sync tracking)
    try {
      await applyMessageToLocalMessageTable(message);
    } catch (e) {
      return false;
    }

    // Apply to data table (may fail if table doesn't exist yet, etc.)
    try {
      await applyMessageToLocalDataTable(message);
    } catch (e) {
      // Message saved but not applied—this is acceptable
      // (e.g., table doesn't exist yet, schema mismatch)
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
