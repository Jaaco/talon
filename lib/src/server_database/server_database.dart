import 'dart:async';

import '../messages/message.dart';

/// Abstract interface for server-side database operations.
///
/// Implement this class to connect Talon to your backend
/// (Supabase, Firebase, custom API, etc.).
///
/// ## Example Implementation (Supabase)
/// ```dart
/// class SupabaseServerDatabase extends ServerDatabase {
///   final SupabaseClient _client;
///
///   SupabaseServerDatabase(this._client);
///
///   @override
///   Future<List<Message>> getMessagesFromServer({...}) async {
///     final response = await _client
///         .from('messages')
///         .select()
///         .eq('user_id', userId)
///         .neq('client_id', clientId)
///         .gt('server_timestamp', lastSyncedServerTimestamp ?? 0);
///     return response.map((row) => Message.fromMap(row)).toList();
///   }
///
///   // ... other methods
/// }
/// ```
abstract class ServerDatabase {
  /// Fetch messages from the server that haven't been synced locally.
  ///
  /// Parameters:
  /// - [lastSyncedServerTimestamp]: Only fetch messages with server_timestamp > this value
  /// - [clientId]: The current client's ID (exclude messages from this client)
  /// - [userId]: The current user's ID (only fetch this user's messages)
  ///
  /// Returns a list of messages to be saved locally.
  Future<List<Message>> getMessagesFromServer({
    required int? lastSyncedServerTimestamp,
    required String clientId,
    required String userId,
  });

  /// Send a single message to the server.
  ///
  /// Returns true if the message was successfully received by the server.
  Future<bool> sendMessageToServer({required Message message});

  /// Send multiple messages to the server in a single request.
  ///
  /// Returns a list of message IDs that were successfully synced.
  /// Override this method to implement efficient batch uploads.
  ///
  /// The default implementation sends messages one-by-one using
  /// [sendMessageToServer]. Override for better performance.
  ///
  /// ## Example (Supabase batch insert)
  /// ```dart
  /// @override
  /// Future<List<String>> sendMessagesToServer({
  ///   required List<Message> messages,
  /// }) async {
  ///   if (messages.isEmpty) return [];
  ///
  ///   try {
  ///     final data = messages.map((m) => m.toMap()..remove('hasBeenApplied')..remove('hasBeenSynced')).toList();
  ///     await supabase.from('messages').insert(data);
  ///     return messages.map((m) => m.id).toList();
  ///   } catch (e) {
  ///     // On batch failure, fall back to individual sends
  ///     return super.sendMessagesToServer(messages: messages);
  ///   }
  /// }
  /// ```
  Future<List<String>> sendMessagesToServer({
    required List<Message> messages,
  }) async {
    final successfulIds = <String>[];
    for (final message in messages) {
      final success = await sendMessageToServer(message: message);
      if (success) {
        successfulIds.add(message.id);
      }
    }
    return successfulIds;
  }

  /// Subscribe to real-time server messages.
  ///
  /// Parameters:
  /// - [clientId]: The current client's ID (filter out own messages)
  /// - [userId]: The current user's ID (only receive this user's messages)
  /// - [lastSyncedServerTimestamp]: Start timestamp for the subscription
  /// - [onMessagesReceived]: Callback when new messages arrive
  ///
  /// Returns a StreamSubscription that should be cancelled when done.
  StreamSubscription subscribeToServerMessages({
    required String clientId,
    required String userId,
    required int? lastSyncedServerTimestamp,
    required void Function(List<Message>) onMessagesReceived,
  });
}
