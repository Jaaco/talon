import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../todo_list_view_model.dart';

class AddTodoBar extends StatefulWidget {
  final TodoListViewModel viewModel;

  const AddTodoBar({super.key, required this.viewModel});

  @override
  State<AddTodoBar> createState() => _AddTodoBarState();
}

class _AddTodoBarState extends State<AddTodoBar> {
  final _controller = TextEditingController();

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.viewModel.addTodo(text);
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ShadInput(
            controller: _controller,
            placeholder: const Text('Add a task…'),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 8),
        ShadButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
