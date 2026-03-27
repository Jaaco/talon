import '../todo.dart';
import '../todo_repository.dart';

/// Syncs todos from the server, then re-fetches from local DB.
///
/// This is the canonical proof-of-sync: after calling syncFromServer()
/// and then reading from local DB, the UI shows exactly what was merged.
class SyncTodosUseCase {
  final TodoRepository _repository;

  SyncTodosUseCase(this._repository);

  Future<List<Todo>> call() async {
    await _repository.sync();
    return _repository.getTodos();
  }
}
