import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_supabase_example/features/todos/data/todo_local_data_source.dart';
import 'package:sqflite_supabase_example/features/todos/data/todo_remote_data_source.dart';
import 'package:sqflite_supabase_example/features/todos/data/todo_repository_impl.dart';
import 'package:sqflite_supabase_example/features/todos/domain/todo.dart';

class MockTodoLocalDataSource extends Mock implements TodoLocalDataSource {}

class MockTodoRemoteDataSource extends Mock implements TodoRemoteDataSource {}

void main() {
  late MockTodoLocalDataSource mockLocal;
  late MockTodoRemoteDataSource mockRemote;
  late TodoRepositoryImpl repository;

  final calls = <Map<String, dynamic>>[];

  Future<void> fakeSaveChange({
    required String table,
    required String row,
    required String column,
    required dynamic value,
  }) async {
    calls.add({'table': table, 'row': row, 'column': column, 'value': value});
  }

  setUp(() {
    mockLocal = MockTodoLocalDataSource();
    mockRemote = MockTodoRemoteDataSource();
    calls.clear();

    repository = TodoRepositoryImpl(
      local: mockLocal,
      remote: mockRemote,
      saveChange: fakeSaveChange,
    );
  });

  group('TodoRepositoryImpl', () {
    test('getTodos returns todos from local data source and updates signal', () async {
      final todos = [
        const Todo(id: '1', name: 'Buy milk', isDone: false),
        const Todo(id: '2', name: 'Walk dog', isDone: true),
      ];
      when(() => mockLocal.getTodos()).thenAnswer((_) async => todos);

      final result = await repository.getTodos();

      expect(result, equals(todos));
      expect(repository.todos.value, equals(todos));
      verify(() => mockLocal.getTodos()).called(1);
    });

    test('addTodo saves name and is_done via saveChange', () async {
      when(() => mockLocal.getTodos()).thenAnswer((_) async => []);

      await repository.addTodo('abc', 'Test todo');

      expect(calls, containsAll([
        {'table': 'todos', 'row': 'abc', 'column': 'name', 'value': 'Test todo'},
        {'table': 'todos', 'row': 'abc', 'column': 'is_done', 'value': '0'},
      ]));
    });

    test('updateName saves name via saveChange', () async {
      when(() => mockLocal.getTodos()).thenAnswer((_) async => []);

      await repository.updateName('abc', 'Updated name');

      expect(calls, containsAll([
        {'table': 'todos', 'row': 'abc', 'column': 'name', 'value': 'Updated name'},
      ]));
    });

    test('updateIsDone saves is_done via saveChange', () async {
      when(() => mockLocal.getTodos()).thenAnswer((_) async => []);

      await repository.updateIsDone('abc', true);

      expect(calls, containsAll([
        {'table': 'todos', 'row': 'abc', 'column': 'is_done', 'value': '1'},
      ]));
    });

    test('deleteTodo saves tombstone value via saveChange', () async {
      when(() => mockLocal.getTodos()).thenAnswer((_) async => []);

      await repository.deleteTodo('abc');

      expect(calls, containsAll([
        {'table': 'todos', 'row': 'abc', 'column': 'name', 'value': '__deleted__'},
      ]));
    });

    test('sync delegates to remote data source', () async {
      when(() => mockRemote.sync()).thenAnswer((_) async {});

      await repository.sync();

      verify(() => mockRemote.sync()).called(1);
    });
  });
}
