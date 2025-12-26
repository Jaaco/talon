import 'dart:async';
import 'dart:convert';

import 'package:talon/src/hybrid_logical_clock/hlc.dart';
import 'package:talon/src/hybrid_logical_clock/hlc.state.dart';
import 'package:talon/src/messages/message.dart';
import 'package:talon/src/offline_database/offline_database.dart';

import '../server_database/server_database.dart';

/// Source of a change event.
enum TalonChangeSource {
  /// Change originated from a local saveChange call.
  local,

  /// Change received from the server.
  server,
}

/// Represents a batch of changes from a single source.
///
/// Use this to react to data changes in your UI:
/// ```dart
/// talon.changes.listen((change) {
///   if (change.affectsTable('todos')) {
///     refreshTodoList();
///   }
/// });
/// ```
class TalonChange {
  /// The source of these changes (local or server).
  final TalonChangeSource source;

  /// The messages in this change batch.
  final List<Message> messages;

  const TalonChange({
    required this.source,
    required this.messages,
  });

  /// Get messages for a specific table.
  List<Message> forTable(String table) {
    return messages.where((m) => m.table == table).toList();
  }

  /// Check if any messages affect a specific table.
  bool affectsTable(String table) {
    return messages.any((m) => m.table == table);
  }

  /// Check if any messages affect a specific row.
  bool affectsRow(String table, String row) {
    return messages.any((m) => m.table == table && m.row == row);
  }
}

/// Data for a single change in a batch operation.
///
/// Used with [Talon.saveChanges] to save multiple changes atomically.
class TalonChangeData {
  final String table;
  final String row;
  final String column;
  final dynamic value;
  final String? dataType;

  const TalonChangeData({
    required this.table,
    required this.row,
    required this.column,
    required this.value,
    this.dataType,
  });
}

/// Configuration for Talon sync behavior.
class TalonConfig {
  /// Maximum number of messages to send in a single batch.
  final int batchSize;

  /// Debounce duration for sync operations.
  /// Set to Duration.zero for immediate sync.
  final Duration syncDebounce;

  /// Whether to sync immediately on saveChange or wait for debounce.
  final bool immediateSyncOnSave;

  const TalonConfig({
    this.batchSize = 50,
    this.syncDebounce = const Duration(milliseconds: 500),
    this.immediateSyncOnSave = false,
  });

  /// Default configuration with batching and debounce.
  static const TalonConfig defaultConfig = TalonConfig();

  /// Configuration for immediate sync (no debounce).
  static const TalonConfig immediate = TalonConfig(
    syncDebounce: Duration.zero,
    immediateSyncOnSave: true,
  );
}

/// Internal representation of a serialized value.
class _SerializedValue {
  final String type;
  final String value;
  const _SerializedValue({required this.type, required this.value});
}

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
///
/// // Listen for changes
/// talon.changes.listen((change) {
///   if (change.affectsTable('todos')) {
///     refreshTodoList();
///   }
/// });
/// ```
///
/// ## Conflict Resolution
///
/// Talon uses Hybrid Logical Clocks (HLC) for conflict resolution.
/// When the same cell (table/row/column) is modified on multiple devices,
/// the change with the latest HLC timestamp wins.
class Talon {
  late final ServerDatabase _serverDatabase;
  late final OfflineDatabase _offlineDatabase;
  late final String Function() _createNewIdFunction;
  late final HLCState _hlcState;

  final String userId;
  final String clientId;
  final TalonConfig config;

  StreamSubscription? _serverMessagesSubscription;
  Timer? _periodicSyncTimer;
  Timer? _syncDebounceTimer;
  bool _syncPending = false;
  bool _isDisposed = false;

  final _changesController = StreamController<TalonChange>.broadcast();

  void Function(List<Message>)? _onMessagesReceived;

  /// Stream of all changes (both local and server).
  ///
  /// Use this to react to data changes:
  /// ```dart
  /// talon.changes.listen((change) {
  ///   if (change.affectsTable('todos')) {
  ///     refreshTodoList();
  ///   }
  /// });
  /// ```
  Stream<TalonChange> get changes => _changesController.stream;

  /// Stream of only server-originated changes.
  Stream<TalonChange> get serverChanges =>
      changes.where((c) => c.source == TalonChangeSource.server);

  /// Stream of only locally-originated changes.
  Stream<TalonChange> get localChanges =>
      changes.where((c) => c.source == TalonChangeSource.local);

  /// Whether sync is currently enabled.
  bool get syncIsEnabled => _syncIsEnabled;

  @Deprecated('Use the changes stream instead. Will be removed in v2.0.0')
  set onMessagesReceived(void Function(List<Message>) value) {
    _onMessagesReceived = value;

    if (!_syncIsEnabled) return;

    // Resubscribe to stream to use the new callback
    unsubscribeFromServerMessages();
    subscribeToServerMessages();
  }

  bool _syncIsEnabled = false;

  set syncIsEnabled(bool value) {
    _checkNotDisposed();
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
    this.config = TalonConfig.defaultConfig,
  }) {
    _serverDatabase = serverDatabase;
    _offlineDatabase = offlineDatabase;
    _createNewIdFunction = createNewIdFunction;

    // Initialize the Hybrid Logical Clock with clientId as the node identifier
    _hlcState = HLCState(clientId);
  }

  /// Serialize a dynamic value to string representation.
  _SerializedValue _serializeValue(dynamic value) {
    if (value == null) {
      return const _SerializedValue(type: 'null', value: '');
    } else if (value is String) {
      return _SerializedValue(type: 'string', value: value);
    } else if (value is int) {
      return _SerializedValue(type: 'int', value: value.toString());
    } else if (value is double) {
      return _SerializedValue(type: 'double', value: value.toString());
    } else if (value is bool) {
      return _SerializedValue(type: 'bool', value: value ? '1' : '0');
    } else if (value is DateTime) {
      return _SerializedValue(type: 'datetime', value: value.toIso8601String());
    } else if (value is Map || value is List) {
      return _SerializedValue(type: 'json', value: jsonEncode(value));
    } else {
      // Fallback: convert to string
      return _SerializedValue(type: 'string', value: value.toString());
    }
  }

  /// Start periodic background sync.
  ///
  /// Useful for ensuring sync happens even without explicit triggers.
  /// Recommended interval: 5-15 minutes.
  void startPeriodicSync({Duration interval = const Duration(minutes: 5)}) {
    _checkNotDisposed();
    stopPeriodicSync();

    _periodicSyncTimer = Timer.periodic(interval, (_) {
      if (_syncIsEnabled && !_isDisposed) {
        runSync();
      }
    });
  }

  /// Stop periodic background sync.
  void stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  /// Dispose all resources.
  ///
  /// After calling dispose, this instance should not be used.
  void dispose() {
    if (_isDisposed) return;

    _isDisposed = true;
    stopPeriodicSync();
    _syncDebounceTimer?.cancel();
    unsubscribeFromServerMessages();
    _changesController.close();
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw StateError('Talon instance has been disposed');
    }
  }

  Future<void> runSync() async {
    _checkNotDisposed();
    await syncToServer();
    await syncFromServer();
  }

  /// Schedule a sync operation, debouncing rapid calls.
  void _scheduleSyncToServer() {
    if (!_syncIsEnabled) return;

    if (config.immediateSyncOnSave || config.syncDebounce == Duration.zero) {
      syncToServer();
      return;
    }

    _syncPending = true;
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(config.syncDebounce, () {
      if (_syncPending && !_isDisposed) {
        _syncPending = false;
        syncToServer();
      }
    });
  }

  /// Force immediate sync, bypassing debounce.
  Future<void> forceSyncToServer() async {
    _checkNotDisposed();
    _syncDebounceTimer?.cancel();
    _syncPending = false;
    await syncToServer();
  }

  Future<void> syncToServer() async {
    _checkNotDisposed();
    if (!_syncIsEnabled) return;

    final unsyncedMessages = await _offlineDatabase.getUnsyncedMessages();
    if (unsyncedMessages.isEmpty) return;

    // Process in batches
    for (int i = 0; i < unsyncedMessages.length; i += config.batchSize) {
      final batch = unsyncedMessages.skip(i).take(config.batchSize).toList();

      final successfulIds = await _serverDatabase.sendMessagesToServer(
        messages: batch,
      );

      if (successfulIds.isNotEmpty) {
        await _offlineDatabase.markMessagesAsSynced(successfulIds);
      }

      // If not all succeeded, stop processing further batches
      if (successfulIds.length < batch.length) {
        break;
      }
    }
  }

  Future<void> syncFromServer() async {
    _checkNotDisposed();
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

      // Emit server changes
      _changesController.add(TalonChange(
        source: TalonChangeSource.server,
        messages: messagesFromServer,
      ));
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
    _checkNotDisposed();
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

        // Emit server changes
        if (messages.isNotEmpty) {
          _changesController.add(TalonChange(
            source: TalonChangeSource.server,
            messages: messages,
          ));
        }

        // Keep backward compatibility
        _onMessagesReceived?.call(messages);
      },
    );
  }

  void unsubscribeFromServerMessages() {
    _serverMessagesSubscription?.cancel();
    _serverMessagesSubscription = null;
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
  /// - [value]: The new value (accepts any type, will be serialized)
  /// - [dataType]: Optional type hint for deserialization (auto-detected if not provided)
  Future<void> saveChange({
    required String table,
    required String row,
    required String column,
    required dynamic value,
    String? dataType,
  }) async {
    _checkNotDisposed();

    final serialized = _serializeValue(value);
    final hlcTimestamp = _hlcState.send();

    final message = Message(
      id: _createNewIdFunction(),
      table: table,
      row: row,
      column: column,
      dataType: dataType ?? serialized.type,
      value: serialized.value,
      localTimestamp: hlcTimestamp.toString(),
      userId: userId,
      clientId: clientId,
      hasBeenApplied: false,
      hasBeenSynced: false,
    );

    await _offlineDatabase.saveMessageFromLocalChange(message);

    // Emit local change
    _changesController.add(TalonChange(
      source: TalonChangeSource.local,
      messages: [message],
    ));

    if (_syncIsEnabled) {
      _scheduleSyncToServer();
    }
  }

  /// Save multiple changes atomically.
  ///
  /// All changes are applied locally, then synced together.
  /// This is more efficient than calling saveChange multiple times.
  ///
  /// Example:
  /// ```dart
  /// await talon.saveChanges([
  ///   TalonChangeData(table: 'todos', row: id, column: 'name', value: 'New name'),
  ///   TalonChangeData(table: 'todos', row: id, column: 'updated_at', value: DateTime.now()),
  /// ]);
  /// ```
  Future<void> saveChanges(List<TalonChangeData> changes) async {
    _checkNotDisposed();
    if (changes.isEmpty) return;

    final messages = <Message>[];

    for (final change in changes) {
      final serialized = _serializeValue(change.value);
      final hlcTimestamp = _hlcState.send();

      final message = Message(
        id: _createNewIdFunction(),
        table: change.table,
        row: change.row,
        column: change.column,
        dataType: change.dataType ?? serialized.type,
        value: serialized.value,
        localTimestamp: hlcTimestamp.toString(),
        userId: userId,
        clientId: clientId,
        hasBeenApplied: false,
        hasBeenSynced: false,
      );

      messages.add(message);
    }

    // Apply all locally
    for (final message in messages) {
      await _offlineDatabase.saveMessageFromLocalChange(message);
    }

    // Emit as single batch
    _changesController.add(TalonChange(
      source: TalonChangeSource.local,
      messages: messages,
    ));

    // Schedule sync
    if (_syncIsEnabled) {
      _scheduleSyncToServer();
    }
  }
}
