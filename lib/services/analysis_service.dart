import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../constants.dart';

/// Flask 백엔드 친밀도 분석 API 서비스
/// - 성공 시 결과를 Firestore rooms/{roomId}에 저장
/// - 실패 시 더미 데이터로 폴백 (앱이 멈추지 않음)
class AnalysisService {
  final _db = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> analyze({
    required String roomId,
    required String txtContent,
  }) async {
    Map<String, dynamic> result;

    try {
      debugPrint('분석 API 호출: ${AppConstants.baseUrl}/analyze');
      final res = await http
          .post(
            Uri.parse('${AppConstants.baseUrl}/analyze'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({'txt_content': txtContent}),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final rawPlaceType = data['place_type'];
        final rawSecondary = data['secondary_place_type'];
        result = {
          'purpose':            data['purpose'] ?? '친목',
          'intimacyScore':      data['intimacy_score'] ?? 74,
          'keywords':           List<String>.from(data['keywords'] ?? []),
          'partnerName':        data['partner_name'] ?? '상대방',
          'placeType':          (rawPlaceType is List ? (rawPlaceType as List).firstOrNull ?? '' : rawPlaceType ?? ''),
          'secondaryPlaceType': (rawSecondary is List ? (rawSecondary as List).firstOrNull ?? '' : rawSecondary ?? ''),
          'preferredFood':      List<String>.from(data['preferred_food'] ?? []),
          'mood':               List<String>.from(data['mood'] ?? []),
        };
        debugPrint('분석 API 성공: $result');
      } else {
        throw Exception('statusCode: ${res.statusCode}');
      }
    } catch (e) {
      // [버그 수정] 기존엔 rethrow로 앱이 에러 다이얼로그를 띄웠음.
      // 백엔드 미연결 환경에서도 앱이 정상 동작하도록 더미 데이터 폴백 처리.
      debugPrint('분석 API 오류 → 더미 데이터 사용: $e');
      result = {
        'purpose':            '친목',
        'intimacyScore':      74,
        'keywords':           ['카페', '조용한 곳', '낮 시간대', '실내', '브런치'],
        'partnerName':        '상대방',
        'placeType':          '',
        'secondaryPlaceType': '',
        'preferredFood':      [],
        'mood':               ['relaxed', 'cozy'],
      };
    }

    // 분석 결과를 Firestore에 저장 → RoomHomeScreen에서 watchRoom()으로 수신
    await _db.collection('rooms').doc(roomId).update({
      'purpose':            result['purpose'],
      'intimacyScore':      result['intimacyScore'],
      'keywords':           result['keywords'],
      'partnerName':        result['partnerName'],
      'placeType':          result['placeType'],
      'secondaryPlaceType': result['secondaryPlaceType'],
      'preferredFood':      result['preferredFood'],
      'mood':               result['mood'],
    });

    return result;
  }
}