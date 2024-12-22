import 'package:flutter/foundation.dart';
import 'package:talon/dart_offlne_first.dart';

import 'offline_database_implementation.dart';
import 'server_database_implementation.dart';

final offlineDatabase = MyOfflineDB();
final serverDatabase = MyServerDatabaseImplementation();

final syncLayer = SyncLayer(
  userId: 'user_1',
  clientId: clientId,
  serverDatabase: serverDatabase,
  offlineDatabase: offlineDatabase,
  createNewIdFunction: () {
    /// Here one could use the 'uuid' package to generate a unique id
    return DateTime.now().toString();
  },
);

/// Here one could use a device info plugin to get a unique device id
/// For testing purposes, we will just return the platform name, so a macos &
/// iOS simulator run at the same time will behave as different devices
String get clientId {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return 'macOS';
  }

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return 'iOS';
  }

  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'Android';
  }

  return 'Other';
}
