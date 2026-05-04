import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:chemeet/app_theme.dart';
import '../services/auth_service.dart';
import '../services/room_service.dart';
import 'analyzing_screen.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _authService      = AuthService();
  final _roomService      = RoomService();
  final _titleController  = TextEditingController();
  int   _memberCount      = 2;
  File? _pickedFile;
  String? _fileName;
  bool  _loading          = false;

  String get _myUserId => _authService.currentUser!.uid;
  String _myUserName = '';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final info = await _authService.getUserInfo(_myUserId);
    setState(() => _myUserName = info?['userName'] ?? '');
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pickedFile = File(result.files.single.path!);
        _fileName   = result.files.single.name;
      });
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('방 제목을 입력해주세요')),
      );
      return;
    }
    if (_pickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('카카오톡 대화 파일을 선택해주세요')),
      );
      return;
    }

    setState(() => _loading = true);

    final roomId = await _roomService.createRoom(
      myUserId:   _myUserId,
      myUserName: _myUserName,
      roomTitle:  _titleController.text.trim(),
      maxMembers: _memberCount,
    );

    final txtContent = await _pickedFile!.readAsString();

    if (!mounted) return;
    setState(() => _loading = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AnalyzingScreen(
          roomId:     roomId,
          myUserId:   _myUserId,
          myUserName: _myUserName,
          maxMembers: _memberCount,
          txtContent: txtContent,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('새 방 만들기'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 방 제목 ──────────────────────────────
            Text(
              '방 제목',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── 인원 설정 ─────────────────────────────
            Text(
              '인원 설정',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '본인 포함 총 인원 수를 선택하세요',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 12),
            Row(
              children: List.generate(4, (i) {
                final count    = i + 2;
                final selected = _memberCount == count;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _memberCount = count),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: selected ? AppTheme.primary : AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? AppTheme.primary : AppTheme.border,
                          width: selected ? 2 : 1,
                        ),
                        boxShadow: selected
                            ? [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                            : [],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: selected ? Colors.white : AppTheme.primary,
                            ),
                          ),
                          Text(
                            '명',
                            style: TextStyle(
                              fontSize: 11,
                              color: selected
                                  ? Colors.white70
                                  : AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 28),

            // ── 파일 업로드 ───────────────────────────
            Text(
              '카카오톡 대화 파일',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '카카오톡 대화방 → 더보기 → 대화 내용 내보내기 → txt 파일',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _pickFile,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: _pickedFile != null
                      ? AppTheme.primaryBg
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _pickedFile != null
                        ? AppTheme.primary
                        : AppTheme.border,
                    width: _pickedFile != null ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _pickedFile != null
                          ? Icons.check_circle
                          : Icons.upload_file,
                      size: 36,
                      color: _pickedFile != null
                          ? AppTheme.primary
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _pickedFile != null ? _fileName! : '탭하여 .txt 파일 선택',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _pickedFile != null
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: _pickedFile != null
                            ? AppTheme.primary
                            : Colors.grey.shade500,
                      ),
                    ),
                    if (_pickedFile != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '파일을 다시 선택하려면 탭하세요',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade400),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 36),

            // ── 제출 버튼 ─────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
                    : const Text(
                  '분석 시작',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}