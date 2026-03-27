import 'package:signals/signals.dart';

import '../domain/todo.dart';
import '../domain/todo_repository.dart';
import 'todo_local_data_source.dart';
import 'todo_remote_data_source.dart';

/// Concrete [TodoRepository] that caches todos in a [Signal].
///
/// The public [todos] is exposed as [ReadonlySignal] so callers can observe
/// changes but cannot mutate the signal directly.
class TodoRepositoryImpl implements TodoRepository {
  final TodoLocalDataSource _local;
  final TodoRemoteDataSource _remote;

  final Future<void> Function({
    required String table,
    required String row,
    required String column,
    required dynamic value,
  }) _saveChange;

  static const _table = 'todos';

  final _todos = signal<List<Todo>>([]);

  ReadonlySignal<List<Todo>> get todos => _todos.readonly();

  TodoRepositoryImpl({
    required TodoLocalDataSource local,
    required TodoRemoteDataSource remote,
    required Future<void> Function({
      required String table,
      required String row,
      required String column,
      required dynamic value,
    }) saveChange,
  })  : _local = local,
        _remote = remote,
        _saveChange = saveChange;

  @override
  Future<List<Todo>> getTodos() async {
    final list = await _local.getTodos();
    _todos.value = list;
    return list;
  }

  @override
  Future<void> addTodo(String id, String name) async {
    await _saveChange(table: _table, row: id, column: 'name', value: name);
    await _saveChange(table: _table, row: id, column: 'is_done', value: '0');
    await getTodos();
  }

  @override
  Future<void> updateName(String id, String name) async {
    await _saveChange(table: _table, row: id, column: 'name', value: name);
    await getTodos();
  }

  @override
  Future<void> updateIsDone(String id, bool isDone) async {
    await _saveChange(
      table: _table,
      row: id,
      column: 'is_done',
      value: isDone ? '1' : '0',
    );
    await getTodos();
  }

  @override
  Future<void> deleteTodo(String id) async {
    // Talon uses a tombstone value to represent deletion.
    await _saveChange(
      table: _table,
      row: id,
      column: 'name',
      value: '__deleted__',
    );
    await getTodos();
  }

  @override
  Future<void> sync() => _remote.sync();
}
