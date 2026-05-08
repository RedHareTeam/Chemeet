import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class KakaoMapWebView extends StatefulWidget {
  final String kakaoApiKey;
  final Function(double lat, double lng) onCenterChanged;
  final Function(double lat, double lng, double radius) onCircleDrawn;
  final VoidCallback? onMapReady;

  const KakaoMapWebView({
    super.key,
    required this.kakaoApiKey,
    required this.onCenterChanged,
    required this.onCircleDrawn,
    this.onMapReady,
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
      ..addJavaScriptChannel(
        'MapReadyChannel',
        onMessageReceived: (_) => widget.onMapReady?.call(),
      )
      ..loadHtmlString(_buildHtml());
  }

  void updateMyCircle(double lat, double lng, double radius, String userName) {
    final encName = Uri.encodeComponent(userName);
    _controller.runJavaScript(
        'updateMyCircle($lat, $lng, $radius, decodeURIComponent("$encName"))');
  }

  void updatePartnerCircle(
    String partnerId,
    double lat,
    double lng,
    double radius,
    String userName,
    String color,
  ) {
    final encName = Uri.encodeComponent(userName);
    _controller.runJavaScript(
        'updatePartnerCircle("$partnerId", $lat, $lng, $radius, decodeURIComponent("$encName"), "$color")');
  }

  void clearPartnerCircle(String partnerId) {
    _controller.runJavaScript('clearPartnerCircle("$partnerId")');
  }

  void setDrawMode(bool isDrawMode) {
    debugPrint('setDrawMode 호출: $isDrawMode');
    _controller.runJavaScript('setDrawMode($isDrawMode)');
  }

  void addMessage(String userId, String userName, String message) {
    final encName = Uri.encodeComponent(userName);
    final encMsg  = Uri.encodeComponent(message);
    _controller.runJavaScript(
        'addMessage("$userId", decodeURIComponent("$encName"), decodeURIComponent("$encMsg"))');
  }

  String _buildHtml() {
    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;700&display=swap" rel="stylesheet">
  <style>
    * {
      margin: 0; padding: 0; box-sizing: border-box;
      font-family: "Noto Sans KR", -apple-system, "Apple SD Gothic Neo", system-ui, sans-serif;
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
      color: white;
      padding: 5px 10px;
      border-radius: 12px;
      font-size: 12px;
      white-space: nowrap;
      max-width: 160px;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .name-tag {
      background: rgba(0,0,0,0.5);
      color: white;
      padding: 2px 8px;
      border-radius: 8px;
      font-size: 11px;
    }

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
    var map, myCircle;
    var isDrawMode = false;
    var isDrawing = false;
    var drawnPoints = [];
    var canvas = document.getElementById('canvas');
    var ctx = canvas.getContext('2d');
    var overlayContainer = document.getElementById('overlay-container');

    // circles.my + circles.partners[partnerId]
    var circles = {
      my: { lat: null, lng: null, radius: null, userName: '', color: '#6C63FF', messages: [] },
      partners: {}
    };
    // kakao.maps.Circle instances keyed by partnerId
    var partnerCircleObjects = {};

    kakao.maps.load(function() {
      Console.postMessage('kakao maps ready');

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
        var rect = canvas.getBoundingClientRect();
        var x = t.clientX - rect.left;
        var y = t.clientY - rect.top;
        ctx.moveTo(x, y);
        drawnPoints.push({ x: x, y: y });
      }, { passive: false });

      canvas.addEventListener('touchmove', function(e) {
        if (!isDrawMode || !isDrawing) return;
        e.preventDefault();
        var t = e.touches[0];
        var rect = canvas.getBoundingClientRect();
        var x = t.clientX - rect.left;
        var y = t.clientY - rect.top;
        ctx.lineTo(x, y);
        ctx.stroke();
        drawnPoints.push({ x: x, y: y });
      }, { passive: false });

      canvas.addEventListener('touchend', function(e) {
        if (!isDrawMode || !isDrawing) return;
        isDrawing = false;
        if (drawnPoints.length < 5) return;

        var cx = 0, cy = 0;
        drawnPoints.forEach(function(p) { cx += p.x; cy += p.y; });
        cx /= drawnPoints.length;
        cy /= drawnPoints.length;

        var avgR = 0;
        drawnPoints.forEach(function(p) {
          avgR += Math.sqrt((p.x-cx)*(p.x-cx)+(p.y-cy)*(p.y-cy));
        });
        avgR /= drawnPoints.length;

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

          Console.postMessage('circle drawn: ' + radiusMeters + 'm');

          myCircle.setPosition(centerLatLng);
          myCircle.setRadius(radiusMeters);
          myCircle.setMap(map);

          CircleDrawnChannel.postMessage(
            centerLatLng.getLat() + ',' + centerLatLng.getLng() + ',' + radiusMeters
          );
        }, 300);
      }, { passive: false });

      document.addEventListener('contextmenu', function(e) { e.preventDefault(); });

      MapReadyChannel.postMessage('ready');
    });

    function hexToRgba(hex, alpha) {
      var r = parseInt(hex.slice(1,3), 16);
      var g = parseInt(hex.slice(3,5), 16);
      var b = parseInt(hex.slice(5,7), 16);
      return 'rgba(' + r + ',' + g + ',' + b + ',' + alpha + ')';
    }

    function updateAllOverlays() {
      overlayContainer.innerHTML = '';

      // 내 원
      if (circles.my.lat !== null) {
        var screenPos = getScreenPos(circles.my.lat, circles.my.lng);
        if (isOnScreen(screenPos)) {
          renderBubbles(circles.my, screenPos);
        } else {
          renderDirectionPin(circles.my, circles.my.lat, circles.my.lng);
        }
      }

      // 파트너 원들
      Object.keys(circles.partners).forEach(function(pid) {
        var c = circles.partners[pid];
        if (c.lat === null) return;
        var screenPos = getScreenPos(c.lat, c.lng);
        if (isOnScreen(screenPos)) {
          renderBubbles(c, screenPos);
        } else {
          renderDirectionPin(c, c.lat, c.lng);
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

    function renderBubbles(circleData, screenPos) {
      var wrap = document.createElement('div');
      wrap.className = 'bubble-wrap';
      wrap.style.left = screenPos.x + 'px';
      wrap.style.top  = (screenPos.y - 20) + 'px';

      var nameTag = document.createElement('div');
      nameTag.className = 'name-tag';
      nameTag.innerText = circleData.userName;
      wrap.appendChild(nameTag);

      var msgs = circleData.messages.slice(-4);
      msgs.forEach(function(msg, i) {
        var opacity = msgs.length === 1 ? 1.0 : 0.25 + (i / (msgs.length - 1)) * 0.75;
        var bubble  = document.createElement('div');
        bubble.className = 'bubble';
        bubble.style.background = hexToRgba(circleData.color, 0.85);
        bubble.style.opacity = opacity;
        bubble.innerText = msg;
        wrap.insertBefore(bubble, nameTag);
      });

      overlayContainer.appendChild(wrap);
    }

    function renderDirectionPin(circleData, lat, lng) {
      var edge = getEdgePosition(getScreenPos(lat, lng));

      var pin = document.createElement('div');
      pin.className  = 'direction-pin';
      pin.style.background = circleData.color;
      pin.style.left = edge.x + 'px';
      pin.style.top  = edge.y + 'px';

      var initial = document.createElement('span');
      initial.innerText = circleData.userName ? circleData.userName[0] : '?';
      pin.appendChild(initial);

      var nameEl = document.createElement('div');
      nameEl.className = 'pin-name';
      nameEl.innerText = circleData.userName;
      pin.appendChild(nameEl);

      if (circleData.messages.length > 0) {
        var msgEl = document.createElement('div');
        msgEl.className = 'pin-msg';
        msgEl.innerText = circleData.messages[circleData.messages.length - 1];
        pin.appendChild(msgEl);
      }

      pin.addEventListener('click', function() {
        map.panTo(new kakao.maps.LatLng(lat, lng));
      });

      overlayContainer.appendChild(pin);
    }

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

    function clearPartnerCircle(partnerId) {
      if (partnerCircleObjects[partnerId]) {
        partnerCircleObjects[partnerId].setMap(null);
        delete partnerCircleObjects[partnerId];
      }
      delete circles.partners[partnerId];
      updateAllOverlays();
    }

    function updatePartnerCircle(partnerId, lat, lng, radius, userName, color) {
      if (!circles.partners[partnerId]) {
        circles.partners[partnerId] = { lat: null, lng: null, radius: null, userName: '', color: color, messages: [] };
      }
      var c = circles.partners[partnerId];
      c.lat      = lat;
      c.lng      = lng;
      c.radius   = radius;
      c.userName = userName;
      c.color    = color;

      if (partnerCircleObjects[partnerId]) {
        partnerCircleObjects[partnerId].setPosition(new kakao.maps.LatLng(lat, lng));
        partnerCircleObjects[partnerId].setRadius(radius);
      } else {
        partnerCircleObjects[partnerId] = new kakao.maps.Circle({
          map: map,
          center: new kakao.maps.LatLng(lat, lng),
          radius: radius,
          strokeWeight: 2,
          strokeColor: color,
          strokeOpacity: 0.8,
          fillColor: color,
          fillOpacity: 0.2
        });
      }
      updateAllOverlays();
    }

    function addMessage(userId, userName, message) {
      var circleData = null;

      if (circles.my.userName === userName) {
        circleData = circles.my;
      } else {
        // 파트너 중에서 userName으로 탐색 (userId가 partners 키와 다를 수 있으므로)
        var keys = Object.keys(circles.partners);
        for (var i = 0; i < keys.length; i++) {
          if (circles.partners[keys[i]].userName === userName) {
            circleData = circles.partners[keys[i]];
            break;
          }
        }
        // userName 불일치 시 userId로 재탐색
        if (!circleData && circles.partners[userId]) {
          circleData = circles.partners[userId];
        }
      }

      if (!circleData) return;

      circleData.messages.push(message);
      if (circleData.messages.length > 4) circleData.messages.shift();
      updateAllOverlays();

      setTimeout(function() {
        circleData.messages.shift();
        updateAllOverlays();
      }, 5000);
    }

    function setDrawMode(enabled) {
      isDrawMode = enabled;
      canvas.className = enabled ? 'draw-mode' : '';
      if (!enabled) ctx.clearRect(0, 0, canvas.width, canvas.height);
      Console.postMessage('drawMode: ' + enabled + ' / class: ' + canvas.className);
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
