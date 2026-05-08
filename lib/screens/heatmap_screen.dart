import 'dart:async';
import 'dart:convert';
import 'package:chemeet/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/history_service.dart';

// ── 데이터 모델 ────────────────────────────────────────────────────────
class _PlaceGroup {
  final String name;
  final double lat;
  final double lng;
  final String address;
  final String category;
  final List<Map<String, dynamic>> historyEntries;

  _PlaceGroup({
    required this.name,
    required this.lat,
    required this.lng,
    required this.address,
    required this.category,
    required this.historyEntries,
  });

  int get count => historyEntries.length;

  Map<String, dynamic> toJson() => {
        'name':    name,
        'lat':     lat,
        'lng':     lng,
        'address': address,
        'count':   count,
      };
}

// ── 히트맵 화면 ────────────────────────────────────────────────────────
class HeatmapScreen extends StatefulWidget {
  final String roomId;
  final String myUserId;
  final String myUserName;

  const HeatmapScreen({
    super.key,
    required this.roomId,
    required this.myUserId,
    required this.myUserName,
  });

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final _historyService = HistoryService();
  final _mapKey         = GlobalKey<_HeatmapMapViewState>();

  StreamSubscription?          _historySub;
  List<_PlaceGroup>            _places     = [];
  List<Map<String, dynamic>>   _rawHistory = [];
  bool                         _mapReady   = false;

  @override
  void initState() {
    super.initState();
    _historySub =
        _historyService.watchHistory(widget.roomId).listen((history) {
      final groups = _groupByPlace(history);
      setState(() {
        _places     = groups;
        _rawHistory = history;
      });
      if (_mapReady) _mapKey.currentState?.updateData(groups);
    });
  }

  @override
  void dispose() {
    _historySub?.cancel();
    super.dispose();
  }

  List<_PlaceGroup> _groupByPlace(List<Map<String, dynamic>> history) {
    final Map<String, _PlaceGroup> groups = {};
    for (final h in history) {
      final place = Map<String, dynamic>.from(h['confirmedPlace'] as Map? ?? {});
      final name  = (place['name'] as String?) ?? '';
      final lat   = (place['lat']  as num?)?.toDouble() ?? 0;
      final lng   = (place['lng']  as num?)?.toDouble() ?? 0;
      if (name.isEmpty || (lat == 0 && lng == 0)) continue;

      if (groups.containsKey(name)) {
        groups[name]!.historyEntries.add(h);
      } else {
        groups[name] = _PlaceGroup(
          name:     name,
          lat:      lat,
          lng:      lng,
          address:  (place['address']  as String?) ?? '',
          category: (place['category'] as String?) ?? '',
          historyEntries: [h],
        );
      }
    }
    return groups.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  void _onMapReady() {
    setState(() => _mapReady = true);
    _mapKey.currentState?.updateData(_places);
  }

  void _onPinTapped(String placeName) {
    final group = _places.firstWhere(
      (p) => p.name == placeName,
      orElse: () =>
          _PlaceGroup(name: '', lat: 0, lng: 0, address: '', category: '', historyEntries: []),
    );
    if (group.name.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlaceDetailSheet(
        roomId:         widget.roomId,
        myUserId:       widget.myUserId,
        myUserName:     widget.myUserName,
        initialGroup:   group,
        historyService: _historyService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('방문 히스토리'),
        actions: [
          if (_rawHistory.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.show_chart_rounded),
              tooltip: '친밀도 변화',
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _IntimacyGraphSheet(history: _rawHistory),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          _HeatmapMapView(
            key:         _mapKey,
            kakaoApiKey: dotenv.env['KAKAO_JS_KEY'] ?? '',
            onMapReady:  _onMapReady,
            onPinTapped: _onPinTapped,
          ),

          // 방문 장소 없을 때 안내
          if (_places.isEmpty && _mapReady)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12)
                  ],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.place_outlined, size: 40, color: AppTheme.border),
                    SizedBox(height: 12),
                    Text(
                      '아직 방문한 장소가 없어요',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '약속을 확정하면 지도에 기록돼요',
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ),

          // 범례
          if (_places.isNotEmpty)
            Positioned(
              bottom: 20 + MediaQuery.of(context).padding.bottom,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('방문 횟수',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    _legendRow(const Color(0xFF818CF8), '1회'),
                    const SizedBox(height: 4),
                    _legendRow(const Color(0xFF7C3AED), '2-3회'),
                    const SizedBox(height: 4),
                    _legendRow(AppTheme.accent, '4회+'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textDark)),
      ],
    );
  }
}

// ── 히트맵 WebView ──────────────────────────────────────────────────────
class _HeatmapMapView extends StatefulWidget {
  final String kakaoApiKey;
  final VoidCallback onMapReady;
  final void Function(String placeName) onPinTapped;

  const _HeatmapMapView({
    super.key,
    required this.kakaoApiKey,
    required this.onMapReady,
    required this.onPinTapped,
  });

  @override
  State<_HeatmapMapView> createState() => _HeatmapMapViewState();
}

class _HeatmapMapViewState extends State<_HeatmapMapView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'MapReadyChannel',
        onMessageReceived: (_) => widget.onMapReady(),
      )
      ..addJavaScriptChannel(
        'PinTappedChannel',
        onMessageReceived: (msg) => widget.onPinTapped(msg.message),
      )
      ..addJavaScriptChannel(
        'Console',
        onMessageReceived: (msg) => debugPrint('HeatmapJS: ${msg.message}'),
      )
      ..loadHtmlString(_buildHtml());
  }

  void updateData(List<_PlaceGroup> places) {
    final json    = jsonEncode(places.map((p) => p.toJson()).toList());
    final encoded = Uri.encodeComponent(json);
    _controller.runJavaScript(
        'updateMapData(JSON.parse(decodeURIComponent("$encoded")))');
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);

  String _buildHtml() => '''
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;700&display=swap" rel="stylesheet">
  <style>
    * { margin:0; padding:0; box-sizing:border-box; -webkit-user-select:none; user-select:none; font-family:"Noto Sans KR",-apple-system,"Apple SD Gothic Neo",system-ui,sans-serif; }
    body { width:100vw; height:100vh; overflow:hidden; }
    #map    { width:100%; height:100%; }
    #canvas { position:absolute; top:0; left:0; width:100%; height:100%; pointer-events:none; z-index:2; }
    #pins   { position:absolute; top:0; left:0; width:100%; height:100%; pointer-events:none; z-index:4; }
    .pin {
      position:absolute; pointer-events:auto; cursor:pointer;
      display:flex; flex-direction:column; align-items:center;
      transform:translate(-50%,-100%);
    }
    .pin-circle {
      width:44px; height:44px; border-radius:50%;
      display:flex; align-items:center; justify-content:center; flex-direction:column;
      color:white; box-shadow:0 3px 10px rgba(0,0,0,0.25); border:2.5px solid white;
    }
    .pin-count { font-size:15px; font-weight:700; line-height:1; }
    .pin-unit  { font-size:8px; opacity:0.85; margin-top:1px; }
    .pin-tail  { width:0; height:0; border-left:6px solid transparent; border-right:6px solid transparent; margin-top:-1px; }
    .pin-label {
      background:rgba(28,28,46,0.72); color:white; font-size:10px;
      padding:2px 7px; border-radius:6px; margin-top:4px;
      max-width:96px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;
    }
    .cpin {
      position:absolute; pointer-events:auto; cursor:pointer;
      display:flex; flex-direction:column; align-items:center;
      transform:translate(-50%,-50%);
    }
    .cpin-circle {
      border-radius:50%; display:flex; align-items:center; justify-content:center; flex-direction:column;
      color:white; border:3px solid white;
      box-shadow:0 3px 14px rgba(0,0,0,0.22);
    }
    .cpin-num   { font-weight:800; line-height:1; }
    .cpin-sub   { font-size:9px; opacity:0.85; }
    .cpin-badge {
      background:rgba(28,28,46,0.72); color:white; font-size:10px;
      padding:2px 8px; border-radius:6px; margin-top:5px; white-space:nowrap;
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <div id="pins"></div>
  <canvas id="canvas"></canvas>

  <script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=${widget.kakaoApiKey}"></script>
  <script>
    var map;
    var canvas   = document.getElementById('canvas');
    var ctx      = canvas.getContext('2d');
    var pinsDiv  = document.getElementById('pins');
    var currentData  = [];
    var clusterTimer = null;
    var pinch        = null;   // { dist, cx, cy }

    kakao.maps.load(function() {
      canvas.width  = window.innerWidth;
      canvas.height = window.innerHeight;

      map = new kakao.maps.Map(document.getElementById('map'), {
        center: new kakao.maps.LatLng(37.5665, 126.9780),
        level: 8
      });

      // 팬: 히트맵 + 핀 위치 실시간 업데이트
      kakao.maps.event.addListener(map, 'center_changed', function() {
        redrawHeatmap();
        updatePinPositions();
      });

      // 줌 완료: transform 리셋 후 재계산
      kakao.maps.event.addListener(map, 'zoom_changed', function() {
        pinch = null;
        resetTransform();
        redrawHeatmap();
        if (clusterTimer) clearTimeout(clusterTimer);
        clusterTimer = setTimeout(function() { renderPins(); redrawHeatmap(); }, 120);
      });

      var mapEl = document.getElementById('map');

      // 핀치 시작: 두 손가락 거리 기록
      mapEl.addEventListener('touchstart', function(e) {
        if (e.touches.length === 2) {
          pinch = {
            dist: tdist(e.touches[0], e.touches[1]),
            cx:   (e.touches[0].clientX + e.touches[1].clientX) / 2,
            cy:   (e.touches[0].clientY + e.touches[1].clientY) / 2
          };
        }
      }, {passive: true});

      // 핀치 이동: 스케일 비율로 canvas + pins CSS transform 적용
      mapEl.addEventListener('touchmove', function(e) {
        if (e.touches.length === 2 && pinch) {
          var s = tdist(e.touches[0], e.touches[1]) / pinch.dist;
          var t = 'scale(' + s + ')';
          var o = pinch.cx + 'px ' + pinch.cy + 'px';
          canvas.style.transform       = t;
          canvas.style.transformOrigin = o;
          pinsDiv.style.transform       = t;
          pinsDiv.style.transformOrigin = o;
        }
      }, {passive: true});

      MapReadyChannel.postMessage('ready');
    });

    function tdist(a, b) {
      var dx = a.clientX - b.clientX, dy = a.clientY - b.clientY;
      return Math.sqrt(dx*dx + dy*dy);
    }
    function resetTransform() {
      canvas.style.transform = pinsDiv.style.transform = '';
      canvas.style.transformOrigin = pinsDiv.style.transformOrigin = '';
    }

    // ── 데이터 주입 ────────────────────────────────────────────────
    function updateMapData(data) {
      currentData = data || [];
      clearPins();
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      if (!currentData.length) return;

      if (currentData.length === 1) {
        map.setCenter(new kakao.maps.LatLng(currentData[0].lat, currentData[0].lng));
        map.setLevel(4);
      } else {
        var b = new kakao.maps.LatLngBounds();
        currentData.forEach(function(p) { b.extend(new kakao.maps.LatLng(p.lat, p.lng)); });
        map.setBounds(b, 80);
      }
      redrawHeatmap();
      renderPins();
    }

    function clearPins() {
      while (pinsDiv.firstChild) pinsDiv.removeChild(pinsDiv.firstChild);
      window._clusterData = [];
    }

    // 팬할 때 이미 렌더된 핀의 left/top만 갱신 (DOM 재생성 없이)
    function updatePinPositions() {
      if (!currentData.length) return;
      var proj = map.getProjection();
      var els  = pinsDiv.querySelectorAll('[data-lat]');
      els.forEach(function(el) {
        var pt = proj.containerPointFromCoords(
          new kakao.maps.LatLng(parseFloat(el.dataset.lat), parseFloat(el.dataset.lng))
        );
        el.style.left = pt.x + 'px';
        el.style.top  = pt.y + 'px';
      });
    }

    // ── 히트맵 (캔버스) ──────────────────────────────────────────
    // 핀과 동일한 클러스터 반경으로 근접 장소를 묶고,
    // 합산 횟수 하나에 대한 색·크기만 렌더링 (색 혼합 방지)
    function redrawHeatmap() {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      if (!currentData.length) return;
      var proj     = map.getProjection();
      var level    = map.getLevel();
      var clusterR = Math.max(35, level * 9);

      var pts = currentData.map(function(p) {
        var pt = proj.containerPointFromCoords(new kakao.maps.LatLng(p.lat, p.lng));
        return { x: pt.x, y: pt.y };
      });

      var used  = new Array(pts.length).fill(false);
      var spots = [];
      for (var a = 0; a < pts.length; a++) {
        if (used[a]) continue;
        var cluster = [a];
        used[a] = true;
        for (var b = a + 1; b < pts.length; b++) {
          if (used[b]) continue;
          var dx = pts[a].x - pts[b].x, dy = pts[a].y - pts[b].y;
          if (Math.sqrt(dx*dx + dy*dy) < clusterR) { cluster.push(b); used[b] = true; }
        }
        var total = cluster.reduce(function(s,i) { return s + currentData[i].count; }, 0);
        var cLat  = cluster.reduce(function(s,i) { return s + currentData[i].lat;   }, 0) / cluster.length;
        var cLng  = cluster.reduce(function(s,i) { return s + currentData[i].lng;   }, 0) / cluster.length;
        var cPt   = proj.containerPointFromCoords(new kakao.maps.LatLng(cLat, cLng));
        spots.push({ x: cPt.x, y: cPt.y, count: total });
      }

      // 낮은 횟수부터 그려 높은 횟수가 위에 오도록
      spots.sort(function(a, b) { return a.count - b.count; });

      spots.forEach(function(s) {
        var r, alpha;
        if      (s.count >= 4) { r = 110; alpha = 0.50; }
        else if (s.count >= 2) { r =  85; alpha = 0.40; }
        else                   { r =  65; alpha = 0.28; }
        var rgb = heatRgb(s.count);
        var g = ctx.createRadialGradient(s.x, s.y, 0, s.x, s.y, r);
        g.addColorStop(0,   'rgba(' + rgb + ',' + alpha + ')');
        g.addColorStop(0.5, 'rgba(' + rgb + ',' + (alpha * 0.38) + ')');
        g.addColorStop(1,   'rgba(' + rgb + ',0)');
        ctx.beginPath();
        ctx.arc(s.x, s.y, r, 0, 2 * Math.PI);
        ctx.fillStyle = g;
        ctx.fill();
      });
    }

    // ── 핀 / 클러스터 (순수 HTML div) ────────────────────────────
    function renderPins() {
      clearPins();
      if (!currentData.length) return;

      var proj     = map.getProjection();
      var level    = map.getLevel();
      var clusterR = Math.max(35, level * 9);

      var pts = currentData.map(function(p) {
        var pt = proj.containerPointFromCoords(new kakao.maps.LatLng(p.lat, p.lng));
        return { x: pt.x, y: pt.y };
      });

      var used = new Array(pts.length).fill(false);
      for (var a = 0; a < pts.length; a++) {
        if (used[a]) continue;
        var cluster = [a];
        used[a] = true;
        for (var b = a + 1; b < pts.length; b++) {
          if (used[b]) continue;
          var dx = pts[a].x - pts[b].x, dy = pts[a].y - pts[b].y;
          if (Math.sqrt(dx*dx + dy*dy) < clusterR) { cluster.push(b); used[b] = true; }
        }
        if (cluster.length === 1) {
          addSinglePin(cluster[0], pts[cluster[0]]);
        } else {
          var cLat = cluster.reduce(function(s,i){return s+currentData[i].lat;},0)/cluster.length;
          var cLng = cluster.reduce(function(s,i){return s+currentData[i].lng;},0)/cluster.length;
          var cPt  = proj.containerPointFromCoords(new kakao.maps.LatLng(cLat, cLng));
          addClusterPin(cLat, cLng, cPt, cluster);
        }
      }
    }

    function addSinglePin(idx, pt) {
      var p     = currentData[idx];
      var color = pinColor(p.count);
      var name10 = Array.from(p.name).slice(0,10).join('');
      var label  = Array.from(p.name).length > 10 ? esc(name10)+'&#8230;' : esc(p.name);
      var el    = document.createElement('div');
      el.className    = 'pin';
      el.dataset.lat  = p.lat;
      el.dataset.lng  = p.lng;
      el.style.left   = pt.x + 'px';
      el.style.top    = pt.y + 'px';
      el.innerHTML =
        '<div class="pin-circle" style="background:' + color + '">' +
          '<span class="pin-count">' + p.count + '</span>' +
          '<span class="pin-unit">&#54924;</span>' +
        '</div>' +
        '<div class="pin-tail" style="border-top:8px solid ' + color + '"></div>' +
        '<div class="pin-label">' + label + '</div>';
      el.addEventListener('click', function(e) { e.stopPropagation(); onPinTap(idx); });
      pinsDiv.appendChild(el);
    }

    function addClusterPin(cLat, cLng, pt, clusterArr) {
      var total = clusterArr.reduce(function(s,i){return s+currentData[i].count;},0);
      var n  = clusterArr.length;
      var sz = Math.min(62, 46 + n * 3);
      var ci = window._clusterData.length;
      window._clusterData.push(clusterArr);
      var el = document.createElement('div');
      el.className    = 'cpin';
      el.dataset.lat  = cLat;
      el.dataset.lng  = cLng;
      el.style.left   = pt.x + 'px';
      el.style.top    = pt.y + 'px';
      el.innerHTML =
        '<div class="cpin-circle" style="width:' + sz + 'px;height:' + sz + 'px;background:' + pinColor(total) + '">' +
          '<span class="cpin-num" style="font-size:' + Math.round(sz*0.36) + 'px">' + n + '</span>' +
          '<span class="cpin-sub">&#44275;</span>' +
        '</div>' +
        '<div class="cpin-badge">' + total + '&#54924; &#48169;&#47928;</div>';
      el.addEventListener('click', function(e) { e.stopPropagation(); onClusterTap(ci); });
      pinsDiv.appendChild(el);
    }

    function onPinTap(idx) { PinTappedChannel.postMessage(currentData[idx].name); }
    function onClusterTap(ci) {
      var b = new kakao.maps.LatLngBounds();
      window._clusterData[ci].forEach(function(i){ b.extend(new kakao.maps.LatLng(currentData[i].lat,currentData[i].lng)); });
      map.setBounds(b, 100);
    }

    function heatRgb(c) { return c>=4?'255,95,126':c>=2?'124,58,237':'129,140,248'; }
    function pinColor(c) { return c>=4?'#FF5F7E':c>=2?'#7C3AED':'#818CF8'; }
    function esc(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#x27;'); }
  </script>
</body>
</html>
''';
}

// ── 장소 상세 시트 ──────────────────────────────────────────────────────
class _PlaceDetailSheet extends StatefulWidget {
  final String         roomId;
  final String         myUserId;
  final String         myUserName;
  final _PlaceGroup    initialGroup;
  final HistoryService historyService;

  const _PlaceDetailSheet({
    required this.roomId,
    required this.myUserId,
    required this.myUserName,
    required this.initialGroup,
    required this.historyService,
  });

  @override
  State<_PlaceDetailSheet> createState() => _PlaceDetailSheetState();
}

class _PlaceDetailSheetState extends State<_PlaceDetailSheet> {
  late _PlaceGroup       _group;
  StreamSubscription?    _sub;

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;

    _sub = widget.historyService.watchHistory(widget.roomId).listen((history) {
      final entries = history.where((h) {
        final place = Map<String, dynamic>.from(h['confirmedPlace'] as Map? ?? {});
        return (place['name'] as String?) == widget.initialGroup.name;
      }).toList();

      if (!mounted) return;
      if (entries.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _group = _PlaceGroup(
          name:          widget.initialGroup.name,
          lat:           widget.initialGroup.lat,
          lng:           widget.initialGroup.lng,
          address:       widget.initialGroup.address,
          category:      widget.initialGroup.category,
          historyEntries: entries,
        );
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Color _countColor(int count) {
    if (count >= 4) return AppTheme.accent;
    if (count >= 2) return const Color(0xFF7C3AED);
    return const Color(0xFF818CF8);
  }

  @override
  Widget build(BuildContext context) {
    final color = _countColor(_group.count);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize:     0.4,
      maxChildSize:     0.95,
      snap:             true,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // 핸들
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),

            // 장소 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.place_rounded, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _group.name,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textDark),
                        ),
                        if (_group.address.isNotEmpty)
                          Text(
                            _group.address,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_group.count}회 방문',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 방문 목록
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
                itemCount: _group.historyEntries.length,
                itemBuilder: (_, i) {
                  final entry     = _group.historyEntries[i];
                  final historyId = entry['historyId'] as String;
                  final dateTs    = entry['appointmentDate'];
                  final date      = dateTs != null
                      ? ((dateTs as dynamic).toDate() as DateTime).toLocal()
                      : null;
                  return _VisitCard(
                    roomId:         widget.roomId,
                    historyId:      historyId,
                    date:           date,
                    myUserId:       widget.myUserId,
                    myUserName:     widget.myUserName,
                    historyService: widget.historyService,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 방문 카드 ──────────────────────────────────────────────────────────
class _VisitCard extends StatefulWidget {
  final String         roomId;
  final String         historyId;
  final DateTime?      date;
  final String         myUserId;
  final String         myUserName;
  final HistoryService historyService;

  const _VisitCard({
    required this.roomId,
    required this.historyId,
    required this.date,
    required this.myUserId,
    required this.myUserName,
    required this.historyService,
  });

  @override
  State<_VisitCard> createState() => _VisitCardState();
}

class _VisitCardState extends State<_VisitCard> {
  bool _deleting = false;

  String _formatDate(DateTime dt) {
    const wds = ['월', '화', '수', '목', '금', '토', '일'];
    return '${dt.year}.${dt.month.toString().padLeft(2,'0')}.${dt.day.toString().padLeft(2,'0')} (${wds[dt.weekday - 1]})';
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('만남 삭제'),
        content: const Text('이 만남 기록과 모든 후기를 삭제할까요?\n삭제하면 상대방에게도 사라져요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.historyService.deleteHistoryEntry(
          widget.roomId, widget.historyId);
    } catch (_) {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _showAddRecord() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddRecordSheet(
        roomId:         widget.roomId,
        historyId:      widget.historyId,
        userId:         widget.myUserId,
        userName:       widget.myUserName,
        historyService: widget.historyService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _deleting ? 0.4 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            // 날짜 행
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 14, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    widget.date != null
                        ? _formatDate(widget.date!)
                        : '날짜 미정',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark),
                  ),
                  const Spacer(),
                  if (_deleting)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: AppTheme.primary, strokeWidth: 2))
                  else
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 18, color: AppTheme.textMuted),
                      onPressed: _confirmDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 36, minHeight: 36),
                    ),
                ],
              ),
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // 기록 목록
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: widget.historyService
                  .watchRecords(widget.roomId, widget.historyId),
              builder: (_, snap) {
                final records = snap.data ?? [];
                return Column(
                  children: [
                    ...records.map((r) => _RecordItem(
                          record:     r,
                          isMyRecord: r['userId'] == widget.myUserId,
                          onDelete:   () =>
                              widget.historyService.deleteRecord(
                                  widget.roomId,
                                  widget.historyId,
                                  r['recordId'] as String),
                        )),
                    // 기록 추가 버튼
                    InkWell(
                      onTap: _showAddRecord,
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline,
                                size: 16, color: AppTheme.primary),
                            const SizedBox(width: 6),
                            const Text(
                              '기록 남기기',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── 기록 아이템 ────────────────────────────────────────────────────────
class _RecordItem extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool                 isMyRecord;
  final VoidCallback         onDelete;

  const _RecordItem({
    required this.record,
    required this.isMyRecord,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final userName = record['userName'] as String? ?? '';
    final review   = record['review']   as String? ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26, height: 26,
                decoration: const BoxDecoration(
                    color: AppTheme.primaryBg, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    userName.isNotEmpty ? userName[0] : '?',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                userName,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDark),
              ),
              const Spacer(),
              if (isMyRecord)
                GestureDetector(
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        title: const Text('기록 삭제'),
                        content: const Text('이 기록을 삭제할까요?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('취소',
                                style: TextStyle(color: AppTheme.textMuted)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('삭제',
                                style: TextStyle(color: AppTheme.error)),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) onDelete();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: AppTheme.textMuted),
                  ),
                ),
            ],
          ),
          if (review.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textDark, height: 1.55),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0x12000000)),
        ],
      ),
    );
  }

}

// ── 기록 추가 시트 ─────────────────────────────────────────────────────
class _AddRecordSheet extends StatefulWidget {
  final String         roomId;
  final String         historyId;
  final String         userId;
  final String         userName;
  final HistoryService historyService;

  const _AddRecordSheet({
    required this.roomId,
    required this.historyId,
    required this.userId,
    required this.userName,
    required this.historyService,
  });

  @override
  State<_AddRecordSheet> createState() => _AddRecordSheetState();
}

class _AddRecordSheetState extends State<_AddRecordSheet> {
  final _reviewCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => _reviewCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit || _loading) return;
    setState(() => _loading = true);
    try {
      await widget.historyService.addRecord(
        roomId:    widget.roomId,
        historyId: widget.historyId,
        userId:    widget.userId,
        userName:  widget.userName,
        review:    _reviewCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e, st) {
      debugPrint('addRecord error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 오류: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 핸들
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            '기록 남기기',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark),
          ),
          const SizedBox(height: 16),

          // 후기 입력
          TextField(
            controller: _reviewCtrl,
            maxLines:   4,
            onChanged:  (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '이 장소에서의 기억을 남겨보세요...',
              filled: true,
              fillColor: AppTheme.bg,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 14),

          // 저장 버튼
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canSubmit && !_loading ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.disabledBg,
                disabledForegroundColor: AppTheme.disabled,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('저장',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 친밀도 그래프 데이터 포인트 ────────────────────────────────────────────
class _ScorePoint {
  final DateTime date;
  final int      score;
  _ScorePoint(this.date, this.score);
}

// ── 친밀도 변화 그래프 시트 ───────────────────────────────────────────────
class _IntimacyGraphSheet extends StatelessWidget {
  final List<Map<String, dynamic>> history;

  const _IntimacyGraphSheet({required this.history});

  List<_ScorePoint> _buildPoints() {
    final pts = <_ScorePoint>[];
    for (final h in history) {
      final raw = h['intimacyScore'];
      if (raw == null) continue;
      final score  = (raw as num).toInt();
      final dateTs = h['appointmentDate'] ?? h['date'];
      if (dateTs == null) continue;
      final date = (dateTs as dynamic).toDate() as DateTime;
      pts.add(_ScorePoint(date.toLocal(), score));
    }
    pts.sort((a, b) => a.date.compareTo(b.date));
    return pts;
  }

  @override
  Widget build(BuildContext context) {
    final pts = _buildPoints();
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Text(
            '친밀도 변화',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark),
          ),
          const SizedBox(height: 24),
          if (pts.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.bar_chart_rounded,
                      size: 44, color: AppTheme.border),
                  const SizedBox(height: 12),
                  const Text(
                    '아직 데이터가 부족해요',
                    style: TextStyle(
                        fontSize: 14, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '약속을 2번 이상 확정하면 그래프가 표시돼요',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 220,
              child: CustomPaint(
                painter: _IntimacyGraphPainter(pts),
                size: Size.infinite,
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── 친밀도 그래프 CustomPainter ───────────────────────────────────────────
class _IntimacyGraphPainter extends CustomPainter {
  final List<_ScorePoint> pts;
  _IntimacyGraphPainter(this.pts);

  static const _padL = 36.0;
  static const _padR = 16.0;
  static const _padT = 28.0;
  static const _padB = 36.0;

  Color _scoreColor(int s) {
    if (s >= 80) return AppTheme.primary;
    if (s >= 60) return AppTheme.drawing;
    if (s >= 40) return AppTheme.accent;
    return AppTheme.intimacyLow;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final chartW = size.width - _padL - _padR;
    final chartH = size.height - _padT - _padB;
    final n = pts.length;

    // 그리드 라인 (0, 50, 100)
    final gridPaint = Paint()
      ..color = AppTheme.border
      ..strokeWidth = 0.8;
    for (final yVal in [0, 50, 100]) {
      final dy = _padT + chartH * (1 - yVal / 100);
      canvas.drawLine(Offset(_padL, dy), Offset(_padL + chartW, dy), gridPaint);
      _drawText(canvas, '$yVal',
          Offset(_padL - 4, dy),
          const TextStyle(fontSize: 10, color: AppTheme.textMuted),
          align: TextAlign.right);
    }

    // X 좌표 계산 (균등 배치)
    List<Offset> offsets = List.generate(n, (i) {
      final x = n == 1
          ? _padL + chartW / 2
          : _padL + i * chartW / (n - 1);
      final y = _padT + chartH * (1 - pts[i].score / 100);
      return Offset(x, y);
    });

    // 채워진 영역
    final fillPath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (int i = 1; i < n; i++) fillPath.lineTo(offsets[i].dx, offsets[i].dy);
    fillPath.lineTo(offsets.last.dx, _padT + chartH);
    fillPath.lineTo(offsets.first.dx, _padT + chartH);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.primary.withValues(alpha: 0.22),
            AppTheme.primary.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(_padL, _padT, chartW, chartH)),
    );

    // 연결선
    final linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (int i = 1; i < n; i++) linePath.lineTo(offsets[i].dx, offsets[i].dy);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = AppTheme.primary.withValues(alpha: 0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 포인트 + 라벨
    for (int i = 0; i < n; i++) {
      final o     = offsets[i];
      final score = pts[i].score;
      final color = _scoreColor(score);

      // 흰 배경 원
      canvas.drawCircle(o, 7, Paint()..color = Colors.white);
      // 색상 원
      canvas.drawCircle(o, 5, Paint()..color = color);

      // 점수 라벨 (위)
      _drawText(canvas, '$score', Offset(o.dx, o.dy - 20),
          TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          align: TextAlign.center);

      // 날짜 라벨 (아래)
      final d = pts[i].date;
      final label = '${d.month}/${d.day}';
      _drawText(canvas, label, Offset(o.dx, _padT + chartH + 6),
          const TextStyle(fontSize: 10, color: AppTheme.textMuted),
          align: TextAlign.center);
    }
  }

  void _drawText(Canvas canvas, String text, Offset anchor, TextStyle style,
      {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    final dx = align == TextAlign.center
        ? anchor.dx - tp.width / 2
        : align == TextAlign.right
            ? anchor.dx - tp.width
            : anchor.dx;
    tp.paint(canvas, Offset(dx, anchor.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _IntimacyGraphPainter old) =>
      old.pts != pts;
}
