import 'dart:async';

import '../messages/message.dart';

abstract class ServerDatabase {
  Future<List<Message>> getMessagesFromServer({
    required int? lastSyncedServerTimestamp,
    required String clientId,
    required String userId,
  });

  /// Must return true if the message was received by the server
  Future<bool> sendMessageToServer({required Message message});

  StreamSubscription subscribeToServerMessages({
    required String clientId,
    required String userId,
    required int? lastSyncedServerTimestamp,
    required void Function(List<Message>) onMessagesReceived,
  });
}
