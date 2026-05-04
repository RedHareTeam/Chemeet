import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class KakaoMapWebView extends StatefulWidget {
  final String kakaoApiKey;
  final Function(double lat, double lng) onCenterChanged;
  final Function(double lat, double lng, double radius) onCircleDrawn;
  final Map<String, dynamic>? partnerCircle;

  const KakaoMapWebView({
    super.key,
    required this.kakaoApiKey,
    required this.onCenterChanged,
    required this.onCircleDrawn,
    this.partnerCircle,
  });

  @override
  State<KakaoMapWebView> createState() => KakaoMapWebViewState();
}

class KakaoMapWebViewState extends State<KakaoMapWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (error) =>
            debugPrint('WebView 에러: ${error.description}'),
        onPageFinished: (_) => debugPrint('지도 로드 완료'),
      ))
      ..addJavaScriptChannel(
        'CircleDrawnChannel',
        onMessageReceived: (msg) {
          final parts = msg.message.split(',');
          widget.onCircleDrawn(
            double.parse(parts[0]),
            double.parse(parts[1]),
            double.parse(parts[2]),
          );
        },
      )
      ..addJavaScriptChannel(
        'Console',
        onMessageReceived: (msg) => debugPrint('JS: ${msg.message}'),
      )
      ..loadHtmlString(_buildHtml());
  }

  @override
  void didUpdateWidget(KakaoMapWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.partnerCircle != null &&
        widget.partnerCircle != oldWidget.partnerCircle) {
      final p = widget.partnerCircle!;
      updatePartnerCircle(
        (p['lat'] as num).toDouble(),
        (p['lng'] as num).toDouble(),
        (p['radius'] as num).toDouble(),
        p['userName'] ?? '상대방',
      );
    }
  }

  void updateMyCircle(double lat, double lng, double radius, String userName) {
    _controller.runJavaScript(
        'updateMyCircle($lat, $lng, $radius, "$userName")');
  }

  void updatePartnerCircle(
      double lat, double lng, double radius, String userName) {
    _controller.runJavaScript(
        'updatePartnerCircle($lat, $lng, $radius, "$userName")');
  }

  void setDrawMode(bool isDrawMode) {
    debugPrint('setDrawMode 호출: $isDrawMode');
    _controller.runJavaScript('setDrawMode($isDrawMode)');
  }

  void addMessage(String userId, String userName, String message) {
    // 특수문자 이스케이프
    final escaped = message.replaceAll("'", "\\'").replaceAll('"', '\\"');
    _controller
        .runJavaScript('addMessage("$userId", "$userName", "$escaped")');
  }

  String _buildHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;700&display=swap" rel="stylesheet">
  <style>
    * {
      margin: 0; padding: 0; box-sizing: border-box;
      font-family: "Noto Sans KR", sans-serif;
      -webkit-user-select: none;
      -webkit-touch-callout: none;
      user-select: none;
    }
    body { width: 100vw; height: 100vh; overflow: hidden; background: #e8e8e8; }
    #map { width: 100%; height: 100%; }
    #canvas {
      position: absolute; top: 0; left: 0;
      width: 100%; height: 100%;
      pointer-events: none; z-index: 10;
    }
    #canvas.draw-mode { pointer-events: all; }
    #overlay-container {
      position: absolute; top: 0; left: 0;
      width: 100%; height: 100%;
      pointer-events: none; z-index: 20;
    }

    /* 말풍선 묶음 */
    .bubble-wrap {
      position: absolute;
      display: flex;
      flex-direction: column;
      align-items: center;
      transform: translate(-50%, -100%);
      pointer-events: none;
      gap: 4px;
      padding-bottom: 6px;
    }
    .bubble {
      background: rgba(108,99,255,0.85);
      color: white;
      padding: 5px 10px;
      border-radius: 12px;
      font-size: 12px;
      white-space: nowrap;
      max-width: 160px;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .bubble.partner { background: rgba(255,101,132,0.85); }
    .name-tag {
      background: rgba(0,0,0,0.5);
      color: white;
      padding: 2px 8px;
      border-radius: 8px;
      font-size: 11px;
    }

    /* 방향 핀 */
    .direction-pin {
      position: absolute;
      width: 48px;
      height: 48px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      flex-direction: column;
      font-size: 16px;
      font-weight: bold;
      color: white;
      cursor: pointer;
      pointer-events: all;
      box-shadow: 0 2px 8px rgba(0,0,0,0.3);
      transform: translate(-50%, -50%);
    }
    .direction-pin .pin-name {
      font-size: 9px;
      margin-top: 1px;
    }
    .direction-pin .pin-msg {
      position: absolute;
      bottom: 54px;
      left: 50%;
      transform: translateX(-50%);
      background: rgba(0,0,0,0.75);
      color: white;
      padding: 4px 8px;
      border-radius: 8px;
      font-size: 11px;
      white-space: nowrap;
      max-width: 130px;
      overflow: hidden;
      text-overflow: ellipsis;
      pointer-events: none;
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <canvas id="canvas"></canvas>
  <div id="overlay-container"></div>

  <script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=${widget.kakaoApiKey}"></script>
  <script>
    var map, myCircle, partnerCircle;
    var isDrawMode = false;
    var isDrawing = false;
    var drawnPoints = [];
    var canvas = document.getElementById('canvas');
    var ctx = canvas.getContext('2d');
    var overlayContainer = document.getElementById('overlay-container');

    var circles = {
      my:      { lat: null, lng: null, radius: null, userName: '', messages: [] },
      partner: { lat: null, lng: null, radius: null, userName: '', messages: [] }
    };

    kakao.maps.load(function() {
      Console.postMessage('카카오맵 로드됨');

      canvas.width  = window.innerWidth;
      canvas.height = window.innerHeight;

      map = new kakao.maps.Map(document.getElementById('map'), {
        center: new kakao.maps.LatLng(37.5665, 126.9780),
        level: 7
      });

      myCircle = new kakao.maps.Circle({
        map: null,
        center: new kakao.maps.LatLng(37.5665, 126.9780),
        radius: 3000,
        strokeWeight: 2,
        strokeColor: '#6C63FF',
        strokeOpacity: 0.8,
        fillColor: '#6C63FF',
        fillOpacity: 0.2
      });

      kakao.maps.event.addListener(map, 'center_changed', updateAllOverlays);
      kakao.maps.event.addListener(map, 'zoom_changed',   updateAllOverlays);

      // ── 그리기 이벤트 ──
      var mapDiv = document.getElementById('map');

      canvas.addEventListener('touchstart', function(e) {
        if (!isDrawMode) return;
        e.preventDefault();
        isDrawing = true;
        drawnPoints = [];
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.beginPath();
        ctx.strokeStyle = 'rgba(108,99,255,0.7)';
        ctx.lineWidth = 3;
        ctx.lineCap = 'round';
        var t = e.touches[0];
        var rect = canvas.getBoundingClientRect();          // ← 추가
        var x = t.clientX - rect.left;                     // ← 수정
        var y = t.clientY - rect.top;                      // ← 수정
        ctx.moveTo(x, y);
        drawnPoints.push({ x: x, y: y });                  // ← 수정
      }, { passive: false });

      canvas.addEventListener('touchmove', function(e) {
        if (!isDrawMode || !isDrawing) return;
        e.preventDefault();
        var t = e.touches[0];
        var rect = canvas.getBoundingClientRect();          // ← 추가
        var x = t.clientX - rect.left;                     // ← 수정
        var y = t.clientY - rect.top;                      // ← 수정
        ctx.lineTo(x, y);
        ctx.stroke();
        drawnPoints.push({ x: x, y: y });                  // ← 수정
      }, { passive: false });

      canvas.addEventListener('touchend', function(e) {
        if (!isDrawMode || !isDrawing) return;
        isDrawing = false;
        if (drawnPoints.length < 5) return;

        // 무게중심
        var cx = 0, cy = 0;
        drawnPoints.forEach(function(p) { cx += p.x; cy += p.y; });
        cx /= drawnPoints.length;
        cy /= drawnPoints.length;

        // 평균 반경
        var avgR = 0;
        drawnPoints.forEach(function(p) {
          avgR += Math.sqrt((p.x-cx)*(p.x-cx)+(p.y-cy)*(p.y-cy));
        });
        avgR /= drawnPoints.length;

        // 보정 원 미리보기
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.beginPath();
        ctx.arc(cx, cy, avgR, 0, 2*Math.PI);
        ctx.strokeStyle = 'rgba(108,99,255,0.9)';
        ctx.lineWidth = 2;
        ctx.stroke();

        setTimeout(function() {
          ctx.clearRect(0, 0, canvas.width, canvas.height);

          var proj = map.getProjection();
          var centerLatLng = proj.coordsFromContainerPoint(new kakao.maps.Point(cx, cy));
          var edgeLatLng   = proj.coordsFromContainerPoint(new kakao.maps.Point(cx + avgR, cy));

          var R    = 6371000;
          var dLat = (edgeLatLng.getLat() - centerLatLng.getLat()) * Math.PI / 180;
          var dLng = (edgeLatLng.getLng() - centerLatLng.getLng()) * Math.PI / 180;
          var a    = Math.sin(dLat/2)*Math.sin(dLat/2) +
                     Math.cos(centerLatLng.getLat()*Math.PI/180) *
                     Math.cos(edgeLatLng.getLat()*Math.PI/180) *
                     Math.sin(dLng/2)*Math.sin(dLng/2);
          var radiusMeters = R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
          radiusMeters = Math.max(500, Math.min(20000, radiusMeters));

          Console.postMessage('원 그리기 완료: ' + radiusMeters + 'm');

          myCircle.setPosition(centerLatLng);
          myCircle.setRadius(radiusMeters);
          myCircle.setMap(map);

          CircleDrawnChannel.postMessage(
            centerLatLng.getLat() + ',' + centerLatLng.getLng() + ',' + radiusMeters
          );
        }, 300);
      }, { passive: false });

      document.addEventListener('contextmenu', function(e) { e.preventDefault(); });
    });

    // ── 오버레이 전체 업데이트 ──
    function updateAllOverlays() {
      overlayContainer.innerHTML = '';
      ['my', 'partner'].forEach(function(key) {
        var c = circles[key];
        if (c.lat === null) return;
        var screenPos = getScreenPos(c.lat, c.lng);
        if (isOnScreen(screenPos)) {
          renderBubbles(key, screenPos);
        } else {
          renderDirectionPin(key, c.lat, c.lng);
        }
      });
    }

    function getScreenPos(lat, lng) {
      var proj  = map.getProjection();
      var point = proj.containerPointFromCoords(new kakao.maps.LatLng(lat, lng));
      return { x: point.x, y: point.y };
    }

    function isOnScreen(pos) {
      var m = 80;
      return pos.x > -m && pos.x < window.innerWidth  + m &&
             pos.y > -m && pos.y < window.innerHeight + m;
    }

    // 말풍선 렌더
    function renderBubbles(key, screenPos) {
      var c    = circles[key];
      var isMe = key === 'my';
      var wrap = document.createElement('div');
      wrap.className = 'bubble-wrap';
      wrap.style.left = screenPos.x + 'px';
      wrap.style.top  = (screenPos.y - 20) + 'px';
    
      // 이름 태그 (맨 아래)
      var nameTag = document.createElement('div');
      nameTag.className = 'name-tag';
      nameTag.innerText = c.userName;
      wrap.appendChild(nameTag);
    
      // 최대 4개 — 최신이 이름 바로 위, 오래된 것이 위로
      var msgs = c.messages.slice(-4);
      msgs.forEach(function(msg, i) {
        // i=0 이 제일 오래된 것 → 위에, i=last 가 최신 → 이름 바로 위
        var opacity = msgs.length === 1 ? 1.0 : 0.25 + (i / (msgs.length - 1)) * 0.75;
        var bubble  = document.createElement('div');
        bubble.className = 'bubble' + (isMe ? '' : ' partner');
        bubble.style.opacity = opacity;
        bubble.innerText = msg;
        // nameTag 앞에 삽입 → 위로 쌓임
        wrap.insertBefore(bubble, nameTag);
      });
    
      overlayContainer.appendChild(wrap);
    }

    // 방향 핀 렌더
    function renderDirectionPin(key, lat, lng) {
      var c     = circles[key];
      var isMe  = key === 'my';
      var color = isMe ? '#6C63FF' : '#FF6584';
      var edge  = getEdgePosition(getScreenPos(lat, lng));

      var pin = document.createElement('div');
      pin.className  = 'direction-pin';
      pin.style.background = color;
      pin.style.left = edge.x + 'px';
      pin.style.top  = edge.y + 'px';

      var initial = document.createElement('span');
      initial.innerText = c.userName ? c.userName[0] : '?';
      pin.appendChild(initial);

      var nameEl = document.createElement('div');
      nameEl.className = 'pin-name';
      nameEl.innerText = c.userName;
      pin.appendChild(nameEl);

      // 최근 메시지
      if (c.messages.length > 0) {
        var msgEl = document.createElement('div');
        msgEl.className = 'pin-msg';
        msgEl.innerText = c.messages[c.messages.length - 1];
        pin.appendChild(msgEl);
      }

      pin.addEventListener('click', function() {
        map.panTo(new kakao.maps.LatLng(lat, lng));
      });

      overlayContainer.appendChild(pin);
    }

    // 화면 가장자리 좌표
    function getEdgePosition(screenPos) {
      var W  = window.innerWidth;
      var H  = window.innerHeight;
      var cx = W / 2, cy = H / 2;
      var dx = screenPos.x - cx;
      var dy = screenPos.y - cy;
      var angle = Math.atan2(dy, dx);
      var m  = 44;
      var tx = cx + (W/2 - m) * Math.cos(angle);
      var ty = cy + (H/2 - m) * Math.sin(angle);
      tx = Math.max(m, Math.min(W - m, tx));
      ty = Math.max(m, Math.min(H - m, ty));
      return { x: tx, y: ty };
    }

    // ── Flutter → JS 함수 ──
    function updateMyCircle(lat, lng, radius, userName) {
      circles.my.lat      = lat;
      circles.my.lng      = lng;
      circles.my.radius   = radius;
      circles.my.userName = userName;
      myCircle.setPosition(new kakao.maps.LatLng(lat, lng));
      myCircle.setRadius(radius);
      myCircle.setMap(map);
      updateAllOverlays();
    }

    function updatePartnerCircle(lat, lng, radius, userName) {
      circles.partner.lat      = lat;
      circles.partner.lng      = lng;
      circles.partner.radius   = radius;
      circles.partner.userName = userName;
      if (partnerCircle) {
        partnerCircle.setPosition(new kakao.maps.LatLng(lat, lng));
        partnerCircle.setRadius(radius);
      } else {
        partnerCircle = new kakao.maps.Circle({
          map: map,
          center: new kakao.maps.LatLng(lat, lng),
          radius: radius,
          strokeWeight: 2,
          strokeColor: '#FF6584',
          strokeOpacity: 0.8,
          fillColor: '#FF6584',
          fillOpacity: 0.2
        });
      }
      updateAllOverlays();
    }

    function addMessage(userId, userName, message) {
      var key = (circles.my.userName === userName) ? 'my' : 'partner';
      circles[key].messages.push(message);
      if (circles[key].messages.length > 4) circles[key].messages.shift();
      updateAllOverlays();
    
      // 5초 후 가장 오래된 메시지 삭제
      setTimeout(function() {
        circles[key].messages.shift();
        updateAllOverlays();
      }, 5000);
    }

    function setDrawMode(enabled) {
      isDrawMode = enabled;
      canvas.className = enabled ? 'draw-mode' : '';
      if (!enabled) ctx.clearRect(0, 0, canvas.width, canvas.height);
      Console.postMessage('드로우모드: ' + enabled + ' / canvas class: ' + canvas.className);
    }
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}