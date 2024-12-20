import '../messages/message.dart';

abstract class OnlineDatabase {
  Future<List<Message>> getMessagesFromServer({
    required String? lastSyncedServerTimestamp,
    required String clientId,
    required String userId,
  });
}
