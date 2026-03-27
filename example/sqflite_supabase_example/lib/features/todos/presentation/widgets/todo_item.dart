import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/todo.dart';
import '../todo_list_view_model.dart';

class TodoItem extends StatefulWidget {
  final Todo todo;
  final TodoListViewModel viewModel;

  const TodoItem({super.key, required this.todo, required this.viewModel});

  @override
  State<TodoItem> createState() => _TodoItemState();
}

class _TodoItemState extends State<TodoItem> {
  bool _editing = false;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.todo.name);
  }

  @override
  void didUpdateWidget(TodoItem old) {
    super.didUpdateWidget(old);
    if (!_editing && old.todo.name != widget.todo.name) {
      _controller.text = widget.todo.name;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commitEdit() {
    setState(() => _editing = false);
    final text = _controller.text.trim();
    if (text.isNotEmpty && text != widget.todo.name) {
      widget.viewModel.updateTodoName(widget.todo.id, text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final todo = widget.todo;

    return ShadCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ShadCheckbox(
            value: todo.isDone,
            onChanged: (_) => widget.viewModel.toggleTodo(todo),
            label: const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _editing
                ? TextField(
                    controller: _controller,
                    autofocus: true,
                    style: theme.textTheme.p,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _commitEdit(),
                    onEditingComplete: _commitEdit,
                  )
                : GestureDetector(
                    onDoubleTap: () => setState(() => _editing = true),
                    child: Text(
                      todo.name,
                      style: theme.textTheme.p.copyWith(
                        decoration: todo.isDone
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        color: todo.isDone
                            ? theme.colorScheme.mutedForeground
                            : null,
                      ),
                    ),
                  ),
          ),
          if (_editing)
            IconButton(
              icon: const Icon(Icons.check, size: 18),
              onPressed: _commitEdit,
              tooltip: 'Save',
            )
          else
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: theme.colorScheme.destructive,
              ),
              onPressed: () => widget.viewModel.deleteTodo(todo.id),
              tooltip: 'Delete',
            ),
        ],
      ),
    );
  }
}
