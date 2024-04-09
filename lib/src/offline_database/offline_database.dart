import 'package:dart_offlne_first/src/messages/message.dart';

// TODO: atomic apply for local message & data table
abstract class OfflineDatabase {
  /// Fetch the ids of all messages in the local messages table.
  Future<List<String>> getAllLocalMessageIds();

  /// Apply a message to the database.
  Future<bool> applyMessageToLocalDataTable(Message message);

  Future<bool> applyMessageToLocalMessageTable(Message message);

  Future<bool> applyMessageLocally(Message message) async {
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
