import 'dart:async';
import 'dart:ui';
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
  late AnimationController _rotateController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnim;
  late Animation<double> _rotateAnim;

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
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _progressController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_steps.length - 1) * 900),
    );

    _pulseAnim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotateAnim = Tween<double>(begin: 0, end: 1).animate(_rotateController);

    _progressController.animateTo(0.9);

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
      await _progressController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 300),
      );
      if (!mounted) return;

      if (widget.isReAnalyze) {
        Navigator.pop(context);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _progressController.dispose();
    _stepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFF9BDE), Color(0xFFFF7BAC), Color(0xFFB08EFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 펄스 + 회전 아이콘
                  ScaleTransition(
                    scale: _pulseAnim,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 회전 링
                        RotationTransition(
                          turns: _rotateAnim,
                          child: Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 2,
                              ),
                            ),
                            child: CustomPaint(painter: _ArcPainter()),
                          ),
                        ),
                        // 외곽 글로우
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        // 중앙 아이콘
                        ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 34,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 44),

                  Text(
                    widget.isReAnalyze ? '리포트를 업데이트하고 있어요' : '대화를 분석하고 있어요',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.3),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Text(
                      _steps[_stepIndex],
                      key: ValueKey(_stepIndex),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // 진행 바 (글라스)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: AnimatedBuilder(
                          animation: _progressController,
                          builder: (_, __) => Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: _progressController.value,
                                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                                  minHeight: 8,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${(_progressController.value * 100).toInt()}%',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 스텝 인디케이터
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_steps.length, (i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: i == _stepIndex ? 24 : 8,
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
      ),
    );
  }
}

// 회전 아크 그리기
class _ArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawArc(rect, -1.2, 2.4, false, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
