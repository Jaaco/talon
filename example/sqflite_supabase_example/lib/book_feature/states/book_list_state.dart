import 'package:flutter/material.dart';
import 'package:sqflite_supabase_example/book_feature/models/book.dart';

import '../repositories/book_repository.dart';

class BookListState extends ChangeNotifier {
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  List<Book> _books = [];
  List<Book> get books => _books;

  final _bookRepository = BookRepository();

  void addBook(String name) async {
    await _bookRepository.addBook(name);

    readBookList();
  }

  void readBookList() async {
    _books = await _bookRepository.readBooks();
    _isLoading = false;

    notifyListeners();
  }
}
