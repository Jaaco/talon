import 'dart:async';

import 'package:talon/src/hybrid_logical_clock/hlc.dart';
import 'package:talon/src/hybrid_logical_clock/hlc.state.dart';
import 'package:talon/src/messages/message.dart';
import 'package:talon/src/offline_database/offline_database.dart';

import '../server_database/server_database.dart';

/// A lightweight offline-first sync layer for Flutter applications.
///
/// Talon handles:
/// - Saving changes locally with immediate application
/// - Syncing changes to the server when online
/// - Receiving and merging server changes with conflict resolution
/// - Notifying listeners of data changes
///
/// ## Basic Usage
///
/// ```dart
/// final talon = Talon(
///   userId: 'user-123',
///   clientId: 'device-456',
///   serverDatabase: myServerDb,
///   offlineDatabase: myOfflineDb,
///   createNewIdFunction: () => uuid.v4(),
/// );
///
/// talon.syncIsEnabled = true;
///
/// await talon.saveChange(
///   table: 'todos',
///   row: 'todo-1',
///   column: 'name',
///   value: 'Buy milk',
/// );
/// ```
class Talon {
  late final ServerDatabase _serverDatabase;
  late final OfflineDatabase _offlineDatabase;
  late final String Function() _createNewIdFunction;
  late final HLCState _hlcState;

  final String userId;
  final String clientId;

  StreamSubscription? _serverMessagesSubscription;

  void Function(List<Message>)?
      _onMessagesReceived; // can be used to selectively refresh states

  set onMessagesReceived(void Function(List<Message>) value) {
    _onMessagesReceived = value;

    if (!_syncIsEnabled) return;

    // Resubscribe to stream to use the new callback
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

  Talon({
    required this.userId,
    required this.clientId,
    required ServerDatabase serverDatabase,
    required OfflineDatabase offlineDatabase,
    required String Function() createNewIdFunction,
  }) {
    _serverDatabase = serverDatabase;
    _offlineDatabase = offlineDatabase;
    _createNewIdFunction = createNewIdFunction;

    // Initialize the Hybrid Logical Clock with clientId as the node identifier
    _hlcState = HLCState(clientId);
  }

  Future<void> startPeriodicSync({int minuteInterval = 5}) async {}

  Future<void> runSync() async {
    await syncToServer();
    await syncFromServer();
  }

  Future<void> syncToServer() async {
    if (!_syncIsEnabled) return;

    final unsyncedMessages = await _offlineDatabase.getUnsyncedMessages();
    if (unsyncedMessages.isEmpty) return;

    final successfullySyncedMessages = <String>[];

    for (final message in unsyncedMessages) {
      final wasSuccessful =
          await _serverDatabase.sendMessageToServer(message: message);

      if (wasSuccessful) {
        successfullySyncedMessages.add(message.id);
      }
    }

    // Mark successfully synced messages
    if (successfullySyncedMessages.isNotEmpty) {
      await _offlineDatabase.markMessagesAsSynced(successfullySyncedMessages);
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

    if (messagesFromServer.isNotEmpty) {
      // Update HLC from received messages to maintain causal ordering
      _updateHlcFromMessages(messagesFromServer);

      await _offlineDatabase.saveMessagesFromServer(messagesFromServer);
    }
  }

  /// Update the local HLC based on received messages.
  ///
  /// This ensures our clock is at least as advanced as any received clock,
  /// maintaining causal ordering even with clock skew between devices.
  void _updateHlcFromMessages(List<Message> messages) {
    for (final message in messages) {
      final receivedHlc = HLC.tryParse(message.localTimestamp);
      if (receivedHlc != null) {
        _hlcState.receive(receivedHlc);
      }
    }
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
        // Update HLC from received messages
        _updateHlcFromMessages(messages);

        // Save messages to local database
        await _offlineDatabase.saveMessagesFromServer(messages);

        // Notify listeners that new messages have been received
        _onMessagesReceived?.call(messages);
      },
    );
  }

  void unsubscribeFromServerMessages() {
    _serverMessagesSubscription?.cancel();
  }

  /// Save a change to the local database and sync to server.
  ///
  /// The change is applied immediately to the local database, then
  /// queued for sync to the server.
  ///
  /// Parameters:
  /// - [table]: The table name to update
  /// - [row]: The row identifier (primary key)
  /// - [column]: The column name to update
  /// - [value]: The new value (as a string)
  /// - [dataType]: Optional type hint for deserialization
  Future<void> saveChange({
    required String table,
    required String row,
    required String column,
    required String value,
    String dataType = '',
  }) async {
    // Generate HLC timestamp for this change
    final hlcTimestamp = _hlcState.send();

    final message = Message(
      id: _createNewIdFunction(),
      table: table,
      row: row,
      column: column,
      dataType: dataType,
      value: value,
      localTimestamp: hlcTimestamp.toString(),
      userId: userId,
      clientId: clientId,
      hasBeenApplied: false,
      hasBeenSynced: false,
    );

    await _offlineDatabase.saveMessageFromLocalChange(message);

    if (_syncIsEnabled) {
      await syncToServer();
    }
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
