import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_supabase_example/features/todos/data/todo_local_data_source.dart';
import 'package:sqflite_supabase_example/features/todos/data/todo_remote_data_source.dart';
import 'package:sqflite_supabase_example/features/todos/data/todo_repository_impl.dart';
import 'package:sqflite_supabase_example/features/todos/domain/todo.dart';
import 'package:sqflite_supabase_example/features/todos/presentation/todo_list_view_model.dart';

class MockTodoLocalDataSource extends Mock implements TodoLocalDataSource {}

class MockTodoRemoteDataSource extends Mock implements TodoRemoteDataSource {}

void main() {
  late MockTodoLocalDataSource mockLocal;
  late MockTodoRemoteDataSource mockRemote;
  late TodoRepositoryImpl repository;
  late TodoListViewModel viewModel;
  late bool syncEnabled;

  Future<void> noopSaveChange({
    required String table,
    required String row,
    required String column,
    required dynamic value,
  }) async {}

  setUp(() {
    mockLocal = MockTodoLocalDataSource();
    mockRemote = MockTodoRemoteDataSource();
    syncEnabled = false;

    repository = TodoRepositoryImpl(
      local: mockLocal,
      remote: mockRemote,
      saveChange: noopSaveChange,
    );

    viewModel = TodoListViewModel(
      repository: repository,
      setSyncEnabled: (v) => syncEnabled = v,
    );
  });

  group('TodoListViewModel', () {
    test('init loads todos and sets isLoading to false', () async {
      final todos = [const Todo(id: '1', name: 'Task', isDone: false)];
      when(() => mockLocal.getTodos()).thenAnswer((_) async => todos);

      expect(viewModel.isLoading.value, isTrue);
      await viewModel.init();
      expect(viewModel.isLoading.value, isFalse);
      expect(viewModel.todos.value, equals(todos));
    });

    test('addTodo ignores empty names', () async {
      when(() => mockLocal.getTodos()).thenAnswer((_) async => []);
      await viewModel.addTodo('');
      // No save call — local data source should not be touched for empty input.
      verifyNever(() => mockLocal.getTodos());
    });

    test('toggleTodo flips isDone', () async {
      const todo = Todo(id: '1', name: 'Task', isDone: false);
      when(() => mockLocal.getTodos())
          .thenAnswer((_) async => [todo.copyWith(isDone: true)]);

      await viewModel.toggleTodo(todo);

      expect(viewModel.todos.value.first.isDone, isTrue);
    });

    test('toggleOnline toggles isOnline and calls setSyncEnabled', () {
      expect(viewModel.isOnline.value, isFalse);
      viewModel.toggleOnline();
      expect(viewModel.isOnline.value, isTrue);
      expect(syncEnabled, isTrue);

      viewModel.toggleOnline();
      expect(viewModel.isOnline.value, isFalse);
      expect(syncEnabled, isFalse);
    });

    test('syncFromServer sets isSyncing during sync', () async {
      when(() => mockRemote.sync()).thenAnswer((_) async {});
      when(() => mockLocal.getTodos()).thenAnswer((_) async => []);

      final syncFuture = viewModel.syncFromServer();
      // isSyncing should be true while awaiting
      expect(viewModel.isSyncing.value, isTrue);
      await syncFuture;
      expect(viewModel.isSyncing.value, isFalse);
    });

    test('syncFromServer does not start a second sync while syncing', () async {
      when(() => mockRemote.sync()).thenAnswer(
        (_) async => await Future.delayed(const Duration(milliseconds: 50)),
      );
      when(() => mockLocal.getTodos()).thenAnswer((_) async => []);

      final first = viewModel.syncFromServer();
      final second = viewModel.syncFromServer(); // should be ignored
      await Future.wait([first, second]);

      // sync() on remote should only be called once.
      verify(() => mockRemote.sync()).called(1);
    });
  });
}
