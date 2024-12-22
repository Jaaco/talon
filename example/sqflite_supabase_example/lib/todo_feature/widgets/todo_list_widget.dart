import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_supabase_example/talon_implementation/talon_implementation.dart';

import '../states/todo_list_state.dart';

class TodoListWidget extends StatefulWidget {
  const TodoListWidget({super.key});

  @override
  State<TodoListWidget> createState() => _TodoListWidgetState();
}

class _TodoListWidgetState extends State<TodoListWidget> {
  @override
  void initState() {
    super.initState();

    Provider.of<TodoListState>(context, listen: false).readTodoList();

    talon.onMessagesReceived = (_) {
      Provider.of<TodoListState>(context, listen: false).readTodoList();
    };
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<TodoListState>(context);

    if (state.isLoading) {
      return const CircularProgressIndicator();
    }

    return ListView.builder(
      itemCount: state.todos.length,
      itemBuilder: (context, index) {
        final todo = state.todos[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: CupertinoButton(
            minSize: 0,
            padding: EdgeInsets.zero,
            onPressed: () {
              Provider.of<TodoListState>(context, listen: false)
                  .toggleTodo(todo);
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  primaryColor: CupertinoColors.black,
                ),
                child: Row(
                  children: [
                    Icon(
                      todo.isDone
                          ? CupertinoIcons.checkmark_alt_circle_fill
                          : CupertinoIcons.circle,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      todo.name,
                      style: TextStyle(
                        decoration: todo.isDone
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        color: CupertinoColors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
