import 'package:chemeet/screens/room_home_screen.dart';
import 'package:chemeet/screens/upload_screen.dart';
import 'package:flutter/material.dart';
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

  Future<void> _loadUserName() async {
    final info = await _authService.getUserInfo(_myUserId);
    setState(() => _myUserName = info?['userName'] ?? '');
  }

  // 방 만들기 — UploadScreen(대화 분석)으로 이동
  Future<void> _createRoom() async {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadScreen()));
  }

  // 코드 입장 다이얼로그
  Future<void> _joinRoom() async {
    _codeController.clear();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('초대 코드 입력'),
        content: TextField(
          controller: _codeController,
          decoration: const InputDecoration(hintText: '6자리 코드 입력'),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              final code = _codeController.text.trim().toUpperCase();
              final roomId = await _roomService.joinRoom(
                inviteCode: code,
                myUserId: _myUserId,
                myUserName: _myUserName,
              );
              if (!mounted) return;
              Navigator.pop(context);
              if (roomId != null) {
                final room = await _roomService.getRoom(roomId);
                if (room != null && mounted) _enterRoom(roomId, room);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('유효하지 않은 코드예요')),
                );
              }
            },
            child: const Text('입장', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  // 방 입장
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
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Chemeet', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _roomStream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('오류: ${snap.error}'));
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final rooms = snap.data ?? [];

          if (rooms.isEmpty) return _buildEmpty();

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: rooms.length,
            itemBuilder: (context, index) => _RoomCard(
              room: rooms[index],
              myUserId: _myUserId,
              onTap: () => _enterRoom(rooms[index]['roomId'], rooms[index]),
            ),
          );
        },
      ),
      // 방 만들기(+) / 코드 입장 아이콘 버튼
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'join',
            onPressed: _joinRoom,
            backgroundColor: AppTheme.surface,
            foregroundColor: AppTheme.primary,
            elevation: 2,
            tooltip: '코드로 입장',
            child: const Icon(Icons.login_rounded),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'create',
            onPressed: _createRoom,
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            elevation: 2,
            tooltip: '방 만들기',
            child: const Icon(Icons.add_rounded),
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
          Icon(Icons.people_outline, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('아직 참여 중인 방이 없어요',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 15)),
          const SizedBox(height: 8),
          Text('오른쪽 아래 + 버튼으로 첫 방을 만들어보세요',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── 방 카드 위젯 ──
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
    final roomTitle = room['roomTitle'] ?? '제목 없음';
    final memberNames = Map<String, dynamic>.from(room['memberNames'] ?? {});
    // 참가자 닉네임 나열 (나 먼저)
    final names = memberNames.entries
        .map((e) => e.value.toString())
        .toList();
    final status = room['status'] ?? 'idle';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 방 이니셜 아바타
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppTheme.primaryBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  roomTitle.isNotEmpty ? roomTitle[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 방 이름
                  Text(
                    roomTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 참가자 닉네임
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
            // 상태 뱃지
            if (status == 'drawing' || status == 'voting')
              _StatusBadge(status: status),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDrawing = status == 'drawing';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDrawing ? AppTheme.primaryBg : AppTheme.accentBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isDrawing ? '지도' : '투표 중',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDrawing ? AppTheme.primary : AppTheme.accent,
        ),
      ),
    );
  }
}
