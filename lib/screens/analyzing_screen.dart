import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chemeet/app_theme.dart';
import '../services/analysis_service.dart';
import 'room_home_screen.dart';

class AnalyzingScreen extends StatefulWidget {
  final String roomId;
  final String myUserId;
  final String myUserName;
  final int maxMembers;
  final String txtContent;

  /// true 이면 재분석 모드: 방 생성 없이 기존 roomId 데이터만 업데이트
  final bool isReAnalyze;

  const AnalyzingScreen({
    super.key,
    required this.roomId,
    required this.myUserId,
    required this.myUserName,
    required this.maxMembers,
    required this.txtContent,
    this.isReAnalyze = false,
  });

  @override
  State<AnalyzingScreen> createState() => _AnalyzingScreenState();
}

class _AnalyzingScreenState extends State<AnalyzingScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnim;

  int _stepIndex = 0;
  final List<String> _steps = [
    '대화 파일 파싱 중...',
    '감성 분석 중...',
    '친밀도 점수 계산 중...',
    '취향 키워드 추출 중...',
    '분석 완료!',
  ];

  Timer? _stepTimer;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..forward();

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _stepTimer = Timer.periodic(const Duration(milliseconds: 900), (t) {
      if (_stepIndex < _steps.length - 1) {
        setState(() => _stepIndex++);
      } else {
        t.cancel();
        _startAnalysis();
      }
    });
  }

  Future<void> _startAnalysis() async {
    try {
      await AnalysisService().analyze(
        roomId: widget.roomId,
        txtContent: widget.txtContent,
      );
      if (!mounted) return;

      if (widget.isReAnalyze) {
        Navigator.pop(context); // RoomHomeScreen으로 복귀
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RoomHomeScreen(
              roomId:     widget.roomId,
              myUserId:   widget.myUserId,
              myUserName: widget.myUserName,
              maxMembers: widget.maxMembers,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('분석 오류'),
          content: const Text('분석 중 오류가 발생했어요.\n파일을 확인하고 다시 시도해주세요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인', style: TextStyle(color: AppTheme.primary)),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context); // UploadScreen으로 복귀
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    _stepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    child: Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: Center(
                          child: Icon(Icons.chat_bubble_outline,
                              size: 36, color: AppTheme.primary),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                Text(
                  widget.isReAnalyze ? '리포트를 업데이트하고 있어요' : '대화를 분석하고 있어요',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 12),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Text(
                    _steps[_stepIndex],
                    key: ValueKey(_stepIndex),
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ),

                const SizedBox(height: 32),

                AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, _) {
                    return Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _progressController.value,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_progressController.value * 100).toInt()}%',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 40),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_steps.length, (i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: i == _stepIndex ? 20 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i <= _stepIndex
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
