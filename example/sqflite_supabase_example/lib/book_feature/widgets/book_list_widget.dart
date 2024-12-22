import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_supabase_example/talon_implementation/sync_layer_implementation.dart';

import '../states/book_list_state.dart';
import 'edit_book_widget.dart';

class BookListWidget extends StatefulWidget {
  const BookListWidget({super.key});

  @override
  State<BookListWidget> createState() => _BookListWidgetState();
}

class _BookListWidgetState extends State<BookListWidget> {
  @override
  void initState() {
    super.initState();

    Provider.of<BookListState>(context, listen: false).readBookList();

    syncLayer.onMessagesReceived = (_) {
      Provider.of<BookListState>(context, listen: false).readBookList();
    };
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<BookListState>(context);

    if (state.isLoading) {
      return const CircularProgressIndicator();
    }

    return ListView.builder(
      itemCount: state.books.length,
      itemBuilder: (context, index) {
        final book = state.books[index];
        return ListTile(
          title: Text(book.name),
          subtitle: Text('Pages: ${book.pages}'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => EditBookWidget(book: book)),
          ),
        );
      },
    );
  }
}
