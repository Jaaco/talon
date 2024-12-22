import 'package:flutter/material.dart';
import 'package:sqflite_supabase_example/todo_feature/models/todo.dart';

import '../repositories/todo_repository.dart';

class TodoListState extends ChangeNotifier {
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  List<Todo> _todos = [];
  List<Todo> get todos => _todos;

  final _todoRepository = TodoRepository();

  void readTodoList() async {
    _todos = await _todoRepository.readTodos();
    _isLoading = false;

    notifyListeners();
  }

  void addTodo(String name) {
    final id = DateTime.now().toString();

    final newTodo = Todo(
      id: id,
      name: name,
      isDone: false,
    );

    _todos.add(newTodo);

    notifyListeners();

    _todoRepository.addTodo(id, name);
  }

  void toggleTodo(Todo todo) {
    _todos.remove(todo);
    final newTodo = todo.copyWith(isDone: !todo.isDone);
    _todos.add(newTodo);
    notifyListeners();

    _todoRepository.updateIsDone(todo.id, newTodo.isDone);
  }
}
