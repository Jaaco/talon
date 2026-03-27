import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

import 'todo_list_view_model.dart';
import 'widgets/add_todo_dialog.dart';
import 'widgets/sync_status_bar.dart';
import 'widgets/todo_item.dart';

class TodoListScreen extends StatefulWidget {
  final TodoListViewModel viewModel;
  final Future<void> Function() onReset;

  const TodoListScreen({
    super.key,
    required this.viewModel,
    required this.onReset,
  });

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShadTheme.of(context).colorScheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(),
              const SizedBox(height: 16),
              AddTodoBar(viewModel: widget.viewModel),
              const SizedBox(height: 16),
              Expanded(child: _TodoList(viewModel: widget.viewModel)),
              const SizedBox(height: 16),
              SyncStatusBar(
                viewModel: widget.viewModel,
                onReset: widget.onReset,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Talon Todos', style: theme.textTheme.h2),
        Text(
          'Offline-first sync demo — double-tap a todo to edit',
          style: theme.textTheme.muted,
        ),
      ],
    );
  }
}

class _TodoList extends StatelessWidget {
  final TodoListViewModel viewModel;

  const _TodoList({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final isLoading = viewModel.isLoading.value;
      if (isLoading) {
        return const Center(child: CircularProgressIndicator());
      }

      final todos = viewModel.todos.value;
      if (todos.isEmpty) {
        return Center(
          child: Text(
            'No todos yet — add one above!',
            style: ShadTheme.of(context).textTheme.muted,
          ),
        );
      }

      return ListView.separated(
        itemCount: todos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final todo = todos[i];
          return TodoItem(key: ValueKey(todo.id), todo: todo, viewModel: viewModel);
        },
      );
    });
  }
}
