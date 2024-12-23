import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talon/talon.dart';

class MyServerDatabaseImplementation extends ServerDatabase {
  final supabase = Supabase.instance.client;

  @override
  Future<List<Message>> getMessagesFromServer({
    required int? lastSyncedServerTimestamp,
    required String clientId,
    required String userId,
  }) async {
    try {
      final messagesRaw = await supabase
          .from('messages')
          .select()
          .eq('user_id', userId)
          .gt('server_timestamp', lastSyncedServerTimestamp ?? -1)
          .neq('client_id', clientId);

      return messagesRaw.map(Message.fromMap).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<bool> sendMessageToServer({required Message message}) async {
    try {
      final dataMap = message.toMap();
      dataMap.remove('server_timestamp');
      dataMap.remove('hasBeenSynced');
      dataMap.remove('hasBeenApplied');
      await supabase.from('messages').insert(dataMap).select();

      return true;
    } catch (e) {
      // todo(jacoo): if 'already exists exception' return true
      return false;
    }
  }

  @override
  StreamSubscription subscribeToServerMessages({
    required String clientId,
    required String userId,
    required int? lastSyncedServerTimestamp,
    required void Function(List<Message>) onMessagesReceived,
  }) {
    return supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        // .eq('user_id', userId)
        .gt('server_timestamp', lastSyncedServerTimestamp ?? -1)
        // .neq('client_id', '')
        .listen(
          (data) {
            final allMessages = data.map(Message.fromMap).toList();

            /// The following misses the fact that this device might be missing
            /// it's own messages, for example due to a reinstallation. We can't
            /// Though in the subscription, this is problably not necesesary.
            final relevantMessages = allMessages.where(
              (message) {
                return message.clientId != clientId;
              },
            ).toList();

            onMessagesReceived(relevantMessages);
          },
        );
  }
}
