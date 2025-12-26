import 'package:talon/talon.dart';

/// Mock implementation of OfflineDatabase for testing.
class MockOfflineDatabase extends OfflineDatabase {
  final List<Message> messages = [];
  final Map<String, Map<String, Map<String, String>>> dataTables = {};
  int? _lastSyncedTimestamp;

  @override
  Future<void> init() async {}

  @override
  Future<bool> applyMessageToLocalDataTable(Message message) async {
    dataTables[message.table] ??= {};
    dataTables[message.table]![message.row] ??= {};
    dataTables[message.table]![message.row]![message.column] = message.value;
    return true;
  }

  @override
  Future<bool> applyMessageToLocalMessageTable(Message message) async {
    // Avoid duplicates
    if (messages.any((m) => m.id == message.id)) return true;
    messages.add(message);
    return true;
  }

  @override
  Future<String?> getExistingTimestamp({
    required String table,
    required String row,
    required String column,
  }) async {
    final matching = messages
        .where((m) => m.table == table && m.row == row && m.column == column)
        .toList();

    if (matching.isEmpty) return null;

    // Sort by HLC timestamp descending
    matching.sort((a, b) => HLC.compareTimestamps(
          b.localTimestamp,
          a.localTimestamp,
        ));

    return matching.first.localTimestamp;
  }

  @override
  Future<bool> shouldApplyMessage(Message message) async {
    final existingTimestamp = await getExistingTimestamp(
      table: message.table,
      row: message.row,
      column: message.column,
    );

    if (existingTimestamp == null) return true;

    return HLC.compareTimestamps(message.localTimestamp, existingTimestamp) > 0;
  }

  @override
  Future<List<Message>> getUnsyncedMessages() async {
    return messages.where((m) => !m.hasBeenSynced).toList();
  }

  @override
  Future<void> markMessagesAsSynced(List<String> syncedMessageIds) async {
    for (int i = 0; i < messages.length; i++) {
      if (syncedMessageIds.contains(messages[i].id)) {
        messages[i] = messages[i].copyWith(hasBeenSynced: true);
      }
    }
  }

  @override
  Future<int?> readLastSyncedServerTimestamp() async => _lastSyncedTimestamp;

  @override
  Future<void> saveLastSyncedServerTimestamp(int serverTimestamp) async {
    _lastSyncedTimestamp = serverTimestamp;
  }

  // Test utilities
  void clear() {
    messages.clear();
    dataTables.clear();
    _lastSyncedTimestamp = null;
  }

  String? getValue(String table, String row, String column) {
    return dataTables[table]?[row]?[column];
  }

  int get messageCount => messages.length;
  int get unsyncedCount => messages.where((m) => !m.hasBeenSynced).length;
  int get syncedCount => messages.where((m) => m.hasBeenSynced).length;
}
