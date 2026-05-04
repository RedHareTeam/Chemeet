import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class RoomService {
  final _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  // 방 생성
  Future<String> createRoom({
    required String myUserId,
    required String myUserName,
    String roomTitle = '',
    int maxMembers = 2,
  }) async {
    final roomId = _uuid.v4().substring(0, 8);
    final inviteCode = _uuid.v4().substring(0, 6).toUpperCase();

    await _db.collection('rooms').doc(roomId).set({
      'createdBy': myUserId,
      'members': [myUserId],
      'memberNames': {myUserId: myUserName},
      'status': 'waiting', // 분석 전 대기 상태
      'inviteCode': inviteCode,
      'roomTitle': roomTitle,
      'maxMembers': maxMembers,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('users').doc(myUserId).update({
      'rooms': FieldValue.arrayUnion([roomId]),
    });

    return roomId;
  }

  // 초대 코드로 방 입장
  Future<String?> joinRoom({
    required String inviteCode,
    required String myUserId,
    required String myUserName,
  }) async {
    final snap = await _db
        .collection('rooms')
        .where('inviteCode', isEqualTo: inviteCode)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

    final roomDoc = snap.docs.first;
    final roomId = roomDoc.id;
    final members = List<String>.from(roomDoc.data()['members'] ?? []);

    // 이미 참여 중이면 바로 반환
    if (members.contains(myUserId)) return roomId;

    await _db.collection('rooms').doc(roomId).update({
      'members': FieldValue.arrayUnion([myUserId]),
      'memberNames.$myUserId': myUserName,
    });

    await _db.collection('users').doc(myUserId).update({
      'rooms': FieldValue.arrayUnion([roomId]),
    });

    return roomId;
  }

  // 내 방 목록 실시간 구독
  Stream<List<Map<String, dynamic>>> watchMyRooms(String userId) {
    return _db
        .collection('rooms')
        .where('members', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => {...d.data(), 'roomId': d.id}).toList());
  }

  // 단일 방 실시간 구독
  Stream<Map<String, dynamic>?> watchRoom(String roomId) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .snapshots()
        .map((snap) =>
    snap.exists ? {...snap.data()!, 'roomId': snap.id} : null);
  }

  // 방 정보 단건 조회
  Future<Map<String, dynamic>?> getRoom(String roomId) async {
    final snap = await _db.collection('rooms').doc(roomId).get();
    return snap.exists ? {...snap.data()!, 'roomId': snap.id} : null;
  }

  // 장소 확정 후 히스토리 저장 + 서브컬렉션 초기화
  Future<void> confirmAndReset({
    required String roomId,
    required Map<String, dynamic> confirmedPlace,
    required List<String> members,
  }) async {
    // 방 데이터에서 appointmentDate 가져오기
    final roomSnap = await _db.collection('rooms').doc(roomId).get();
    final appointmentDate = roomSnap.data()?['appointmentDate'];

    final batch = _db.batch();
    final roomRef = _db.collection('rooms').doc(roomId);

    // 히스토리에 장소 + 약속날짜 저장
    batch.set(roomRef.collection('history').doc(), {
      'confirmedPlace': confirmedPlace,
      'members': members,
      'appointmentDate': appointmentDate,  // ← 추가
      'date': FieldValue.serverTimestamp(),
    });

    // status waiting으로 초기화
    batch.update(roomRef, {
      'status': 'waiting',
      'places': FieldValue.delete(),
      'confirmedPlace': FieldValue.delete(),
      'appointmentDate': FieldValue.delete(),
    });

    await batch.commit();

    for (final col in ['circles', 'messages', 'votes']) {
      await _deleteSubcollection(roomId, col);
    }
  }

  Future<void> _deleteSubcollection(String roomId, String col) async {
    final snap = await _db
        .collection('rooms')
        .doc(roomId)
        .collection(col)
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // 만남 히스토리 구독
  Stream<List<Map<String, dynamic>>> watchHistory(String roomId) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('history')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // 특정 서브컬렉션의 모든 문서를 일괄 삭제
  Future<void> deleteSubcollection(String roomId, String sub) async {
    final snap = await _db.collection('rooms').doc(roomId).collection(sub).get();
    for (final doc in snap.docs) await doc.reference.delete();
  }
}