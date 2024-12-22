import 'package:flutter/foundation.dart';
import 'package:sqflite_supabase_example/talon_implementation/talon_implementation.dart';

class SyncingControlsState extends ChangeNotifier {
  bool _syncIsEnabled = false;
  bool get syncIsEnabled => _syncIsEnabled;

  void toggleSync() {
    _syncIsEnabled = !_syncIsEnabled;

    talon.syncIsEnabled = _syncIsEnabled;
    notifyListeners();
  }
}
