import '../todo_repository.dart';

class AddTodoUseCase {
  final TodoRepository _repository;

  AddTodoUseCase(this._repository);

  Future<void> call(String id, String name) => _repository.addTodo(id, name);
}
