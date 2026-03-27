import '../todo_repository.dart';

class UpdateTodoNameUseCase {
  final TodoRepository _repository;

  UpdateTodoNameUseCase(this._repository);

  Future<void> call(String id, String name) =>
      _repository.updateName(id, name);
}

class UpdateTodoIsDoneUseCase {
  final TodoRepository _repository;

  UpdateTodoIsDoneUseCase(this._repository);

  Future<void> call(String id, bool isDone) =>
      _repository.updateIsDone(id, isDone);
}
