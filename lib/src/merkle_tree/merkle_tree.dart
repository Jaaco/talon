import 'package:dart_offlne_first/src/offline_database/offline_database.dart';

class MerkleTree {
  final OfflineDatabase offlineDatabase;

  const MerkleTree({required this.offlineDatabase});

  Future<String> createMerkleTree() async {
    final messages = await offlineDatabase.getAllLocalMessageIds();

    return '';
  }

  String _hashMessageId(String messageId) {
    return messageId;
  }
}
