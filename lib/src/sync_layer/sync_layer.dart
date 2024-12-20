import 'package:talon/src/offline_database/offline_database.dart';

import '../online_database/online_database.dart';

class SyncLayer {
  late final OnlineDatabase _onlineDatabase;
  late final OfflineDatabase _offlineDatabase;

  final String userId;
  final String clientId;

  SyncLayer({
    required this.userId,
    required this.clientId,
    required OnlineDatabase onlineDatabase,
    required OfflineDatabase offlineDatabase,
  }) {
    _onlineDatabase = onlineDatabase;
    _offlineDatabase = offlineDatabase;
  }

  Future<void> startPeriodicSync({int minuteInterval = 5}) async {}

  Future<void> runSync() async {}

  Future<void> getMessagesFromServer() async {
    final lastSyncedServerTimestamp =
        await _offlineDatabase.readLastSyncedServerTimestamp();

    final messagesFromServer = _onlineDatabase.getMessagesFromServer(
      userId: userId,
      clientId: clientId,
      lastSyncedServerTimestamp: lastSyncedServerTimestamp,
    );
  }
}
