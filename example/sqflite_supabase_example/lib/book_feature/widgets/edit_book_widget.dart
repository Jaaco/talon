import 'package:flutter/material.dart';

import '../models/book.dart';

class EditBookWidget extends StatefulWidget {
  final Book book;

  const EditBookWidget({super.key, required this.book});

  @override
  EditBookWidgetState createState() => EditBookWidgetState();
}

class EditBookWidgetState extends State<EditBookWidget> {
  late TextEditingController _nameController;
  late TextEditingController _pagesController;
  late TextEditingController _imageUrlController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.book.name);
    _pagesController =
        TextEditingController(text: widget.book.pages.toString());
    _imageUrlController = TextEditingController(text: widget.book.imageUrl);
  }

  void _saveChanges() {
    setState(() {
      // widget.book.name = _nameController.text;
      // widget.book.pages =
      //     int.tryParse(_pagesController.text) ?? widget.book.pages;
      // widget.book.imageUrl = _imageUrlController.text;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Changes saved!')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Book')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _pagesController,
              decoration: const InputDecoration(labelText: 'Pages'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _imageUrlController,
              decoration: const InputDecoration(labelText: 'Image URL'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveChanges,
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
