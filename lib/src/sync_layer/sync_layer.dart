import 'package:dart_offlne_first/src/merkle_tree/merkle_tree.dart';
import 'package:dart_offlne_first/src/messages/message.dart';
import 'package:dart_offlne_first/src/offline_database/offline_database.dart';
import 'package:dart_offlne_first/src/online_database/online_database.dart';

class SyncLayer {
  late final MerkleTree _merkleTree;
  late final OnlineDatabase _onlineDatabase;
  late final OfflineDatabase _offlineDatabase;

  SyncLayer({
    required OnlineDatabase onlineDatabase,
    required OfflineDatabase offlineDatabase,
  }) {
    _onlineDatabase = onlineDatabase;
    _offlineDatabase = offlineDatabase;

    _merkleTree = MerkleTree(offlineDatabase: _offlineDatabase);
  }

  Future<void> runSync() async {
    final localMerkleTreeHash = await _merkleTree.createMerkleTree();
  }

  Future<void> getMessagesFromServer() async {}
}
