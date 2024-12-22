import 'package:sqflite_supabase_example/talon_implementation/sync_layer_implementation.dart';

import '../models/book.dart';

class BookRepository {
  final table = 'books';
  final nameField = 'name';
  final pagesField = 'pages';

  Future<void> addBook(String name) async {
    final id = DateTime.now().toString();

    await syncLayer.saveChange(
      table: table,
      row: id,
      column: nameField,
      value: name,
    );
  }

  void saveName({required String id, required String name}) {
    syncLayer.saveChange(
      table: table,
      row: id,
      column: nameField,
      value: name,
    );
  }

  Future<List<Book>> readBooks() async {
    final booksRaw = await offlineDatabase.runQuery('''
      SELECT *
      FROM $table;
   ''');

    return booksRaw.map(Book.fromMap).toList()..reversed;
  }
}
