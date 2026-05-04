import 'package:cloud_firestore/cloud_firestore.dart';

/// 장소 선택(투표) 전담 서비스
class VoteService {
  final _db = FirebaseFirestore.instance;

  // 장소 선택 저장
  Future<void> selectPlace({
    required String roomId,
    required String userId,
    required String placeId,
  }) async {
    await _db
        .collection('rooms')
        .doc(roomId)
        .collection('votes')
        .doc(userId)
        .set({'userId': userId, 'selectedPlaceId': placeId}, SetOptions(merge: true));
  }

  // 투표 현황 실시간 구독
  Stream<List<Map<String, dynamic>>> watchVotes(String roomId) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('votes')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }
}
