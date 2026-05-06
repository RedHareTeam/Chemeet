import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

/// Flask 백엔드의 친밀도 분석 API를 호출하는 서비스
/// 백엔드 미연결 시 더미 데이터를 반환하며, 결과를 Firestore에 저장합니다.
class AnalysisService {
  static const _baseUrl = 'http://10.0.2.2:5000'; // 에뮬레이터 → localhost
  final _db = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> analyze({
    required String roomId,
    required String txtContent,
  }) async {
    Map<String, dynamic> result;

    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/analyze'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'txt_content': txtContent,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        result = {
          'intimacyScore': data['intimacy_score'] ?? 74,
          'keywords':      List<String>.from(data['keywords'] ?? []),
          'partnerName':   data['partner_name'] ?? '상대방',
          'searchQuery':   data['search_query'] ?? '맛집',
          'mood':          List<String>.from(data['mood'] ?? []),
        };
      } else {
        throw Exception('statusCode: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('분석 API 오류 (더미 데이터 사용): $e');

      // ── 백엔드 미연결 시 더미 데이터 반환 ──
      await Future.delayed(const Duration(seconds: 3));
      result = {
        'intimacyScore': 74,
        'keywords':      ['카페', '조용한 곳'],
        'partnerName':   '상대방',
        'searchQuery':   '맛집',
        'mood':          [],
      };
    }

    // ── 분석 결과를 Firestore rooms/{roomId}에 저장 ──
    await _db.collection('rooms').doc(roomId).update({
      'intimacyScore': result['intimacyScore'],
      'keywords':      result['keywords'],
      'partnerName':   result['partnerName'],
      'searchQuery':   result['searchQuery'],
      'mood':          result['mood'],
    });

    return result;
  }
}