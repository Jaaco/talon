abstract interface class TodoRemoteDataSource {
  Future<void> sync();
}

class TodoRemoteDataSourceImpl implements TodoRemoteDataSource {
  final Future<void> Function() syncFromServer;

  TodoRemoteDataSourceImpl({required this.syncFromServer});

  @override
  Future<void> sync() => syncFromServer();
}
