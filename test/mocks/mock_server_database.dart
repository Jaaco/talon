import 'dart:async';

import 'package:talon/talon.dart';

/// Mock implementation of ServerDatabase for testing.
class MockServerDatabase extends ServerDatabase {
  final List<Message> serverMessages = [];
  int _nextServerTimestamp = 1;
  final _messageController = StreamController<Message>.broadcast();
  bool shouldFailSend = false;

  @override
  Future<List<Message>> getMessagesFromServer({
    required int? lastSyncedServerTimestamp,
    required String clientId,
    required String userId,
  }) async {
    return serverMessages
        .where((m) =>
            m.serverTimestamp != null &&
            m.serverTimestamp! > (lastSyncedServerTimestamp ?? 0) &&
            m.clientId != clientId &&
            m.userId == userId)
        .toList();
  }

  @override
  Future<bool> sendMessageToServer({required Message message}) async {
    if (shouldFailSend) return false;

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
    shouldFailSend = false;
  }

  /// Simulate a message arriving from another client.
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

  int get messageCount => serverMessages.length;
}
