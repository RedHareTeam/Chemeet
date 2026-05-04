// 앱 전역 색상/스타일 상수
import 'package:flutter/material.dart';

class AppTheme {
  // Primary — 딥 민트그린
  static const primary    = Color(0xFF5C8374);
  static const primaryBg  = Color(0xFFE8F0ED);

  // Accent — 살몬 코랄
  static const accent     = Color(0xFFE07B5A);
  static const accentBg   = Color(0xFFFAEDE7);

  // Neutral
  static const bg         = Color(0xFFF7F5F2);
  static const surface    = Colors.white;
  static const textDark   = Color(0xFF2B2B2B);
  static const textMuted  = Color(0xFF8A8A8A);
  static const border     = Color(0xFFE5E2DD);

  // 상태별 색상
  static const drawing    = Color(0xFF5C8374); // 지도 중
  static const voting     = Color(0xFFE07B5A); // 투표 중
  static const confirmed  = Color(0xFF4A90D9); // 확정

  static ThemeData get theme => ThemeData(
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(seedColor: primary),
    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    fontFamily: 'Pretendard',
  );
}
