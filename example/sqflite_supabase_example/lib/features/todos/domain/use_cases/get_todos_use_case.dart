import '../todo.dart';
import '../todo_repository.dart';

class GetTodosUseCase {
  final TodoRepository _repository;

  GetTodosUseCase(this._repository);

  Future<List<Todo>> call() => _repository.getTodos();
}
