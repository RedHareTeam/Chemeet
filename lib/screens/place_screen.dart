import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/vote_service.dart';
import '../services/circle_service.dart';
import '../services/room_service.dart';
import 'package:chemeet/app_theme.dart';

/// 장소 추천 & 투표 화면
/// - 모든 멤버가 투표 완료 → 최다 득표 장소 자동 확정 → 확정 팝업
/// - 다시 그리기: places·votes만 초기화, status → 'drawing' (지도로 돌아감)
/// - 다시 만들기: 날짜·원·장소 모두 초기화, status → 'idle' (RoomHome으로 돌아감)
/// - 확인 버튼: confirmAndReset 호출 후 RoomHomeScreen까지 popUntil
class PlaceScreen extends StatefulWidget {
  final String roomId;
  final String userId;
  final String userName;
  final List<String> members;
  final List<Map<String, dynamic>> places;

  const PlaceScreen({
    super.key,
    required this.roomId,
    required this.userId,
    required this.userName,
    required this.members,
    required this.places,
  });

  @override
  State<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends State<PlaceScreen> {
  final _voteService    = VoteService();
  final _circleService  = CircleService();
  final _roomService    = RoomService();
  final _db             = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _votes   = [];
  String? _mySelectedId;
  StreamSubscription? _voteSub;
  StreamSubscription? _roomSub;

  /// 화면 전환 중 중복 실행 방지
  bool _isNavigating  = false;
  /// 확정 팝업 중복 방지
  bool _confirmedShown = false;

  // ── 생명주기 ────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _voteSub = _voteService.watchVotes(widget.roomId).listen((votes) {
      setState(() => _votes = votes);
      _checkAllVoted(votes);
    });
    _watchRoom();
  }

  @override
  void dispose() {
    _voteSub?.cancel();
    _roomSub?.cancel();
    super.dispose();
  }

  // ── Firestore 구독 ───────────────────────────────────────

  /// 방 상태 실시간 감지
  /// - 'drawing'  → 다시 그리기 완료: 이 화면(PlaceScreen)만 pop → MapScreen으로 복귀
  /// - 'idle'     → 다시 만들기 완료: RoomHomeScreen까지 popUntil
  /// - 'confirmed' → 장소 확정 팝업 표시
  void _watchRoom() {
    _roomSub = _roomService.watchRoom(widget.roomId).listen((room) {
      if (room == null || _isNavigating || !mounted) return;
      final status = room['status'] as String? ?? '';

      if (status == 'drawing') {
        // 다시 그리기 → 이 화면만 닫기
        _isNavigating = true;
        Navigator.pop(context);
        return;
      }

      if (status == 'idle') {
        // 다시 만들기 → RoomHomeScreen까지
        _isNavigating = true;
        Navigator.popUntil(
          context,
              (route) => route.settings.name == 'RoomHomeScreen' || route.isFirst,
        );
        return;
      }

      if (status == 'confirmed' && !_confirmedShown) {
        _confirmedShown = true;
        final confirmed = Map<String, dynamic>.from(
            room['confirmedPlace'] as Map? ?? {});
        final members = List<String>.from(room['members'] ?? []);
        _showConfirmedDialog(confirmed, members);
      }
    });
  }

  // ── 투표 로직 ────────────────────────────────────────────

  /// 모든 멤버가 투표했으면 최다 득표 장소 확정
  void _checkAllVoted(List<Map<String, dynamic>> votes) {
    if (votes.length < widget.members.length) return;
    final allSelected = votes.every((v) => v['selectedPlaceId'] != null);
    if (!allSelected) return;

    final Map<String, int> tally = {};
    for (final v in votes) {
      final id = v['selectedPlaceId'] as String;
      tally[id] = (tally[id] ?? 0) + 1;
    }
    final topId =
        tally.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final confirmed = widget.places.firstWhere(
          (p) => (p['kakaoId'] ?? '') == topId,
      orElse: () => widget.places.first,
    );
    _circleService.confirmPlace(widget.roomId, confirmed);
  }

  Future<void> _selectPlace(String placeId) async {
    setState(() => _mySelectedId = placeId);
    await _voteService.selectPlace(
      roomId: widget.roomId,
      userId: widget.userId,
      placeId: placeId,
    );
  }

  // ── 메뉴 액션 ────────────────────────────────────────────

  /// 다시 그리기
  /// places·votes만 지우고 status → 'drawing'
  /// (_watchRoom이 'drawing'을 감지해 자동으로 이 화면을 pop)
  Future<void> _resetAndRedraw() async {
    final roomRef = _db.collection('rooms').doc(widget.roomId);
    // places 비우고 상태를 drawing으로 되돌림
    await roomRef.update({
      'places': [],
      'status': 'drawing',
    });
    // votes 서브컬렉션 삭제
    await _roomService.deleteSubcollection(widget.roomId, 'votes');
  }

  /// 다시 만들기
  /// 날짜·원·장소 모두 초기화, status → 'idle'
  Future<void> _resetAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('다시 만들기'),
        content: const Text('날짜, 원, 장소를 모두 초기화하고\n처음부터 다시 시작할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('초기화',
                style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final roomRef = _db.collection('rooms').doc(widget.roomId);
    await roomRef.update({
      'status': 'idle',
      'places': [],
      'appointmentDate': FieldValue.delete(),
      'confirmedPlace': FieldValue.delete(),
    });
    await _roomService.deleteSubcollection(widget.roomId, 'circles');
    await _roomService.deleteSubcollection(widget.roomId, 'votes');
    await _roomService.deleteSubcollection(widget.roomId, 'messages');
  }

  // ── 확정 팝업 ────────────────────────────────────────────

  /// 장소 확정 다이얼로그 표시
  /// 확인 버튼 → confirmAndReset 호출 → RoomHomeScreen으로 popUntil
  void _showConfirmedDialog(
      Map<String, dynamic> place, List<String> members) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmedDialog(
        place: place,
        onConfirm: () async {
          // 팝업 닫기
          if (mounted) Navigator.of(context).pop();

          // 히스토리 저장 + Firestore 초기화
          await _roomService.confirmAndReset(
            roomId: widget.roomId,
            confirmedPlace: place,
            members: members,
          );

          // RoomHomeScreen 또는 루트까지 스택 정리
          if (mounted) {
            _isNavigating = true;
            Navigator.popUntil(
              context,
                  (route) =>
              route.settings.name == 'RoomHomeScreen' || route.isFirst,
            );
          }
        },
      ),
    );
  }

  // ── 메뉴 바텀시트 ─────────────────────────────────────────

  void _showMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // 핸들 바
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading:
              const Icon(Icons.refresh_rounded, color: AppTheme.primary),
              title: const Text('다시 그리기',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('원만 초기화하고 지도로 돌아가요'),
              onTap: () {
                Navigator.pop(context); // 바텀시트 닫기
                _resetAndRedraw();
              },
            ),
            ListTile(
              leading:
              const Icon(Icons.replay_rounded, color: AppTheme.accent),
              title: const Text('다시 만들기',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: AppTheme.accent)),
              subtitle: const Text('날짜·원·장소 모두 초기화해요'),
              onTap: () {
                Navigator.pop(context); // 바텀시트 닫기
                _resetAll();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── 빌드 ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final votedCount =
        _votes.where((v) => v['selectedPlaceId'] != null).length;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('장소 추천'),
        actions: [
          IconButton(
              onPressed: _showMenu, icon: const Icon(Icons.more_vert)),
        ],
      ),
      body: Column(
        children: [
          // ── 투표 현황 바 ──
          Container(
            color: AppTheme.surface,
            padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.how_to_vote_outlined,
                    size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '투표 현황',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
                const SizedBox(width: 8),
                Text(
                  '$votedCount / ${widget.members.length}명 선택 완료',
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textMuted),
                ),
                const Spacer(),
                // 진행률 바
                SizedBox(
                  width: 80,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: widget.members.isEmpty
                          ? 0
                          : votedCount / widget.members.length,
                      backgroundColor: Colors.grey.shade100,
                      valueColor:
                      const AlwaysStoppedAnimation(AppTheme.primary),
                      minHeight: 6,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 장소 카드 리스트 ──
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.places.length,
              itemBuilder: (context, index) {
                final place   = widget.places[index];
                final placeId = place['kakaoId'] ?? '$index';
                final isSelected = _mySelectedId == placeId;
                final voteCount  = _votes
                    .where((v) => v['selectedPlaceId'] == placeId)
                    .length;

                return _PlaceCard(
                  place: place,
                  placeId: placeId,
                  rank: index + 1,
                  isSelected: isSelected,
                  voteCount: voteCount,
                  totalMembers: widget.members.length,
                  onSelect: () => _selectPlace(placeId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 장소 카드
// ════════════════════════════════════════════════════════════

class _PlaceCard extends StatelessWidget {
  final Map<String, dynamic> place;
  final String placeId;
  final int rank;
  final bool isSelected;
  final int voteCount;
  final int totalMembers;
  final VoidCallback onSelect;

  const _PlaceCard({
    required this.place,
    required this.placeId,
    required this.rank,
    required this.isSelected,
    required this.voteCount,
    required this.totalMembers,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppTheme.primary : AppTheme.border,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected
            ? [
          BoxShadow(
              color: AppTheme.primary.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ]
            : [],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 순위 뱃지
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: rank == 1 ? AppTheme.primary : AppTheme.bg,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: rank == 1 ? Colors.white : AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place['name'] ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppTheme.textDark),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        place['address'] ?? '',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                // 선택 버튼
                GestureDetector(
                  onTap: onSelect,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primary : AppTheme.bg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isSelected ? '✓ 선택됨' : '선택',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // 투표 진행 바
            if (totalMembers > 0) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: voteCount / totalMembers,
                        backgroundColor: Colors.grey.shade100,
                        valueColor:
                        const AlwaysStoppedAnimation(AppTheme.primary),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$voteCount명',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 장소 확정 다이얼로그
// ════════════════════════════════════════════════════════════

class _ConfirmedDialog extends StatefulWidget {
  final Map<String, dynamic> place;
  /// 확인 버튼 콜백 (팝업 닫기 + 네비게이션은 호출부에서 처리)
  final Future<void> Function() onConfirm;

  const _ConfirmedDialog({required this.place, required this.onConfirm});

  @override
  State<_ConfirmedDialog> createState() => _ConfirmedDialogState();
}

class _ConfirmedDialogState extends State<_ConfirmedDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final name     = widget.place['name']     ?? '';
    final address  = widget.place['address']  ?? '';
    final category = widget.place['category'] ?? '';

    return Dialog(
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 아이콘
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppTheme.primaryBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.place_rounded,
                  color: AppTheme.primary, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              '약속 장소가 확정됐어요!',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark),
            ),
            const SizedBox(height: 20),

            // 장소 정보 카드
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark),
                  ),
                  if (category.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        category,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.primary),
                      ),
                    ),
                  ],
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 13, color: AppTheme.textMuted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            address,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 확인 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading
                    ? null
                    : () async {
                  setState(() => _loading = true);
                  await widget.onConfirm();
                  // onConfirm 내부에서 팝업 닫기 + 네비게이션 처리
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                    : const Text(
                  '확인하고 홈으로',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
