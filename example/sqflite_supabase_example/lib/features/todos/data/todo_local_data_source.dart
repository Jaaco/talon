import '../domain/todo.dart';

abstract interface class TodoLocalDataSource {
  Future<List<Todo>> getTodos();
}

class TodoLocalDataSourceImpl implements TodoLocalDataSource {
  final Future<List<Map<String, Object?>>> Function(String query) runQuery;

  TodoLocalDataSourceImpl({required this.runQuery});

  @override
  Future<List<Todo>> getTodos() async {
    final rows = await runQuery('SELECT * FROM todos;');
    return rows.map((r) => Todo.fromMap(r.cast<String, dynamic>())).toList();
  }
}
