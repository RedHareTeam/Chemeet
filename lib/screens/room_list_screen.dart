import 'package:chemeet/screens/room_home_screen.dart';
import 'package:chemeet/screens/upload_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/room_service.dart';
import 'auth_screen.dart';
import 'package:chemeet/app_theme.dart';

class RoomListScreen extends StatefulWidget {
  const RoomListScreen({super.key});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  final _authService = AuthService();
  final _roomService = RoomService();
  final _codeController = TextEditingController();

  Stream<List<Map<String, dynamic>>>? _roomStream;
  String get _myUserId => _authService.currentUser!.uid;
  String _myUserName = '';

  @override
  void initState() {
    super.initState();
    _roomStream = _roomService.watchMyRooms(_myUserId);
    _loadUserName();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadUserName() async {
    final info = await _authService.getUserInfo(_myUserId);
    setState(() => _myUserName = info?['userName'] ?? '');
  }

  Future<void> _createRoom() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UploadScreen()),
    );
  }

  Future<void> _joinRoom() async {
    _codeController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _JoinSheet(controller: _codeController, onJoin: _handleJoinCode),
    );
  }

  Future<void> _handleJoinCode(String code) async {
    final result = await _roomService.joinRoom(
      inviteCode: code,
      myUserId: _myUserId,
      myUserName: _myUserName,
    );
    if (!mounted) return;
    if (result == 'FULL') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('방이 가득 찼어요')));
    } else if (result != null) {
      final room = await _roomService.getRoom(result);
      if (room != null && mounted) _enterRoom(result, room);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('유효하지 않은 코드예요')));
    }
  }

  void _enterRoom(String roomId, Map<String, dynamic> room) {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: 'RoomHomeScreen'),
        builder: (_) => RoomHomeScreen(
          roomId: roomId,
          myUserId: _myUserId,
          myUserName: _myUserName,
          maxMembers: room['maxMembers'] ?? 2,
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Chemeet'),
        actions: [
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _roomStream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('오류: ${snap.error}'));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }

          final rooms = snap.data ?? [];
          if (rooms.isEmpty) return _buildEmpty();

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
            itemCount: rooms.length,
            itemBuilder: (_, i) => _RoomCard(
              room: rooms[i],
              myUserId: _myUserId,
              onTap: () => _enterRoom(rooms[i]['roomId'], rooms[i]),
            ),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Fab(
            heroTag: 'join',
            onPressed: _joinRoom,
            backgroundColor: AppTheme.surface,
            foregroundColor: AppTheme.primary,
            icon: Icons.vpn_key_rounded,
            tooltip: '코드로 입장',
          ),
          const SizedBox(height: 12),
          _Fab(
            heroTag: 'create',
            onPressed: _createRoom,
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            icon: Icons.add_rounded,
            tooltip: '방 만들기',
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryBg, AppTheme.accentBg],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.people_outline_rounded,
              size: 32,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '아직 참여 중인 방이 없어요',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '+ 버튼으로 새 방을 만들거나\n코드로 친구 방에 입장해보세요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textMuted,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 초대코드 바텀시트 ────────────────────────────────────────────
class _JoinSheet extends StatefulWidget {
  final TextEditingController controller;
  final Future<void> Function(String code) onJoin;

  const _JoinSheet({required this.controller, required this.onJoin});

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  bool _loading = false;

  Future<void> _submit() async {
    final code = widget.controller.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    Navigator.pop(context);
    await widget.onJoin(code);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들바
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // 아이콘
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, Color(0xFF9B8BFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.vpn_key_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            '초대 코드로 입장',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '친구에게 받은 6자리 코드를 입력하세요',
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 24),

          // 코드 입력 필드
          TextField(
            controller: widget.controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(6),
            ],
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 8,
              color: AppTheme.textDark,
            ),
            decoration: InputDecoration(
              hintText: '------',
              hintStyle: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
                color: AppTheme.border,
              ),
              filled: true,
              fillColor: AppTheme.bg,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppTheme.primary,
                  width: 1.5,
                ),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),

          // 입장 버튼
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      '입장하기',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 방 카드 ─────────────────────────────────────────────────────
class _RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final String myUserId;
  final VoidCallback onTap;

  const _RoomCard({
    required this.room,
    required this.myUserId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final roomTitle = room['roomTitle'] as String? ?? '제목 없음';
    final memberNames = Map<String, dynamic>.from(room['memberNames'] ?? {});
    final names = memberNames.values.map((e) => e.toString()).toList();
    final status = room['status'] as String? ?? 'idle';
    final isActive = status == 'drawing' || status == 'voting';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive
                ? _statusColor(status).withValues(alpha: 0.3)
                : AppTheme.border,
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? _statusColor(status).withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
          child: Row(
            children: [
            // 아바타
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: isActive
                    ? _statusColor(status).withValues(alpha: 0.15)
                    : AppTheme.primaryBg,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: Text(
                  roomTitle.isNotEmpty ? roomTitle[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: isActive ? _statusColor(status) : AppTheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      names.join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

            if (isActive) ...[
              _StatusBadge(status: status),
              const SizedBox(width: 14),
            ] else
              const Padding(
                padding: EdgeInsets.only(right: 14),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.border,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    ),
  );
  }

  Color _statusColor(String status) =>
      status == 'drawing' ? AppTheme.drawing : AppTheme.voting;
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDrawing = status == 'drawing';
    final color = isDrawing ? AppTheme.drawing : AppTheme.voting;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            isDrawing ? '지도 중' : '투표 중',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── FAB 헬퍼 ────────────────────────────────────────────────────
class _Fab extends StatelessWidget {
  final String heroTag;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final String tooltip;

  const _Fab({
    required this.heroTag,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: heroTag,
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      elevation: 2,
      tooltip: tooltip,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: backgroundColor == AppTheme.surface
            ? const BorderSide(color: AppTheme.border)
            : BorderSide.none,
      ),
      child: Icon(icon),
    );
  }
}
