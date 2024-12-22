import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_supabase_example/book_feature/states/book_list_state.dart';
import 'package:sqflite_supabase_example/book_feature/widgets/book_list_widget.dart';
import 'package:sqflite_supabase_example/syncing_controls/widgets/syncing_controls_widget.dart';
import 'package:sqflite_supabase_example/talon_implementation/config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'book_feature/widgets/add_book.dart';
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
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => SyncingControlsState()),
          ChangeNotifierProvider(create: (context) => BookListState()),
        ],
        builder: (context, child) {
          final isOnline =
              Provider.of<SyncingControlsState>(context).syncIsEnabled;

          return Scaffold(
            backgroundColor: isOnline ? Colors.white : Colors.grey[500],
            body: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(height: 64),
                  AddBookWidget(),
                  Expanded(
                    child: BookListWidget(),
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
