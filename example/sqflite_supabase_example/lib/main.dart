import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_supabase_example/todo_feature/states/todo_list_state.dart';
import 'package:sqflite_supabase_example/todo_feature/widgets/todo_list_widget.dart';
import 'package:sqflite_supabase_example/syncing_controls/widgets/syncing_controls_widget.dart';
import 'package:sqflite_supabase_example/talon_implementation/config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'todo_feature/widgets/add_todo.dart';
import 'syncing_controls/states/syncing_controls_state.dart';
import 'talon_implementation/sync_layer_implementation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
  );

  await offlineDatabase.init();

  syncLayer.startPeriodicSync();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      localizationsDelegates: localizationsDelegates,
      theme: const CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: CupertinoColors.white,
        scaffoldBackgroundColor: Color.fromARGB(255, 90, 101, 255),
      ),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => SyncingControlsState()),
          ChangeNotifierProvider(create: (context) => TodoListState()),
        ],
        builder: (context, child) {
          final isOnline =
              Provider.of<SyncingControlsState>(context).syncIsEnabled;

          return Scaffold(
            backgroundColor: isOnline
                ? const Color.fromARGB(255, 90, 101, 255)
                : const Color.fromARGB(255, 159, 162, 211),
            body: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(height: 64),
                  AddTodoWidget(),
                  SizedBox(height: 12),
                  Expanded(
                    child: TodoListWidget(),
                  ),
                  SyncingControlsWidget(),
                  SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

const localizationsDelegates = [
  DefaultMaterialLocalizations.delegate,
  DefaultCupertinoLocalizations.delegate,
  DefaultWidgetsLocalizations.delegate,
];
