import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../services/analysis_service.dart';
import '../widgets/app_dialog.dart';
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _startAnalysis();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _startAnalysis() async {
    try {
      await AnalysisService().analyze(
        roomId: widget.roomId,
        txtContent: widget.txtContent,
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
        builder: (_) => AppDialog(
          title: '분석 오류',
          content: '분석 중 오류가 발생했어요.\n파일을 확인하고 다시 시도해주세요.',
          icon: Icons.error_outline_rounded,
          actions: [
            DialogAction(
              label: '확인',
              primary: true,
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.intimacyTop, AppTheme.gradientEnd, Color(0xFFB08EFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) => Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                        angle: _ctrl.value * 2 * pi,
                        child: CustomPaint(
                          size: const Size(120, 120),
                          painter: _SpinnerPainter(),
                        ),
                      ),
                      ClipOval(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 28,
                              color: AppTheme.intimacyTop,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 36),
              Text(
                widget.isReAnalyze ? '리포트를 업데이트하고 있어요' : '대화를 분석하고 있어요',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const sweepAngle = 2 * pi * 0.75;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.9),
        ],
        endAngle: sweepAngle,
      ).createShader(rect);

    canvas.drawArc(rect, 0, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
