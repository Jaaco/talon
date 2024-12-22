import 'package:flutter/material.dart';
import 'package:sqflite_supabase_example/talon_implementation/sync_layer_implementation.dart';

class SyncingControlsState extends ChangeNotifier {
  bool _syncIsEnabled = false;
  bool get syncIsEnabled => _syncIsEnabled;

  void toggleSync() {
    _syncIsEnabled = !_syncIsEnabled;

    syncLayer.syncIsEnabled = _syncIsEnabled;
    notifyListeners();
  }
}
