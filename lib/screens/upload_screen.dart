import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:chemeet/app_theme.dart';
import '../services/auth_service.dart';
import '../services/room_service.dart';
import '../widgets/gradient_button.dart';
import 'analyzing_screen.dart';

class UploadScreen extends StatefulWidget {
  final bool isReAnalyze;
  final String? roomId;

  const UploadScreen({
    super.key,
    this.isReAnalyze = false,
    this.roomId,
  });

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _authService     = AuthService();
  final _roomService     = RoomService();
  final _titleController = TextEditingController();
  int   _memberCount     = 2;
  Uint8List? _pickedBytes;
  String? _fileName;
  bool  _loading         = false;

  String get _myUserId => _authService.currentUser?.uid ?? '';
  String _myUserName = '';

  bool get _canSubmit {
    if (_pickedBytes == null) return false;
    if (!widget.isReAnalyze && _titleController.text.trim().isEmpty) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _titleController.addListener(() => setState(() {}));
  }

  Future<void> _loadUserName() async {
    final info = await _authService.getUserInfo(_myUserId);
    if (mounted) setState(() => _myUserName = info?['userName'] ?? '');
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _pickedBytes = result.files.single.bytes;
        _fileName    = result.files.single.name;
      });
    }
  }

  Future<void> _submit() async {
    if (!widget.isReAnalyze && _titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('방 제목을 입력해주세요')),
      );
      return;
    }
    if (_pickedBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('카카오톡 대화 파일을 선택해주세요')),
      );
      return;
    }

    setState(() => _loading = true);

    final String roomId;
    if (widget.isReAnalyze) {
      roomId = widget.roomId!;
    } else {
      roomId = await _roomService.createRoom(
        myUserId:   _myUserId,
        myUserName: _myUserName,
        roomTitle:  _titleController.text.trim(),
        maxMembers: _memberCount,
      );
    }

    final txtContent = utf8.decode(_pickedBytes!, allowMalformed: true);
    if (!mounted) return;
    setState(() => _loading = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AnalyzingScreen(
          roomId:      roomId,
          myUserId:    _myUserId,
          myUserName:  _myUserName,
          maxMembers:  _memberCount,
          txtContent:  txtContent,
          isReAnalyze: widget.isReAnalyze,
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
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.bg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            centerTitle: false,
            titleSpacing: 0,
            leading: IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 28, color: AppTheme.textDark),
              onPressed: () => Navigator.pop(context),
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
            ),
            title: Text(
              widget.isReAnalyze ? '리포트 업데이트' : '새 방 만들기',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textDark, letterSpacing: -0.3),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: CircleForwardButton(
                  enabled: _canSubmit,
                  loading: _loading,
                  onTap: _submit,
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 방 제목 + 인원 (재분석 모드 숨김)
                  if (!widget.isReAnalyze) ...[
                    const Text(
                      '방 제목',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
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
                          horizontal: 16, vertical: 14,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      '인원 설정',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
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
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => setState(() => _memberCount = count),
                              borderRadius: BorderRadius.circular(18),
                              splashFactory: NoSplash.splashFactory,
                              highlightColor: Colors.black.withValues(alpha: 0.06),
                              child: Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  gradient: selected
                                      ? const LinearGradient(
                                          colors: [AppTheme.primary, AppTheme.gradientEnd],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  color: selected ? null : AppTheme.surface,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: selected ? Colors.transparent : AppTheme.border,
                                  ),
                                  boxShadow: selected
                                      ? [BoxShadow(
                                          color: AppTheme.primary.withValues(alpha: 0.3),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        )]
                                      : [],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$count',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: selected ? Colors.white : AppTheme.primary,
                                      ),
                                    ),
                                    Text(
                                      '명',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: selected ? Colors.white70 : AppTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 32),
                  ],

                  // 파일 업로드
                  const Text(
                    '카카오톡 대화 파일',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '카카오톡 → 대화방 → 더보기 → 대화 내용 내보내기 → .txt',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _pickFile,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      decoration: BoxDecoration(
                        gradient: _pickedBytes != null
                            ? LinearGradient(
                                colors: [
                                  AppTheme.primary.withValues(alpha: 0.08),
                                  AppTheme.gradientEnd.withValues(alpha: 0.06),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: _pickedBytes != null ? null : AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _pickedBytes != null
                              ? AppTheme.primary.withValues(alpha: 0.4)
                              : AppTheme.border,
                          width: _pickedBytes != null ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: _pickedBytes != null
                                  ? const LinearGradient(
                                      colors: [AppTheme.primary, AppTheme.gradientEnd],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: _pickedBytes != null ? null : AppTheme.bg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _pickedBytes != null
                                  ? Icons.check_rounded
                                  : Icons.upload_file_rounded,
                              size: 26,
                              color: _pickedBytes != null ? Colors.white : AppTheme.disabled,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _pickedBytes != null ? _fileName! : '탭하여 .txt 파일 선택',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: _pickedBytes != null ? FontWeight.w600 : FontWeight.w400,
                              color: _pickedBytes != null ? AppTheme.primary : AppTheme.textMuted,
                            ),
                          ),
                          if (_pickedBytes != null) ...[
                            const SizedBox(height: 4),
                            const Text(
                              '다시 선택하려면 탭하세요',
                              style: TextStyle(fontSize: 11, color: AppTheme.disabled),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
