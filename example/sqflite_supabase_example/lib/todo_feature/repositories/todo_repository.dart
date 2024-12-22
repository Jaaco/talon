import 'package:sqflite_supabase_example/talon_implementation/talon_implementation.dart';

import '../models/todo.dart';

class TodoRepository {
  final table = 'todos';
  final nameField = 'name';
  final isDoneField = 'is_done';

  Future<void> addTodo(String id, String name) async {
    await talon.saveChange(
      table: table,
      row: id,
      column: nameField,
      value: name,
    );
  }

  Future<void> updateIsDone(String id, bool todoState) async {
    await talon.saveChange(
      table: table,
      row: id,
      column: isDoneField,
      value: todoState ? '1' : '0',
    );
  }

  void saveName({required String id, required String name}) {
    talon.saveChange(
      table: table,
      row: id,
      column: nameField,
      value: name,
    );
  }

  Future<List<Todo>> readTodos() async {
    final todosRaw = await offlineDatabase.runQuery('''
      SELECT *
      FROM $table;
   ''');

    return todosRaw.map(Todo.fromMap).toList()..reversed;
  }
}
