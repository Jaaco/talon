import '../messages/message.dart';

// todo(jacoo): make all local methods private once the API is known
abstract class OfflineDatabase {
  /// Initialize the database here.
  Future<void> init();

  /// Apply a message to the database.
  Future<bool> applyMessageToLocalDataTable(Message message);

  /// Apply a message to the message table
  Future<bool> applyMessageToLocalMessageTable(Message message);

  Future<void> saveLastSyncedServerTimestamp(String serverTimestamp);

  Future<String?> readLastSyncedServerTimestamp();

  Future<bool> saveMessageFromServer(Message message) async {
    try {
      applyMessageToLocalMessageTable(message);
    } catch (e) {
      return Future.value(false);
    }

    try {
      applyMessageToLocalDataTable(message);
    } catch (e) {
      return Future.value(false);
    }

    return Future.value(true);
  }

  Future<void> saveMessagesFromServer(List<Message> messages) async {
    for (final message in messages) {
      saveMessageFromServer(message);
    }
  }

  /// Saves a change that has just been made on the client.
  ///
  /// First tries to apply the message, and only if successful does it save the message
  /// to the message table.
  /// Could in the future be saved to the message table either way, and marked with a bool
  /// whether it has been applied locally, which is maybe a necessary field either way
  Future<bool> saveMessageFromLocalChange(Message message) async {
    try {
      applyMessageToLocalDataTable(message);
    } catch (e) {
      return Future.value(false);
    }

    try {
      applyMessageToLocalMessageTable(message);
    } catch (e) {
      return Future.value(false);
    }

    return Future.value(true);
  }
}
