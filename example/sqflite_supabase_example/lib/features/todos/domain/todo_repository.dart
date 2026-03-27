import 'todo.dart';

abstract interface class TodoRepository {
  Future<List<Todo>> getTodos();
  Future<void> addTodo(String id, String name);
  Future<void> updateName(String id, String name);
  Future<void> updateIsDone(String id, bool isDone);
  Future<void> deleteTodo(String id);
  Future<void> sync();
}
