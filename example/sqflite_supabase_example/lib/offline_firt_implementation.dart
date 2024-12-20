import 'package:sqflite/sqflite.dart';
import 'package:talon/dart_offlne_first.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart';

class MyOfflineDB extends OfflineDatabase {
  late final Database localDb;

  @override
  Future<void> init() async {
    final databasePath = await getDatabasesPath();

    final dbPath = join(databasePath, 'example_app.db');

    localDb = await openDatabase(dbPath);
  }

  @override
  Future<List<String>> getAllLocalMessageIds() {
    throw UnimplementedError();
  }

  @override
  Future<bool> applyMessageToLocalDataTable(Message message) {
    throw UnimplementedError();
  }

  @override
  Future<bool> applyMessageToLocalMessageTable(Message message) {
    throw UnimplementedError();
  }
}
