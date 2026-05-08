import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants.dart';
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
  final _roomService   = RoomService();
  final _db            = FirebaseFirestore.instance;
  final _mapKey        = GlobalKey<KakaoMapWebViewState>();

  final List<StreamSubscription> _subs = [];
  Timer? _saveTimer;

  // 내 원
  double _myLat    = 37.5665;
  double _myLng    = 126.9780;
  double _myRadius = 3000;
  bool   _myCircleDrawn = false;

  // 파트너 원 (memberId → {lat, lng, radius, userName})
  final Map<String, Map<String, dynamic>> _partnerCircles = {};

  // 약속 날짜 + 날씨
  DateTime?          _appointmentDate;
  Map<String, dynamic>? _weatherInfo;
  Map<String, dynamic>? _lastRoom;

  bool _isDrawMode    = false;
  bool _isRequesting  = false;
  bool _isNavigating  = false;
  bool _mapReady      = false;
  bool _hasIntersection = false;

  // 파트너 색상 (최대 3명 추가 지원)
  static const List<String> _partnerColors = ['#FF6584', '#FFB347', '#4ECDC4'];

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

  // ── 방 상태 감지 ──────────────────────────────────────────

  void _watchRoom() {
    final sub = _roomService.watchRoom(widget.roomId).listen((room) {
      if (room == null || !mounted || _isNavigating) return;
      _lastRoom = room;
      final status  = room['status'] as String? ?? '';
      final members = List<String>.from(room['members'] ?? []);

      // 약속 날짜 업데이트
      final dateTs = room['appointmentDate'];
      if (dateTs != null) {
        final date = ((dateTs as dynamic).toDate() as DateTime).toLocal();
        if (_appointmentDate != date) {
          setState(() => _appointmentDate = date);
        }
      }

      if (status == 'voting') {
        _isNavigating = true;
        final places = List<Map<String, dynamic>>.from(room['places'] ?? []);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PlaceScreen(
              roomId:   widget.roomId,
              userId:   widget.myUserId,
              userName: widget.myUserName,
              members:  members,
              places:   places,
            ),
          ),
        );
      } else if (status == 'waiting') {
        _isNavigating = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('멤버가 나가 처음으로 돌아갑니다')),
        );
        Navigator.pop(context);
      }
    });
    _subs.add(sub);
  }

  // 약속 날짜의 날씨 조회 (백엔드 forecast 엔드포인트)
  Future<void> _fetchWeather(Map<String, dynamic> room) async {
    final dateTs = room['appointmentDate'];
    if (dateTs == null) return;
    final dateUtc = ((dateTs as dynamic).toDate() as DateTime).toUtc();

    // 만남 구역 중심 = 모든 원 중심의 평균
    double centerLat = _myLat;
    double centerLng = _myLng;
    if (_partnerCircles.isNotEmpty) {
      for (final c in _partnerCircles.values) {
        centerLat += c['lat'] as double;
        centerLng += c['lng'] as double;
      }
      centerLat /= (_partnerCircles.length + 1);
      centerLng /= (_partnerCircles.length + 1);
    }

    try {
      final res = await http.get(
        Uri.parse('${AppConstants.baseUrl}/weather/forecast'
            '?date=${Uri.encodeComponent(dateUtc.toIso8601String())}'
            '&lat=$centerLat&lng=$centerLng'),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() => _weatherInfo = data as Map<String, dynamic>);
      }
    } catch (_) {
      // 날씨 조회 실패 시 날짜만 표시 (무시)
    }
  }

  // ── 파트너 원 구독 ────────────────────────────────────────

  void _watchPartners() {
    for (final memberId in widget.members) {
      if (memberId == widget.myUserId) continue;
      final sub = _circleService
          .watchPartnerCircle(roomId: widget.roomId, partnerId: memberId)
          .listen((data) {
        if (data != null) {
          setState(() {
            _partnerCircles[memberId] = {
              'lat':      (data['lat']    as num).toDouble(),
              'lng':      (data['lng']    as num).toDouble(),
              'radius':   (data['radius'] as num).toDouble(),
              'userName': data['userName'] as String? ?? '상대방',
            };
          });
          _updateIntersectionState();
          if (_mapReady) {
            final colorIdx = widget.members
                    .where((id) => id != widget.myUserId)
                    .toList()
                    .indexOf(memberId) %
                _partnerColors.length;
            _mapKey.currentState?.updatePartnerCircle(
              memberId,
              _partnerCircles[memberId]!['lat'] as double,
              _partnerCircles[memberId]!['lng'] as double,
              _partnerCircles[memberId]!['radius'] as double,
              _partnerCircles[memberId]!['userName'] as String,
              _partnerColors[colorIdx],
            );
          }
        } else {
          // 원이 삭제됨 (다시 그리기 / 다시 만들기)
          setState(() => _partnerCircles.remove(memberId));
          _updateIntersectionState();
          if (_mapReady) _mapKey.currentState?.clearPartnerCircle(memberId);
        }
      });
      _subs.add(sub);
    }
  }

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

  // ── 지도 준비 완료 콜백 ───────────────────────────────────

  Future<void> _onMapReady() async {
    setState(() => _mapReady = true);

    // 내 원 복원
    final myData = await _circleService.getMyCircle(
      roomId: widget.roomId,
      userId: widget.myUserId,
    );
    if (myData != null && mounted) {
      final lat    = (myData['lat']    as num).toDouble();
      final lng    = (myData['lng']    as num).toDouble();
      final radius = (myData['radius'] as num).toDouble();
      setState(() {
        _myLat = lat; _myLng = lng; _myRadius = radius;
        _myCircleDrawn = true;
      });
      _mapKey.currentState?.updateMyCircle(lat, lng, radius, widget.myUserName);
    }

    // 파트너 원 복원
    final partnerIds = widget.members
        .where((id) => id != widget.myUserId)
        .toList();
    for (int i = 0; i < partnerIds.length; i++) {
      final id   = partnerIds[i];
      final data = _partnerCircles[id];
      if (data != null) {
        _mapKey.currentState?.updatePartnerCircle(
          id,
          data['lat']    as double,
          data['lng']    as double,
          data['radius'] as double,
          data['userName'] as String,
          _partnerColors[i % _partnerColors.length],
        );
      }
    }

    _updateIntersectionState();
  }

  // ── 원 그리기 ─────────────────────────────────────────────

  void _onCircleDrawn(double lat, double lng, double radius) {
    setState(() {
      _myLat = lat; _myLng = lng; _myRadius = radius;
      _isDrawMode = false;
      _myCircleDrawn = true;
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
    _updateIntersectionState();
  }

  void _toggleDrawMode() {
    setState(() => _isDrawMode = !_isDrawMode);
    _mapKey.currentState?.setDrawMode(_isDrawMode);
  }

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

  // ── 교집합 체크 ───────────────────────────────────────────

  void _updateIntersectionState() {
    final prev = _hasIntersection;
    setState(() => _hasIntersection = _checkIntersection());
    // 교집합이 처음 생겼을 때 날씨를 올바른 만남 지점으로 재조회
    if (!prev && _hasIntersection && _lastRoom != null && _appointmentDate != null) {
      _fetchWeather(_lastRoom!);
    }
  }

  bool _checkIntersection() {
    if (!_myCircleDrawn) return false;

    final partnerIds = widget.members
        .where((id) => id != widget.myUserId)
        .toList();
    if (_partnerCircles.length < partnerIds.length) return false;

    final circles = <Map<String, double>>[
      {'lat': _myLat, 'lng': _myLng, 'radius': _myRadius},
      ...partnerIds.map((id) => {
        'lat':    _partnerCircles[id]!['lat']    as double,
        'lng':    _partnerCircles[id]!['lng']    as double,
        'radius': _partnerCircles[id]!['radius'] as double,
      }),
    ];

    // 모든 쌍(pair) 교집합 확인
    for (int i = 0; i < circles.length; i++) {
      for (int j = i + 1; j < circles.length; j++) {
        final dist = _haversine(
          circles[i]['lat']!, circles[i]['lng']!,
          circles[j]['lat']!, circles[j]['lng']!,
        );
        if (dist >= circles[i]['radius']! + circles[j]['radius']!) return false;
      }
    }

    // 3명 이상: 공통 교집합 존재 여부 추가 검증
    if (circles.length >= 3) {
      double cLat = 0, cLng = 0, totalW = 0;
      for (int i = 0; i < circles.length; i++) {
        for (int j = i + 1; j < circles.length; j++) {
          final ri = circles[i]['radius']!, rj = circles[j]['radius']!;
          final w  = 1.0 / (ri + rj);
          cLat += (circles[i]['lat']! * rj + circles[j]['lat']! * ri) / (ri + rj) * w;
          cLng += (circles[i]['lng']! * rj + circles[j]['lng']! * ri) / (ri + rj) * w;
          totalW += w;
        }
      }
      cLat /= totalW;
      cLng /= totalW;

      for (final c in circles) {
        if (_haversine(cLat, cLng, c['lat']!, c['lng']!) >= c['radius']!) {
          return false;
        }
      }
    }

    return true;
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
              cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
              sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ── 장소 추천 요청 ────────────────────────────────────────

  Future<void> _requestPlaces() async {
    if (_isRequesting || !_hasIntersection) return;
    setState(() => _isRequesting = true);

    try {
      final roomSnap  = await _db.collection('rooms').doc(widget.roomId).get();
      final roomData  = roomSnap.data() ?? {};
      final searchQuery    = roomData['searchQuery'] ?? '맛집';
      final mood           = List<String>.from(roomData['mood'] ?? []);
      final intimacyScore  = (roomData['intimacyScore'] ?? 50).toDouble();

      // user1 = 나, user2 = 첫 번째 파트너 (현재 백엔드는 2인 지원)
      final partnerId  = widget.members.firstWhere((id) => id != widget.myUserId);
      final partnerData = _partnerCircles[partnerId]!;

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/recommend'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'user1': {'lat': _myLat, 'lng': _myLng, 'radius': _myRadius},
          'user2': {
            'lat':    partnerData['lat'],
            'lng':    partnerData['lng'],
            'radius': partnerData['radius'],
          },
          'search_query':   searchQuery,
          'mood':           mood,
          'intimacy_score': intimacyScore,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 422) {
        // 추천 장소 2개 미만
        if (mounted) {
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('장소가 부족해요'),
              content: const Text(
                  '교집합이 너무 작아 추천 장소가 2곳 미만이에요.\n원을 조금 더 넓게 그려주세요.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('확인',
                      style: TextStyle(color: AppTheme.primary)),
                ),
              ],
            ),
          );
        }
        return;
      }

      if (response.statusCode == 200) {
        final data   = jsonDecode(utf8.decode(response.bodyBytes));
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

  // ── 날짜/날씨 포맷 ────────────────────────────────────────

  String _formatAppointmentDate(DateTime dt) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd  = weekdays[dt.weekday - 1];
    final h   = dt.hour;
    final m   = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? '오전' : '오후';
    final dh   = h % 12 == 0 ? 12 : h % 12;
    return '${dt.month}/${dt.day}($wd) $ampm $dh:$m';
  }

  IconData? _weatherIconData() {
    if (_weatherInfo == null) return null;
    return switch (_weatherInfo!['condition']) {
      'clear'   => Icons.wb_sunny,
      'clouds'  => Icons.cloud,
      'rain'    => Icons.water_drop,
      'snow'    => Icons.ac_unit,
      'thunder' => Icons.thunderstorm,
      _         => null,
    };
  }

  // ── 빌드 ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('구역 설정',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Stack(
        children: [
          KakaoMapWebView(
            key: _mapKey,
            kakaoApiKey: dotenv.env['KAKAO_JS_KEY'] ?? '',
            onCenterChanged: (lat, lng) {},
            onCircleDrawn: _onCircleDrawn,
            onMapReady: _onMapReady,
          ),

          // ── 상단 안내 텍스트 ──
          Positioned(
            top: 16, left: 16, right: 16,
            child: Column(
              children: [
                // 날짜/날씨 배너
                if (_appointmentDate != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 6),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.event, size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          _formatAppointmentDate(_appointmentDate!),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        if (_weatherIconData() != null) ...[
                          const SizedBox(width: 8),
                          Icon(_weatherIconData()!, size: 15, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            '${_weatherInfo!['temp']}°',
                            style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ],
                    ),
                  ),

                // 드로우 모드 안내
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isDrawMode ? Icons.gesture : Icons.open_with,
                        size: 16,
                        color: _isDrawMode
                            ? AppTheme.accent
                            : AppTheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isDrawMode
                            ? '손가락으로 원을 그려보세요!'
                            : '이동 모드  ·  반경 ${(_myRadius / 1000).toStringAsFixed(1)}km',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _isDrawMode
                              ? AppTheme.accent
                              : AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── 하단 버튼 ──
          Positioned(
            bottom: bottomPadding + 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 교집합 미충족 안내
                if (!_hasIntersection && _myCircleDrawn)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      _partnerCircles.length <
                              widget.members.length - 1
                          ? '모든 멤버가 원을 그려야 장소 추천이 가능해요'
                          : '원이 겹치지 않아요. 원을 더 넓게 그려주세요',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.accent),
                    ),
                  ),

                Row(
                  children: [
                    FloatingActionButton(
                      heroTag: 'drawToggle',
                      onPressed: _toggleDrawMode,
                      backgroundColor:
                          _isDrawMode ? AppTheme.accent : AppTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      child: Icon(
                          _isDrawMode ? Icons.open_with : Icons.gesture),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_isRequesting || !_hasIntersection)
                            ? null
                            : _requestPlaces,
                        icon: _isRequesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.search_rounded),
                        label: Text(
                            _isRequesting ? '검색 중...' : '장소 추천 받기'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _hasIntersection
                              ? AppTheme.primary
                              : AppTheme.disabled,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppTheme.disabled,
                          disabledForegroundColor: Colors.white70,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
