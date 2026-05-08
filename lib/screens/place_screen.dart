import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/vote_service.dart';
import '../services/circle_service.dart';
import '../services/room_service.dart';
import 'package:chemeet/app_theme.dart';
import 'map_screen.dart';

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

class _PlaceScreenState extends State<PlaceScreen>
    with SingleTickerProviderStateMixin {
  final _voteService    = VoteService();
  final _circleService  = CircleService();
  final _roomService    = RoomService();
  final _db             = FirebaseFirestore.instance;

  late final TabController _tabController;

  List<Map<String, dynamic>> _votes   = [];
  List<Map<String, dynamic>> _circles = [];
  String? _mySelectedId;
  StreamSubscription? _voteSub;
  StreamSubscription? _roomSub;

  bool _isNavigating      = false;
  bool _confirmedShown    = false;
  bool _confirmDialogOpen = false;
  bool _isConfirming      = false;
  bool _tieDetected       = false;

  static const _circleColors = ['#9D8EFF', '#FF6584', '#FFB347', '#4ECDC4'];

  double _expansion = 1.0;

  static double _radiusExpansion(int score) {
    if (score <= 40) return 1.0;
    if (score <= 70) return 1.3;
    return 1.5;
  }

  // ── 생명주기 ────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() { if (!_tabController.indexIsChanging) setState(() {}); });
    _loadCircles();
    _voteSub = _voteService.watchVotes(widget.roomId).listen((votes) {
      final myVote = votes.firstWhere(
        (v) => v['userId'] == widget.userId,
        orElse: () => {},
      );
      setState(() {
        _votes = votes;
        _mySelectedId = myVote['selectedPlaceId'] as String?;
      });
      // 투표가 비워지면 플래그 초기화 (동점 후 재투표 대비)
      if (votes.isEmpty) {
        _isConfirming = false;
        _tieDetected  = false;
      }
      _checkAllVoted(votes);
    });
    _watchRoom();
  }

  Future<void> _loadCircles() async {
    final raw      = await _circleService.getAllCircles(widget.roomId);
    final roomSnap = await _db.collection('rooms').doc(widget.roomId).get();
    final score    = ((roomSnap.data() ?? {})['intimacyScore'] as num?)?.toInt() ?? 50;
    final expansion = _radiusExpansion(score);

    final colored = raw.asMap().entries.map((e) => {
      ...e.value,
      'radius': ((e.value['radius'] as num?) ?? 0) * expansion,
      'color': _circleColors[e.key % _circleColors.length],
    }).toList();
    if (mounted) setState(() {
      _circles  = colored;
      _expansion = expansion;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
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
        _isNavigating = true;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MapScreen(
              roomId:     widget.roomId,
              myUserId:   widget.userId,
              myUserName: widget.userName,
              members:    widget.members,
            ),
          ),
        );
        return;
      }

      if (status == 'waiting') {
        _isNavigating = true;
        if (_confirmedShown) {
          // 확정 후 초기화된 경우 → 조용히 홈으로
          if (mounted) {
            if (_confirmDialogOpen) Navigator.of(context).pop(); // 팝업 닫기
            Navigator.of(context).pop(); // PlaceScreen 나가기
          }
        } else {
          // 실제로 멤버가 나간 경우
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('멤버가 나가 처음으로 돌아갑니다')),
            );
            Navigator.pop(context);
          }
        }
        return;
      }

      if (status == 'idle') {
        // 다시 만들기 → RoomHomeScreen까지
        _isNavigating = true;
        Navigator.pop(context);
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
  Future<void> _checkAllVoted(List<Map<String, dynamic>> votes) async {
    if (_isConfirming || _tieDetected) return;
    if (votes.length < widget.members.length) return;
    final allSelected = votes.every((v) => v['selectedPlaceId'] != null);
    if (!allSelected) return;

    final Map<String, int> tally = {};
    for (final v in votes) {
      final id = v['selectedPlaceId'] as String;
      tally[id] = (tally[id] ?? 0) + 1;
    }

    final maxVotes = tally.values.reduce((a, b) => a > b ? a : b);
    final topEntries = tally.entries.where((e) => e.value == maxVotes).toList();

    // 동점 처리
    if (topEntries.length > 1) {
      _tieDetected = true;
      if (mounted) _showTieDialog();
      return;
    }

    _isConfirming = true;
    final topId = topEntries.first.key;
    final confirmed = widget.places.firstWhere(
      (p) => (p['kakaoId'] ?? '') == topId,
      orElse: () => widget.places.first,
    );
    await Future.wait([
      _roomService.saveConfirmHistory(
        roomId:         widget.roomId,
        confirmedPlace: confirmed,
        members:        widget.members,
      ),
      _circleService.confirmPlace(widget.roomId, confirmed),
    ]);
  }

  Future<void> _selectPlace(String placeId) async {
    if (_mySelectedId == placeId) {
      setState(() => _mySelectedId = null);
      await _voteService.clearVote(
        roomId: widget.roomId,
        userId: widget.userId,
      );
    } else {
      setState(() => _mySelectedId = placeId);
      await _voteService.selectPlace(
        roomId: widget.roomId,
        userId: widget.userId,
        userName: widget.userName,
        placeId: placeId,
      );
    }
  }

  // ── 메뉴 액션 ────────────────────────────────────────────

  /// 다시 그리기
  /// places·votes만 지우고 status → 'drawing'
  /// (_watchRoom이 'drawing'을 감지해 자동으로 이 화면을 pop)
  Future<void> _resetAndRedraw() async {
    // 서브컬렉션을 먼저 삭제한 뒤 status를 변경해야
    // _watchRoom이 'drawing'을 감지해 MapScreen으로 넘어갈 때 데이터가 깨끗함
    await _roomService.deleteSubcollection(widget.roomId, 'votes');
    await _roomService.deleteSubcollection(widget.roomId, 'circles');
    await _db.collection('rooms').doc(widget.roomId).update({
      'places': [],
      'status': 'drawing',
    });
  }

  /// 다시 만들기
  /// 날짜·원·장소 모두 초기화, status → 'idle'
  Future<void> _resetAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _SimpleDialog(
        title: '다시 만들기',
        content: '날짜, 원, 장소를 모두 초기화하고\n처음부터 다시 시작할까요?',
        actions: [
          _DialogAction(label: '취소',    onTap: () => Navigator.pop(context, false)),
          _DialogAction(label: '초기화',  primary: true, destructive: true,
              onTap: () => Navigator.pop(context, true)),
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

  // ── 동점 팝업 ────────────────────────────────────────────

  void _showTieDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SimpleDialog(
        title: '동점이에요',
        content: '득표수가 같아 장소를 확정할 수 없어요.\n다시 그리기를 하거나\n투표를 다시 진행해주세요.',
        actions: [
          _DialogAction(
            label: '다시 투표',
            onTap: () {
              Navigator.pop(context);
              setState(() { _tieDetected = false; _mySelectedId = null; });
              _roomService.deleteSubcollection(widget.roomId, 'votes');
            },
          ),
          _DialogAction(
            label: '다시 그리기',
            primary: true,
            onTap: () {
              Navigator.pop(context);
              _resetAndRedraw();
            },
          ),
        ],
      ),
    );
  }

  // ── 확정 팝업 ────────────────────────────────────────────

  /// 장소 확정 다이얼로그 표시
  /// 확인 버튼 → confirmAndReset 호출 → RoomHomeScreen으로 popUntil
  void _showConfirmedDialog(
      Map<String, dynamic> place, List<String> members) {
    if (!mounted) return;
    _confirmDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmedDialog(
        place: place,
        onConfirm: () {
          _isNavigating      = true;
          _confirmDialogOpen = false;
          if (mounted) {
            Navigator.of(context).pop(); // 팝업 닫기
            Navigator.of(context).pop(); // PlaceScreen → RoomHome
          }
          _cleanupConfirmedSession(); // 이전 세션 데이터 정리
        },
      ),
    ).then((_) => _confirmDialogOpen = false);
  }

  /// 확정 후 세션 데이터 정리 (circles/votes/messages 삭제 + status 초기화)
  /// 양쪽 유저가 동시에 호출해도 멱등적으로 동작
  Future<void> _cleanupConfirmedSession() async {
    await _db.collection('rooms').doc(widget.roomId).update({
      'status':          'waiting',
      'places':          FieldValue.delete(),
      'confirmedPlace':  FieldValue.delete(),
      'appointmentDate': FieldValue.delete(),
      'historySaved':    FieldValue.delete(),
    });
    for (final col in ['circles', 'messages', 'votes']) {
      await _roomService.deleteSubcollection(widget.roomId, col);
    }
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              if (v == 'redraw')  _resetAndRedraw();
              if (v == 'restart') _resetAll();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'redraw',
                child: Row(children: [
                  Icon(Icons.refresh_rounded, size: 18, color: AppTheme.primary),
                  SizedBox(width: 10),
                  Text('다시 그리기'),
                ]),
              ),
              const PopupMenuItem(
                value: 'restart',
                child: Row(children: [
                  Icon(Icons.replay_rounded, size: 18, color: AppTheme.error),
                  SizedBox(width: 10),
                  Text('다시 만들기', style: TextStyle(color: AppTheme.error)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 투표 현황 바 ──
          Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                SizedBox(
                  width: 80,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: widget.members.isEmpty
                          ? 0
                          : votedCount / widget.members.length,
                      backgroundColor: AppTheme.border,
                      valueColor:
                          const AlwaysStoppedAnimation(AppTheme.primary),
                      minHeight: 6,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 탭 바 ──
          ColoredBox(
            color: AppTheme.surface,
            child: TabBar(
              controller: _tabController,
              tabs: const [Tab(text: '목록'), Tab(text: '지도')],
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textMuted,
              indicatorColor: AppTheme.primary,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),

          const Divider(height: 1),

          // ── 탭 내용 ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 목록 탭
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: widget.places.length,
                  itemBuilder: (context, index) {
                    final place   = widget.places[index];
                    final placeId = place['kakaoId'] ?? '$index';
                    final isSelected = _mySelectedId == placeId;
                    final voterNames = _votes
                        .where((v) => v['selectedPlaceId'] == placeId)
                        .map((v) => (v['userName'] as String?) ?? '')
                        .where((n) => n.isNotEmpty)
                        .toList();
                    final url = (place['url'] ?? place['kakaoUrl']) as String?;
                    return _PlaceCard(
                      place:       place,
                      placeId:     placeId,
                      rank:        index + 1,
                      isSelected:  isSelected,
                      voterNames:  voterNames,
                      onSelect:    () => _selectPlace(placeId),
                      onDetail: url != null && url.isNotEmpty
                          ? () => showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => _KakaoPlaceSheet(
                                  name: place['name'] ?? '',
                                  url:  url,
                                ),
                              )
                          : null,
                    );
                  },
                ),

                // 지도 탭
                _circles.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.primary))
                    : Stack(
                        children: [
                          _PlaceMapView(
                            kakaoApiKey: dotenv.env['KAKAO_JS_KEY'] ?? '',
                            circles: _circles,
                            places:  widget.places,
                          ),
                          if (_expansion > 1.0)
                            Positioned(
                              top: 12, left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.88),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '친밀도로 탐색 범위 ${(_expansion * 100).toInt()}% 확장',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                        ],
                      ),
              ],
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
  final List<String> voterNames;
  final VoidCallback onSelect;
  final VoidCallback? onDetail;

  const _PlaceCard({
    required this.place,
    required this.placeId,
    required this.rank,
    required this.isSelected,
    required this.voterNames,
    required this.onSelect,
    this.onDetail,
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
              color: AppTheme.primary.withValues(alpha: 0.12),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((place['category'] as String?)?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          place['category']!,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // 지도 아이콘 + 선택 버튼
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (onDetail != null) ...[
                      GestureDetector(
                        onTap: onDetail,
                        child: const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Icon(Icons.map_outlined,
                              size: 22, color: AppTheme.primary),
                        ),
                      ),
                    ],
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
                            color: isSelected
                                ? Colors.white
                                : AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // 투표자 닉네임
            if (voterNames.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: voterNames
                    .map((name) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            name,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600),
                          ),
                        ))
                    .toList(),
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

class _ConfirmedDialog extends StatelessWidget {
  final Map<String, dynamic> place;
  final VoidCallback onConfirm;

  const _ConfirmedDialog({required this.place, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final name     = place['name']     ?? '';
    final address  = place['address']  ?? '';
    final category = place['category'] ?? '';

    return _SimpleDialog(
      title: '약속 장소가 확정됐어요!',
      content: null,
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark)),
          if (category.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(category,
                style: const TextStyle(fontSize: 12, color: AppTheme.primary)),
          ],
          if (address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on_outlined,
                  size: 13, color: AppTheme.textMuted),
              const SizedBox(width: 3),
              Expanded(
                child: Text(address,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textMuted)),
              ),
            ]),
          ],
        ],
      ),
      actions: [
        _DialogAction(
            label: '확인하고 홈으로', primary: true, onTap: onConfirm),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// 카카오맵 장소 상세 시트
// ════════════════════════════════════════════════════════════

class _KakaoPlaceSheet extends StatefulWidget {
  final String name;
  final String url;

  const _KakaoPlaceSheet({required this.name, required this.url});

  @override
  State<_KakaoPlaceSheet> createState() => _KakaoPlaceSheetState();
}

class _KakaoPlaceSheetState extends State<_KakaoPlaceSheet> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) '
          'Version/17.0 Mobile/15E148 Safari/604.1')
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 핸들 + 헤더
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 8, 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.name,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: AppTheme.textMuted),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),
          // WebView
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loading)
                  const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 교집합 확인 지도
// ════════════════════════════════════════════════════════════

class _PlaceMapView extends StatefulWidget {
  final String                     kakaoApiKey;
  final List<Map<String, dynamic>> circles; // {lat, lng, radius, userName, color}
  final List<Map<String, dynamic>> places;  // {name, lat, lng, ...}

  const _PlaceMapView({
    required this.kakaoApiKey,
    required this.circles,
    required this.places,
  });

  @override
  State<_PlaceMapView> createState() => _PlaceMapViewState();
}

class _PlaceMapViewState extends State<_PlaceMapView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'MapReadyChannel',
        onMessageReceived: (_) => _initMapData(),
      )
      ..addJavaScriptChannel(
        'PlaceTappedChannel',
        onMessageReceived: (msg) {
          final idx = int.tryParse(msg.message) ?? 0;
          if (idx < widget.places.length && mounted) {
            final place = widget.places[idx];
            final url = (place['url'] ?? place['kakaoUrl']) as String?;
            if (url != null && url.isNotEmpty) {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _KakaoPlaceSheet(
                  name: place['name'] ?? '',
                  url: url,
                ),
              );
            }
          }
        },
      )
      ..loadHtmlString(_buildHtml());
  }

  void _initMapData() {
    final circlesJson = jsonEncode(widget.circles
        .map((c) => {
              'lat':      c['lat'],
              'lng':      c['lng'],
              'radius':   c['radius'],
              'userName': c['userName'] ?? '',
              'color':    c['color'] ?? '#9D8EFF',
            })
        .toList());
    final placesJson = jsonEncode(widget.places
        .map((p) => {
              'name': p['name'] ?? '',
              'lat':  p['lat'],
              'lng':  p['lng'],
            })
        .toList());
    final cEnc = Uri.encodeComponent(circlesJson);
    final pEnc = Uri.encodeComponent(placesJson);
    _controller.runJavaScript(
        'initMapData(JSON.parse(decodeURIComponent("$cEnc")), JSON.parse(decodeURIComponent("$pEnc")))');
  }

  @override
  Widget build(BuildContext context) =>
      WebViewWidget(controller: _controller);

  String _buildHtml() => '''
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0,user-scalable=yes">
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;700&display=swap" rel="stylesheet">
  <style>
    * { margin:0; padding:0; box-sizing:border-box; font-family:"Noto Sans KR",-apple-system,"Apple SD Gothic Neo",system-ui,sans-serif; }
    body { width:100vw; height:100vh; overflow:hidden; }
    #map { width:100%; height:100%; }
    /* 핀 래퍼: 원(30×30)만 flow에 포함, 레이블은 absolute로 위에 띄움 */
    .pm { position:relative; width:30px; height:30px; cursor:pointer; }
    .pm-num {
      width:30px; height:30px; border-radius:50%;
      background:#FF5F7E; color:#fff;
      display:flex; align-items:center; justify-content:center;
      font-weight:700; font-size:13px;
      box-shadow:0 2px 6px rgba(0,0,0,0.28);
    }
    .pm-name {
      position:absolute; bottom:calc(100% + 4px); left:50%;
      transform:translateX(-50%);
      background:#fff; color:#1C1C2E;
      padding:3px 8px; border-radius:8px;
      font-size:11px;
      white-space:nowrap; max-width:110px;
      overflow:hidden; text-overflow:ellipsis;
      box-shadow:0 1px 4px rgba(0,0,0,0.14);
      pointer-events:none;
    }
    .cm {
      padding:3px 9px; border-radius:10px;
      font-size:11px; font-weight:600;
      color:#fff; white-space:nowrap;
      box-shadow:0 1px 4px rgba(0,0,0,0.18);
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=${widget.kakaoApiKey}"></script>
  <script>
    var map;
    kakao.maps.load(function() {
      map = new kakao.maps.Map(document.getElementById('map'), {
        center: new kakao.maps.LatLng(37.5665, 126.9780),
        level: 7
      });
      MapReadyChannel.postMessage('ready');
    });

    function initMapData(circles, places) {
      var bounds = new kakao.maps.LatLngBounds();

      // 원 + 이름 레이블
      circles.forEach(function(c) {
        new kakao.maps.Circle({
          map: map,
          center: new kakao.maps.LatLng(c.lat, c.lng),
          radius: c.radius,
          strokeWeight: 2,
          strokeColor: c.color,
          strokeOpacity: 0.9,
          fillColor: c.color,
          fillOpacity: 0.15
        });

        var label = document.createElement('div');
        label.className = 'cm';
        label.style.background = c.color;
        label.innerText = c.userName;
        new kakao.maps.CustomOverlay({
          map: map,
          position: new kakao.maps.LatLng(c.lat, c.lng),
          content: label,
          yAnchor: 0.5
        });

        var dLat = c.radius / 111000;
        var dLng = c.radius / (111000 * Math.cos(c.lat * Math.PI / 180));
        bounds.extend(new kakao.maps.LatLng(c.lat + dLat, c.lng + dLng));
        bounds.extend(new kakao.maps.LatLng(c.lat - dLat, c.lng - dLng));
      });

      // 장소 번호 마커
      places.forEach(function(p, i) {
        var wrap = document.createElement('div');
        wrap.className = 'pm';

        var name = document.createElement('div');
        name.className = 'pm-name';
        name.innerText = p.name;

        var num = document.createElement('div');
        num.className = 'pm-num';
        num.innerText = (i + 1) + '';

        wrap.appendChild(name); // absolute → 원 위에 띄워짐
        wrap.appendChild(num);  // 원 자체가 flow 기준

        (function(idx) {
          wrap.addEventListener('click', function() {
            PlaceTappedChannel.postMessage(idx + '');
          });
        })(i);

        new kakao.maps.CustomOverlay({
          map: map,
          position: new kakao.maps.LatLng(p.lat, p.lng),
          content: wrap,
          yAnchor: 0.5  // 원의 중심 = 좌표
        });

        bounds.extend(new kakao.maps.LatLng(p.lat, p.lng));
      });

      if (circles.length > 0 || places.length > 0) {
        map.setBounds(bounds, 60);
      }
    }
  </script>
</body>
</html>
''';
}

// ════════════════════════════════════════════════════════════
// 공용 심플 다이얼로그
// ════════════════════════════════════════════════════════════

class _DialogAction {
  final String label;
  final bool   primary;
  final bool   destructive;
  final VoidCallback onTap;

  const _DialogAction({
    required this.label,
    required this.onTap,
    this.primary     = false,
    this.destructive = false,
  });
}

class _SimpleDialog extends StatelessWidget {
  final String  title;
  final String? content;
  final Widget? extra;
  final List<_DialogAction> actions;

  const _SimpleDialog({
    required this.title,
    required this.content,
    required this.actions,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark),
              textAlign: TextAlign.center,
            ),
            if (content != null) ...[
              const SizedBox(height: 12),
              Text(
                content!,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textMuted, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
            if (extra != null) ...[
              const SizedBox(height: 16),
              extra!,
            ],
            const SizedBox(height: 24),
            Row(
              children: actions.map((a) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: a == actions.first ? 0 : 6),
                    child: a.primary
                        ? ElevatedButton(
                            onPressed: a.onTap,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: a.destructive
                                  ? AppTheme.error
                                  : AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(a.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                          )
                        : OutlinedButton(
                            onPressed: a.onTap,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.border),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(a.label,
                                style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textMuted)),
                          ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
