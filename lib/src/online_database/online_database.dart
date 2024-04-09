import 'package:dart_offlne_first/src/messages/message.dart';

abstract class OnlineDatabase {
  Future<List<Message>> getMessagesFromServer(
      {required String localMerkleTreeHash});

  Future<String> fetchMerkleTreeHashFromServer();
}
