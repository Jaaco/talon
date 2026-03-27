import 'package:signals/signals.dart';
import 'package:uuid/uuid.dart';

import '../data/todo_repository_impl.dart';
import '../domain/todo.dart';
import '../domain/use_cases/add_todo_use_case.dart';
import '../domain/use_cases/delete_todo_use_case.dart';
import '../domain/use_cases/sync_todos_use_case.dart';
import '../domain/use_cases/update_todo_use_case.dart';

/// Exposes [ReadonlySignal]s for the UI and coordinates use cases.
///
/// Both [todos] and [isSyncing] are public as [ReadonlySignal] only — the UI
/// observes but never mutates signals directly.
class TodoListViewModel {
  final TodoRepositoryImpl _repository;
  final AddTodoUseCase _addTodo;
  final UpdateTodoNameUseCase _updateName;
  final UpdateTodoIsDoneUseCase _updateIsDone;
  final DeleteTodoUseCase _deleteTodo;
  final SyncTodosUseCase _sync;

  final _uuid = const Uuid();
  final _isOnline = signal<bool>(false);
  final _isSyncing = signal<bool>(false);
  final _isLoading = signal<bool>(true);

  ReadonlySignal<List<Todo>> get todos => _repository.todos;
  ReadonlySignal<bool> get isOnline => _isOnline.readonly();
  ReadonlySignal<bool> get isSyncing => _isSyncing.readonly();
  ReadonlySignal<bool> get isLoading => _isLoading.readonly();

  final void Function(bool) _setSyncEnabled;

  TodoListViewModel({
    required TodoRepositoryImpl repository,
    required void Function(bool) setSyncEnabled,
  })  : _repository = repository,
        _setSyncEnabled = setSyncEnabled,
        _addTodo = AddTodoUseCase(repository),
        _updateName = UpdateTodoNameUseCase(repository),
        _updateIsDone = UpdateTodoIsDoneUseCase(repository),
        _deleteTodo = DeleteTodoUseCase(repository),
        _sync = SyncTodosUseCase(repository);

  Future<void> init() async {
    _isLoading.value = true;
    await _repository.getTodos();
    _isLoading.value = false;
  }

  Future<void> addTodo(String name) async {
    if (name.trim().isEmpty) return;
    final id = _uuid.v4();
    await _addTodo(id, name.trim());
  }

  Future<void> updateTodoName(String id, String name) async {
    if (name.trim().isEmpty) return;
    await _updateName(id, name.trim());
  }

  Future<void> toggleTodo(Todo todo) async {
    await _updateIsDone(todo.id, !todo.isDone);
  }

  Future<void> deleteTodo(String id) async {
    await _deleteTodo(id);
  }

  Future<void> syncFromServer() async {
    if (_isSyncing.value) return;
    _isSyncing.value = true;
    try {
      await _sync();
    } finally {
      _isSyncing.value = false;
    }
  }

  void toggleOnline() {
    _isOnline.value = !_isOnline.value;
    _setSyncEnabled(_isOnline.value);
  }

  Future<void> resetDatabase(Future<void> Function() resetFn) async {
    await resetFn();
    await _repository.getTodos();
  }

  /// Called when talon emits a change (e.g. from subscribeToServerMessages).
  Future<void> onTalonChange() async {
    await _repository.getTodos();
  }
}
