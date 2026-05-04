import 'dart:async';
import 'package:chemeet/app_theme.dart';
import 'package:chemeet/screens/place_screen.dart';
import 'package:flutter/material.dart';
import '../services/room_service.dart';
import 'date_setting_screen.dart';
import 'map_screen.dart';

class RoomHomeScreen extends StatefulWidget {
  final String roomId;
  final String myUserId;
  final String myUserName;
  final int    maxMembers;

  const RoomHomeScreen({
    super.key,
    required this.roomId,
    required this.myUserId,
    required this.myUserName,
    required this.maxMembers,
  });

  @override
  State<RoomHomeScreen> createState() => _RoomHomeScreenState();
}

class _RoomHomeScreenState extends State<RoomHomeScreen>
    with SingleTickerProviderStateMixin {
  final _roomService = RoomService();

  late AnimationController _scoreAnim;
  late Animation<int>      _scoreCounter;

  List<Map<String, dynamic>> _schedules = [];
  StreamSubscription?        _scheduleSub;
  Map<String, dynamic>?      _roomData;
  StreamSubscription?        _roomSub;

  // Firestore에서 읽어온 분석 데이터
  int           _intimacyScore = 0;
  List<String>  _keywords      = [];
  String        _partnerName   = '';
  bool          _analysisReady = false;

  @override
  void initState() {
    super.initState();

    _scoreAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    // 초기엔 0→0, 데이터 로드 후 재설정
    _scoreCounter = IntTween(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _scoreAnim, curve: Curves.easeOut),
    );

    _watchRoom();
    _watchSchedules();
  }

  void _watchRoom() {
    _roomSub = _roomService.watchRoom(widget.roomId).listen((room) {
      if (room == null) return;

      final newScore       = (room['intimacyScore'] as num?)?.toInt() ?? 0;
      final newKeywords    = List<String>.from(room['keywords'] ?? []);
      final newPartnerName = room['partnerName'] as String? ?? '';

      // 분석 데이터가 새로 들어왔을 때만 애니메이션 재실행
      if (newScore != _intimacyScore || !_analysisReady) {
        _scoreAnim.reset();
        _scoreCounter = IntTween(begin: 0, end: newScore).animate(
          CurvedAnimation(parent: _scoreAnim, curve: Curves.easeOut),
        );
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _scoreAnim.forward();
        });
      }

      setState(() {
        _roomData      = room;
        _intimacyScore = newScore;
        _keywords      = newKeywords;
        _partnerName   = newPartnerName;
        _analysisReady = newScore > 0 || newKeywords.isNotEmpty;
      });
    });
  }

  void _watchSchedules() {
    _scheduleSub =
        _roomService.watchHistory(widget.roomId).listen((history) {
          final now = DateTime.now();
          final upcoming = history.where((h) {
            final dateTs = h['appointmentDate'];
            if (dateTs == null) return false;
            final date = (dateTs as dynamic).toDate() as DateTime;
            return date.isAfter(now);
          }).toList();

          upcoming.sort((a, b) {
            final da = (a['appointmentDate'] as dynamic).toDate() as DateTime;
            final db = (b['appointmentDate'] as dynamic).toDate() as DateTime;
            return da.compareTo(db);
          });

          setState(() => _schedules = upcoming.cast<Map<String, dynamic>>());
        });
  }

  Color _intimacyColor(int score) {
    if (score >= 80) return AppTheme.primary;
    if (score >= 60) return const Color(0xFF4ECDC4);
    if (score >= 40) return const Color(0xFFFFBE0B);
    return const Color(0xFFFF6584);
  }

  String _intimacyLabel(int score) {
    if (score >= 80) return '매우 친밀해요';
    if (score >= 60) return '꽤 가까운 사이예요';
    if (score >= 40) return '친해지는 중이에요';
    return '아직은 서먹서먹해요';
  }

  String _weekdayLabel(int wd) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[(wd - 1) % 7];
  }

  @override
  void dispose() {
    _scoreAnim.dispose();
    _scheduleSub?.cancel();
    _roomSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inviteCode     = _roomData?['inviteCode'] ?? '';
    final currentMembers = List<String>.from(_roomData?['members'] ?? [widget.myUserId]);
    final isFull         = currentMembers.length >= widget.maxMembers;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(_roomData?['roomTitle'] ?? 'Chemeet'),
        actions: [
          if (inviteCode.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('초대 코드: $inviteCode'),
                        action: SnackBarAction(label: '복사', onPressed: () {}),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.tag, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          inviteCode,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ─── 참여 인원 현황 ───────────────────────────
            Builder(builder: (_) {
              final memberNames = Map<String, dynamic>.from(
                  _roomData?['memberNames'] ?? {});
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isFull ? AppTheme.primaryBg : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isFull
                        ? AppTheme.primary.withOpacity(0.3)
                        : Colors.orange.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isFull ? Icons.group : Icons.group_outlined,
                          color: isFull
                              ? AppTheme.primary
                              : Colors.orange.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isFull
                              ? '${currentMembers.length}/${widget.maxMembers}명 모두 참여했어요!'
                              : '${currentMembers.length}/${widget.maxMembers}명 참여 중 · 초대 코드로 친구를 초대하세요',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isFull
                                ? AppTheme.primary
                                : Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                    if (currentMembers.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: ([widget.myUserId,
                          ...currentMembers.where((uid) => uid != widget.myUserId),
                        ]).map((uid) {
                          final name = memberNames[uid] as String? ?? uid;
                          final isMe = uid == widget.myUserId;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isMe ? AppTheme.primary : AppTheme.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isMe ? AppTheme.primary : AppTheme.border,
                              ),
                            ),
                            child: Text(
                              isMe ? '$name (나)' : name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isMe ? Colors.white : AppTheme.textDark,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              );
            }),

            const SizedBox(height: 20),

            // ─── 친밀도 분석 리포트 ───────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _analysisReady
                  ? _buildAnalysisContent()
                  : _buildAnalysisLoading(),
            ),

            const SizedBox(height: 24),

            // ─── 메인 액션 버튼 (상태별) ─────────────────
            Builder(builder: (_) {
              final status  = _roomData?['status'] ?? 'idle';
              final members = List<String>.from(_roomData?['members'] ?? []);

              String       label;
              IconData     icon;
              Color        color;
              bool         enabled;
              VoidCallback? onTap;

              if (status == 'voting') {
                label   = '장소 투표 진행 중 · 참여하기';
                icon    = Icons.how_to_vote_outlined;
                color   = AppTheme.accent;
                enabled = true;
                onTap   = () {
                  final places = List<Map<String, dynamic>>.from(
                      _roomData?['places'] ?? []);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlaceScreen(
                        roomId:   widget.roomId,
                        userId:   widget.myUserId,
                        userName: widget.myUserName,
                        members:  members,
                        places:   places,
                      ),
                    ),
                  );
                };
              } else if (status == 'drawing' &&
                  _roomData?['appointmentDate'] != null) {
                label   = '약속을 정하는 중이에요 · 지도 보기';
                icon    = Icons.map_outlined;
                color   = const Color(0xFF4ECDC4);
                enabled = true;
                onTap   = () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MapScreen(
                      roomId:     widget.roomId,
                      myUserId:   widget.myUserId,
                      myUserName: widget.myUserName,
                      members:    members,
                    ),
                  ),
                );
              } else if (!isFull) {
                label   = '${widget.maxMembers - members.length}명 더 참여해야 약속을 만들 수 있어요';
                icon    = Icons.group_outlined;
                color   = Colors.grey;
                enabled = false;
                onTap   = null;
              } else {
                label   = '약속 만들기';
                icon    = Icons.add_circle_outline;
                color   = AppTheme.primary;
                enabled = true;
                onTap   = () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DateSettingScreen(
                      roomId:     widget.roomId,
                      myUserId:   widget.myUserId,
                      myUserName: widget.myUserName,
                      maxMembers: widget.maxMembers,
                      members:    currentMembers,
                    ),
                  ),
                );
              }

              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: enabled ? color : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: enabled
                      ? [
                    BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ]
                      : [],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon,
                              color: enabled
                                  ? Colors.white
                                  : Colors.grey.shade400,
                              size: 20),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: enabled
                                    ? Colors.white
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 28),

            // ─── 다가오는 약속 ────────────────────────────
            Text(
              '다가오는 약속',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 12),

            if (_schedules.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 36, color: Colors.grey.shade300),
                    const SizedBox(height: 10),
                    Text(
                      '아직 약속이 없어요\n위 버튼으로 첫 약속을 잡아보세요!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...List.generate(_schedules.length, (i) {
                final s       = _schedules[i];
                final place   = Map<String, dynamic>.from(
                    s['confirmedPlace'] as Map? ?? {});
                final dateTs  = s['appointmentDate'];
                final date    = (dateTs as dynamic).toDate() as DateTime;
                final isNext  = i == 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isNext
                          ? AppTheme.primary.withOpacity(0.4)
                          : AppTheme.border,
                      width: isNext ? 1.5 : 1,
                    ),
                    boxShadow: isNext
                        ? [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      )
                    ]
                        : [],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isNext
                              ? AppTheme.primaryBg
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${date.month}/${date.day}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isNext
                                    ? AppTheme.primary
                                    : Colors.grey.shade500,
                              ),
                            ),
                            Text(
                              _weekdayLabel(date.weekday),
                              style: TextStyle(
                                fontSize: 10,
                                color: isNext
                                    ? AppTheme.primary
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isNext)
                              Text(
                                'D-DAY 가장 가까운 약속',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            Text(
                              place['name'] ?? '장소 미정',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              place['address'] ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── 분석 결과 위젯 ────────────────────────────────────
  Widget _buildAnalysisContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '친밀도 분석 리포트',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // 점수
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AnimatedBuilder(
              animation: _scoreCounter,
              builder: (_, __) => Text(
                '${_scoreCounter.value}',
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.bold,
                  color: _intimacyColor(_intimacyScore),
                  height: 1,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(' / 100',
                  style: TextStyle(fontSize: 18, color: Colors.grey)),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // 게이지 바
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AnimatedBuilder(
            animation: _scoreAnim,
            builder: (_, __) => LinearProgressIndicator(
              value: _scoreAnim.value * (_intimacyScore / 100),
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation(_intimacyColor(_intimacyScore)),
              minHeight: 10,
            ),
          ),
        ),

        const SizedBox(height: 10),

        Text(
          _intimacyLabel(_intimacyScore),
          style: TextStyle(
            fontSize: 13,
            color: _intimacyColor(_intimacyScore),
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 16),

        // 취향 키워드
        Text(
          '취향 키워드',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _keywords.map((kw) {
            return Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.primaryBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '# $kw',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── 분석 대기 중 스켈레톤 ─────────────────────────────
  Widget _buildAnalysisLoading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '친밀도 분석 리포트',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
              const SizedBox(height: 12),
              Text(
                '분석 결과를 불러오는 중이에요...',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}