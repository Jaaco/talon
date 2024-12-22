import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_supabase_example/syncing_controls/states/syncing_controls_state.dart';

import '../states/todo_list_state.dart';

class AddTodoWidget extends StatefulWidget {
  const AddTodoWidget({super.key});

  @override
  AddTodoWidgetState createState() => AddTodoWidgetState();
}

class AddTodoWidgetState extends State<AddTodoWidget> {
  final TextEditingController _nameController = TextEditingController();

  void _addTodo() {
    if (_nameController.text.isNotEmpty) {
      Provider.of<TodoListState>(context, listen: false)
          .addTodo(_nameController.text);

      _nameController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = Provider.of<SyncingControlsState>(context).syncIsEnabled;

    return Container(
      decoration: BoxDecoration(
        color: isOnline
            ? const Color.fromARGB(255, 81, 91, 227)
            : const Color.fromARGB(255, 131, 134, 193),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _nameController,
              onEditingComplete: _addTodo,
              textAlign: TextAlign.start,
              style: const TextStyle(
                fontSize: 16,
                color: CupertinoColors.white,
              ),
              decoration: const InputDecoration(
                prefixIcon: Icon(
                  CupertinoIcons.add,
                  color: CupertinoColors.white,
                ),
                labelText: 'Add a Task',
                labelStyle: TextStyle(
                  fontSize: 16,
                  color: CupertinoColors.white,
                ),
                border: OutlineInputBorder(borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
