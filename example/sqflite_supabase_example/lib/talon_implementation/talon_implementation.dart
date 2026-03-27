import 'package:flutter/foundation.dart';
import 'package:talon/talon.dart';
import 'package:uuid/uuid.dart';

import 'client_id_stub.dart'
    if (dart.library.html) 'client_id_web.dart';
import 'offline_database_implementation.dart';
import 'server_database_implementation.dart';

final offlineDatabase = MyOfflineDB();
final serverDatabase = MyServerDatabaseImplementation();

const _uuid = Uuid();

final talon = Talon(
  userId: 'user_1',
  clientId: clientId,
  serverDatabase: serverDatabase,
  offlineDatabase: offlineDatabase,
  createNewIdFunction: () => _uuid.v4(),
);

/// Returns a unique client ID per platform/tab.
///
/// On web/Chrome, uses a random UUID stored in sessionStorage so that each
/// tab acts as a distinct client — enabling two-tab conflict resolution demos.
/// On other platforms, uses the platform name (macOS, iOS, Android).
String get clientId {
  if (kIsWeb) {
    return getOrCreateWebClientId(_uuid);
  }

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
