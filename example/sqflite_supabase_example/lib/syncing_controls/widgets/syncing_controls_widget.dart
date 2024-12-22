import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_supabase_example/syncing_controls/widgets/control_button.dart';
import 'package:sqflite_supabase_example/talon_implementation/talon_implementation.dart';

import '../../todo_feature/states/todo_list_state.dart';
import '../states/syncing_controls_state.dart';

class SyncingControlsWidget extends StatelessWidget {
  const SyncingControlsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final isOnline = Provider.of<SyncingControlsState>(context).syncIsEnabled;

    return Column(
      children: [
        ControlButton(
          onPressed: () {
            talon.syncFromServer();
            Provider.of<TodoListState>(context, listen: false).readTodoList();
          },
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.arrow_down,
                color: Colors.white,
              ),
              SizedBox(width: 12),
              Text(
                'Sync From Server',
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ControlButton(
          onPressed: () {
            Provider.of<SyncingControlsState>(context, listen: false)
                .toggleSync();
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isOnline ? CupertinoIcons.wifi : CupertinoIcons.wifi_slash,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                isOnline ? 'Online & Syncing' : 'Offline',
                style: const TextStyle(
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ControlButton(
          onPressed: () {
            offlineDatabase.resetDatabase();
          },
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.arrow_2_circlepath,
                color: Colors.white,
              ),
              SizedBox(width: 12),
              Text(
                'Fresh Install',
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
