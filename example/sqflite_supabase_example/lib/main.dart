import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/todos/data/todo_local_data_source.dart';
import 'features/todos/data/todo_remote_data_source.dart';
import 'features/todos/data/todo_repository_impl.dart';
import 'features/todos/presentation/todo_list_screen.dart';
import 'features/todos/presentation/todo_list_view_model.dart';
import 'talon_implementation/config.dart';
import 'talon_implementation/talon_implementation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
  );

  await offlineDatabase.init();
  talon.startPeriodicSync();

  final localDataSource = TodoLocalDataSourceImpl(
    runQuery: offlineDatabase.runQuery,
  );
  final remoteDataSource = TodoRemoteDataSourceImpl(
    syncFromServer: () => talon.syncFromServer(),
  );

  final repository = TodoRepositoryImpl(
    local: localDataSource,
    remote: remoteDataSource,
    saveChange: talon.saveChange,
  );

  final viewModel = TodoListViewModel(
    repository: repository,
    setSyncEnabled: (enabled) => talon.syncIsEnabled = enabled,
  );

  // Refresh todos whenever talon receives any change (local or server).
  talon.changes.listen((_) => viewModel.onTalonChange());

  runApp(MyApp(
    viewModel: viewModel,
    onReset: () async {
      await offlineDatabase.resetDatabase();
      await viewModel.onTalonChange();
    },
  ));
}

class MyApp extends StatelessWidget {
  final TodoListViewModel viewModel;
  final Future<void> Function() onReset;

  const MyApp({
    super.key,
    required this.viewModel,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: 'Talon Todo Demo',
      theme: ShadThemeData(
        colorScheme: const ShadSlateColorScheme.light(),
        brightness: Brightness.light,
      ),
      darkTheme: ShadThemeData(
        colorScheme: const ShadSlateColorScheme.dark(),
        brightness: Brightness.dark,
      ),
      home: TodoListScreen(
        viewModel: viewModel,
        onReset: onReset,
      ),
    );
  }
}
