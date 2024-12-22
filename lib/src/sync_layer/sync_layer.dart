import 'dart:async';

import 'package:talon/src/messages/message.dart';
import 'package:talon/src/offline_database/offline_database.dart';

import '../server_database/server_database.dart';

class SyncLayer {
  late final ServerDatabase _serverDatabase;
  late final OfflineDatabase _offlineDatabase;
  late final String Function() _createNewIdFunction;

  final String userId;
  final String clientId;

  StreamSubscription? _serverMessagesSubscription;

  void Function(List<Message>)?
      _onMessagesReceived; // can be used to selectively refresh states

  set onMessagesReceived(void Function(List<Message>) value) {
    _onMessagesReceived = value;

    if (!_syncIsEnabled) return;

    /// Resubscribe to stream to use the new callback, could be optimized
    unsubscribeFromServerMessages();
    subscribeToServerMessages();
  }

  bool _syncIsEnabled = false;

  set syncIsEnabled(bool value) {
    _syncIsEnabled = value;

    if (_syncIsEnabled) {
      runSync();
      subscribeToServerMessages();
    } else {
      unsubscribeFromServerMessages();
    }
  }

  SyncLayer({
    required this.userId,
    required this.clientId,
    required ServerDatabase serverDatabase,
    required OfflineDatabase offlineDatabase,
    required String Function() createNewIdFunction,
  }) {
    _serverDatabase = serverDatabase;

    _offlineDatabase = offlineDatabase;
    _createNewIdFunction = createNewIdFunction;
  }

  Future<void> startPeriodicSync({int minuteInterval = 5}) async {}

  Future<void> runSync() async {
    final completer = Completer<void>();
    syncToServer();
    syncFromServer();
    completer.complete();
  }

  Future<void> syncToServer() async {
    if (!_syncIsEnabled) return;

    final unsyncedMessages = await _offlineDatabase.getUnsyncedMessages();

    final successfullySyncedMessages = <String>[];

    for (final message in unsyncedMessages) {
      final wasSuccessful =
          await _serverDatabase.sendMessageToServer(message: message);

      if (wasSuccessful) {
        successfullySyncedMessages.add(message.id);
      }
    }
  }

  Future<void> syncFromServer() async {
    if (!_syncIsEnabled) return;

    final lastSyncedServerTimestamp =
        await _offlineDatabase.readLastSyncedServerTimestamp();

    final messagesFromServer = await _serverDatabase.getMessagesFromServer(
      userId: userId,
      clientId: clientId,
      lastSyncedServerTimestamp: lastSyncedServerTimestamp,
    );

    _offlineDatabase.saveMessagesFromServer(messagesFromServer);
  }

  void subscribeToServerMessages() async {
    _serverMessagesSubscription?.cancel();

    final lastSyncedServerTimestamp =
        await _offlineDatabase.readLastSyncedServerTimestamp();

    _serverMessagesSubscription = _serverDatabase.subscribeToServerMessages(
      clientId: clientId,
      userId: userId,
      lastSyncedServerTimestamp: lastSyncedServerTimestamp,
      onMessagesReceived: (List<Message> messages) async {
        // Wait for the messages to be processed and saved in the local database
        await _offlineDatabase.saveMessagesFromServer(messages);

        // Notify listeners that new messages have been received
        _onMessagesReceived?.call(messages);
      },
    );
  }

  void unsubscribeFromServerMessages() {
    _serverMessagesSubscription?.cancel();
  }

  Future<void> saveChange({
    required String table,
    required String row,
    required String column,
    required String value,
    String dataType = '',
  }) async {
    final message = Message(
      id: _createNewIdFunction(),
      table: table,
      row: row,
      column: column,
      dataType: dataType,
      value: value,
      localTimestamp: DateTime.now().toString(), // todo(jacoo): get HLC state
      userId: userId,
      clientId: clientId,
      hasBeenApplied: false,
      hasBeenSynced: false,
    );

    await _offlineDatabase.saveMessageFromLocalChange(message);

    await syncToServer();
  }

  /// NOTE: the following will only work partially, if the online database has
  /// the default behaviour like supabase of using a single increasing integer
  /// for the whole 'messages' table instead of one per user.
  ///
  /// This code makes sure that no messages are missed due to any errors in syncing
  /// run this code regularly (ie. on app start) to ensure that the database
  /// fixes itself.
  void validateServerTimestamp() {
    // todo(jacoo): check:
    // 1. if all messages are in local db
    // check whatever highest timestamp is, and check if count is equal to it
    // 2. if highest timestamp is the one saved in shared prefs
  }
}
