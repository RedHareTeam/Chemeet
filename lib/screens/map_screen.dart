import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/kakao_map_webview.dart';
import '../services/circle_service.dart';
import '../services/room_service.dart';
import 'place_screen.dart';
import 'package:chemeet/app_theme.dart';

class MapScreen extends StatefulWidget {
  final String roomId;
  final String myUserId;
  final String myUserName;
  final List<String> members;

  const MapScreen({
    super.key,
    required this.roomId,
    required this.myUserId,
    required this.myUserName,
    required this.members,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _circleService = CircleService();
  final _roomService = RoomService();
  final _db = FirebaseFirestore.instance;
  final _mapKey = GlobalKey<KakaoMapWebViewState>();

  final List<StreamSubscription> _subs = [];
  Timer? _saveTimer;

  double _myLat = 37.5665;
  double _myLng = 126.9780;
  double _myRadius = 3000;

  double? _partnerLat;
  double? _partnerLng;
  double? _partnerRadius;

  bool _isDrawMode = false;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    _watchRoom();
    _watchPartners();
    _watchMessages();
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _saveTimer?.cancel();
    super.dispose();
  }

  // 방 상태 감지 — voting이면 PlaceScreen으로 이동
  void _watchRoom() {
    final sub = _roomService.watchRoom(widget.roomId).listen((room) {
      if (room == null || !mounted) return;
      if (room['status'] == 'voting') {
        final places = List<Map<String, dynamic>>.from(room['places'] ?? []);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PlaceScreen(
              roomId: widget.roomId,
              userId: widget.myUserId,
              userName: widget.myUserName,
              members: widget.members,
              places: places,
            ),
          ),
        );
      }
    });
    _subs.add(sub);
  }

  // 파트너 원 실시간 구독
  void _watchPartners() {
    for (final memberId in widget.members) {
      if (memberId == widget.myUserId) continue;
      final sub = _circleService
          .watchPartnerCircle(roomId: widget.roomId, partnerId: memberId)
          .listen((data) {
        if (data != null) {
          setState(() {
            _partnerLat = (data['lat'] as num).toDouble();
            _partnerLng = (data['lng'] as num).toDouble();
            _partnerRadius = (data['radius'] as num).toDouble();
          });
          _mapKey.currentState?.updatePartnerCircle(
            _partnerLat!,
            _partnerLng!,
            _partnerRadius!,
            data['userName'] ?? '상대방',
          );
        }
      });
      _subs.add(sub);
    }
  }

  // 메시지 구독 — 상대방 메시지만 WebView에 전달
  void _watchMessages() {
    final sub = _circleService
        .watchMessages(roomId: widget.roomId)
        .listen((messages) {
      if (messages.isEmpty) return;
      final last = messages.last;
      if (last['userId'] != widget.myUserId) {
        _mapKey.currentState?.addMessage(
          last['userId'], last['userName'], last['message'],
        );
      }
    });
    _subs.add(sub);
  }

  // 원 그리기 완료 콜백
  void _onCircleDrawn(double lat, double lng, double radius) {
    setState(() {
      _myLat = lat; _myLng = lng; _myRadius = radius; _isDrawMode = false;
    });
    _mapKey.currentState?.setDrawMode(false);
    _mapKey.currentState?.updateMyCircle(lat, lng, radius, widget.myUserName);

    final msg = '${widget.myUserName}이(가) 구역을 설정했어요';
    _circleService.sendMessage(
      roomId: widget.roomId,
      userId: widget.myUserId,
      userName: widget.myUserName,
      message: msg,
    );
    _mapKey.currentState?.addMessage(widget.myUserId, widget.myUserName, msg);
    _saveDebounced();
  }

  void _toggleDrawMode() {
    setState(() => _isDrawMode = !_isDrawMode);
    _mapKey.currentState?.setDrawMode(_isDrawMode);
  }

  // 500ms 디바운스로 Firestore 저장
  void _saveDebounced() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      _circleService.saveMyCircle(
        roomId: widget.roomId, userId: widget.myUserId,
        userName: widget.myUserName,
        lat: _myLat, lng: _myLng, radius: _myRadius,
      );
    });
  }

  // 장소 추천 요청 — 백엔드 /recommend 호출
  Future<void> _requestPlaces() async {
    if (_isRequesting) return;

    if (_partnerLat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상대방이 아직 구역을 설정하지 않았어요')),
      );
      return;
    }

    setState(() => _isRequesting = true);

    try {
      // Firestore에서 분석 결과 읽기
      final roomSnap = await _db.collection('rooms').doc(widget.roomId).get();
      final roomData = roomSnap.data() ?? {};
      final searchQuery = roomData['searchQuery'] ?? '맛집';
      final mood = List<String>.from(roomData['mood'] ?? []);
      final intimacyScore = (roomData['intimacyScore'] ?? 50).toDouble();

      final response = await http.post(
        Uri.parse('http://10.0.2.2:5000/recommend'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'user1': {'lat': _myLat, 'lng': _myLng, 'radius': _myRadius},
          'user2': {'lat': _partnerLat, 'lng': _partnerLng, 'radius': _partnerRadius},
          'search_query': searchQuery,
          'mood': mood,
          'intimacy_score': intimacyScore,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final places = List<Map<String, dynamic>>.from(data['places'] ?? []);
        await _circleService.savePlaces(widget.roomId, places);
      } else {
        throw Exception('statusCode: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('장소 추천 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('장소 추천 중 오류가 발생했어요')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('구역 설정', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Stack(
        children: [
          // 지도
          KakaoMapWebView(
            key: _mapKey,
            kakaoApiKey: dotenv.env['KAKAO_JS_KEY'] ?? '',
            onCenterChanged: (lat, lng) {},
            onCircleDrawn: _onCircleDrawn,
            partnerCircle: null,
          ),

          // 상단 안내 텍스트
          Positioned(
            top: 16, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isDrawMode ? Icons.gesture : Icons.open_with,
                    size: 16,
                    color: _isDrawMode ? AppTheme.accent : AppTheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isDrawMode
                        ? '손가락으로 원을 그려보세요!'
                        : '이동 모드  ·  반경 ${(_myRadius / 1000).toStringAsFixed(1)}km',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _isDrawMode ? AppTheme.accent : AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 하단 버튼 영역
          Positioned(
            bottom: bottomPadding + 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // 그리기/이동 모드 전환 FAB
                FloatingActionButton(
                  heroTag: 'drawToggle',
                  onPressed: _toggleDrawMode,
                  backgroundColor: _isDrawMode ? AppTheme.accent : AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  child: Icon(_isDrawMode ? Icons.open_with : Icons.gesture),
                ),
                const SizedBox(width: 12),
                // 장소 추천 받기 버튼
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isRequesting ? null : _requestPlaces,
                    icon: _isRequesting
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.search_rounded),
                    label: Text(_isRequesting ? '검색 중...' : '장소 추천 받기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}