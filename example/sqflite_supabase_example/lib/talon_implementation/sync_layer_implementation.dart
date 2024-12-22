import 'package:talon/dart_offlne_first.dart';

import 'offline_database_implementation.dart';
import 'server_database_implementation.dart';

final offlineDatabase = MyOfflineDB();
final serverDatabase = MyServerDatabaseImplementation();

final syncLayer = SyncLayer(
  userId: 'user_1',
  clientId: 'device_1',
  serverDatabase: serverDatabase,
  offlineDatabase: offlineDatabase,
  createNewIdFunction: () {
    return DateTime.now().toString();
  },
);
