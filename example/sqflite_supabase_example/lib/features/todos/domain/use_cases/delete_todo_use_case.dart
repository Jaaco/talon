import '../todo_repository.dart';

class DeleteTodoUseCase {
  final TodoRepository _repository;

  DeleteTodoUseCase(this._repository);

  Future<void> call(String id) => _repository.deleteTodo(id);
}
