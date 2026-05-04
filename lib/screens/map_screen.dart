import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../widgets/kakao_map_webview.dart';
import '../services/circle_service.dart';
import '../services/place_service.dart';
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
  final _mapKey = GlobalKey<KakaoMapWebViewState>();

  final List<StreamSubscription> _subs = [];
  Timer? _saveTimer;

  double _myLat = 37.5665;
  double _myLng = 126.9780;
  double _myRadius = 3000;
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
          _mapKey.currentState?.updatePartnerCircle(
            (data['lat'] as num).toDouble(),
            (data['lng'] as num).toDouble(),
            (data['radius'] as num).toDouble(),
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

  // 장소 추천 요청
  Future<void> _requestPlaces() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);
    try {
      final places = await PlaceService().searchNearby(lat: _myLat, lng: _myLng);
      await _circleService.savePlaces(widget.roomId, places);
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
