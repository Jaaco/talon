import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../states/book_list_state.dart';

class AddBookWidget extends StatefulWidget {
  const AddBookWidget({super.key});

  @override
  AddBookWidgetState createState() => AddBookWidgetState();
}

class AddBookWidgetState extends State<AddBookWidget> {
  final TextEditingController _nameController = TextEditingController();

  void _addBook() {
    if (_nameController.text.isNotEmpty) {
      Provider.of<BookListState>(context, listen: false)
          .addBook(_nameController.text);

      _nameController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _nameController,
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color.fromARGB(255, 32, 32, 32),
            ),
            decoration: const InputDecoration(
              labelText: 'Book',
              border: OutlineInputBorder(borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 16),
        CupertinoButton(
          onPressed: _addBook,
          child: const Text(
            'Add Book',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
