import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

import '../models/route_point.dart';
import '../models/route_info.dart';

class KakaoMapService {
  static final KakaoMapService _instance = KakaoMapService._internal();
  factory KakaoMapService() => _instance;
  KakaoMapService._internal();

  // Kakao Developers에서 발급받은 JavaScript 앱 키
  static const String kakaoMapApiKey = '7261c06ab1f8493085156e1c60751ed4';

  final WebviewController _controller = WebviewController();
  bool _isMapInitialized = false;
  bool _isControllerInitialized = false;
  final List<Completer<void>> _pendingOperations = [];
  final StreamController<String> _messageController = StreamController<String>.broadcast();

  // 지도 초기화 여부 확인
  bool get isMapInitialized => _isMapInitialized;

  // 컨트롤러 가져오기
  WebviewController get controller => _controller;

  // 메시지 스트림 가져오기
  Stream<String> get onMessage => _messageController.stream;

  // 컨트롤러 초기화
  Future<void> _initWebViewController() async {
    if (_isControllerInitialized) return;

    try {
      await _controller.initialize();

      // 웹뷰 설정
      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      // 메시지 수신 설정
      _controller.webMessage.listen((event) {
        try {
          final data = jsonDecode(event.data);
          if (data['event'] == 'mapInitialized') {
            _completeInitialization();
          }
          _messageController.add(event.data);
        } catch (e) {
          print('메시지 처리 오류: $e');
        }
      });

      _isControllerInitialized = true;
    } catch (e) {
      print('WebView 컨트롤러 초기화 오류: $e');
      rethrow;
    }
  }

  // 지도 초기화 완료 처리
  void _completeInitialization() {
    if (_isMapInitialized) return; // 이미 초기화되었으면 무시

    _isMapInitialized = true;

    // 대기 중인 작업들 처리
    for (var completer in _pendingOperations) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _pendingOperations.clear();
  }

  // 지도 초기화 대기
  Future<void> waitForInitialization() async {
    if (_isMapInitialized) return;

    final completer = Completer<void>();
    _pendingOperations.add(completer);
    return completer.future;
  }

  // HTML 내용 생성
  String _getKakaoMapHtml() {
    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8"/>
        <title>Kakao Maps</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
        <style>
          body { margin: 0; padding: 0; }
          #map { width: 100%; height: 100vh; }
        </style>
      </head>
      <body>
        <div id="map"></div>
        <script type="text/javascript" src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=$kakaoMapApiKey&libraries=services,drawing,clusterer"></script>
        <script>
          // 지도 객체
          var map;
          // 마커 목록
          var markers = {};
          // 경로선 목록
          var polylines = {};
          
          // JavaScript 메시지 전송 함수
          function sendMessage(data) {
            window.chrome.webview.postMessage(JSON.stringify(data));
          }
          
          // 지도 초기화
          function initMap() {
            // 지도 생성
            map = new kakao.maps.Map(document.getElementById('map'), {
              center: new kakao.maps.LatLng(37.566, 126.978),  // 서울 시청
              level: 3  // 줌 레벨
            });
            
            // 지도 컨트롤 추가
            var zoomControl = new kakao.maps.ZoomControl();
            map.addControl(zoomControl, kakao.maps.ControlPosition.RIGHT);
            
            // 지도 타입 컨트롤 추가
            var mapTypeControl = new kakao.maps.MapTypeControl();
            map.addControl(mapTypeControl, kakao.maps.ControlPosition.TOPRIGHT);
            
            // 초기화 완료 메시지 전송
            sendMessage({ event: 'mapInitialized' });
          }
          
          // 마커 추가
          function addMarker(id, lat, lng, name, type) {
            // 기존 마커가 있으면 제거
            if (markers[id]) {
              markers[id].setMap(null);
              delete markers[id];
            }
            
            // 마커 이미지 설정
            var imageSrc, imageSize;
            switch (type) {
              case 'start':
                imageSrc = 'https://t1.daumcdn.net/localimg/localimages/07/mapapidoc/red_b.png';
                imageSize = new kakao.maps.Size(50, 45);
                break;
              case 'end':
                imageSrc = 'https://t1.daumcdn.net/localimg/localimages/07/mapapidoc/blue_b.png';
                imageSize = new kakao.maps.Size(50, 45);
                break;
              default:
                imageSrc = 'https://t1.daumcdn.net/localimg/localimages/07/mapapidoc/markerStar.png';
                imageSize = new kakao.maps.Size(24, 35);
            }
            
            var markerImage = new kakao.maps.MarkerImage(imageSrc, imageSize);
            
            // 마커 생성
            var marker = new kakao.maps.Marker({
              position: new kakao.maps.LatLng(lat, lng),
              map: map,
              title: name,
              image: markerImage
            });
            
            // 인포윈도우 생성
            var infowindow = new kakao.maps.InfoWindow({
              content: '<div style="padding:5px;font-size:12px;">' + name + '</div>'
            });
            
            // 마커 클릭 이벤트
            kakao.maps.event.addListener(marker, 'click', function() {
              infowindow.open(map, marker);
            });
            
            // 목록에 마커 추가
            markers[id] = marker;
            
            // 마커 추가 완료 메시지 전송
            sendMessage({ event: 'markerAdded', id: id });
          }
          
          // 경로선 그리기
          function drawRoute(routeId, points, color) {
            // 기존 경로선이 있으면 제거
            if (polylines[routeId]) {
              polylines[routeId].setMap(null);
              delete polylines[routeId];
            }
            
            // 경로 좌표 배열 생성
            var path = [];
            for (var i = 0; i < points.length; i++) {
              path.push(new kakao.maps.LatLng(points[i].lat, points[i].lng));
            }
            
            // 경로선 생성
            var polyline = new kakao.maps.Polyline({
              path: path,
              strokeWeight: 5,
              strokeColor: color,
              strokeOpacity: 0.7,
              strokeStyle: 'solid'
            });
            
            // 지도에 경로선 표시
            polyline.setMap(map);
            
            // 목록에 경로선 추가
            polylines[routeId] = polyline;
            
            // 경로 표시 영역으로 지도 이동
            if (path.length > 0) {
              var bounds = new kakao.maps.LatLngBounds();
              for (var i = 0; i < path.length; i++) {
                bounds.extend(path[i]);
              }
              map.setBounds(bounds);
            }
            
            // 경로 그리기 완료 메시지 전송
            sendMessage({ event: 'routeDrawn', routeId: routeId });
          }
          
          // 경로 제거
          function removeRoute(routeId) {
            if (polylines[routeId]) {
              polylines[routeId].setMap(null);
              delete polylines[routeId];
              
              // 경로 제거 완료 메시지 전송
              sendMessage({ event: 'routeRemoved', routeId: routeId });
            }
          }
          
          // 모든 마커 제거
          function clearMarkers() {
            for (var id in markers) {
              markers[id].setMap(null);
            }
            markers = {};
            
            // 마커 제거 완료 메시지 전송
            sendMessage({ event: 'markersCleared' });
          }
          
          // 모든 경로 제거
          function clearRoutes() {
            for (var id in polylines) {
              polylines[id].setMap(null);
            }
            polylines = {};
            
            // 경로 제거 완료 메시지 전송
            sendMessage({ event: 'routesCleared' });
          }
          
          // 페이지 로드 완료 시 지도 초기화
          window.onload = initMap;
        </script>
      </body>
      </html>
    ''';
  }

  // 지도 로드
  Future<void> loadMap() async {
    try {
      if (!_isControllerInitialized) {
        await _initWebViewController();
      }

      // 이전 초기화 상태 리셋
      _isMapInitialized = false;

      // HTML 내용 로드
      await _controller.loadStringContent(_getKakaoMapHtml());
    } catch (e) {
      print('지도 로드 오류: $e');
      rethrow;
    }
  }

  // 경로 표시
  Future<void> displayRoute(RouteInfo routeInfo) async {
    try {
      await waitForInitialization();

      final routeColor = routeInfo.isAM ? '#3B71CA' : '#E43A45'; // 오전:파란색, 오후:빨간색

      // 포인트 목록 변환
      final pointsJson = jsonEncode(routeInfo.points
          .map((point) => {
                'lat': point.latitude,
                'lng': point.longitude,
              })
          .toList());

      // 경로선 그리기
      await _controller.executeScript('drawRoute(${routeInfo.routeId}, $pointsJson, "$routeColor");');

      // 마커 추가
      for (var point in routeInfo.points) {
        await addMarker(point);
      }
    } catch (e) {
      print('경로 표시 오류: $e');
    }
  }

  // 마커 추가
  Future<void> addMarker(RoutePoint point) async {
    try {
      await waitForInitialization();

      String pointType;
      switch (point.type) {
        case PointType.start:
          pointType = 'start';
          break;
        case PointType.end:
          pointType = 'end';
          break;
        default:
          pointType = 'waypoint';
      }

      await _controller.executeScript('addMarker("${point.name}_${DateTime.now().millisecondsSinceEpoch}", '
          '${point.latitude}, ${point.longitude}, "${point.name}", "$pointType");');
    } catch (e) {
      print('마커 추가 오류: $e');
    }
  }

  // 경로 제거
  Future<void> removeRoute(int routeId) async {
    try {
      await waitForInitialization();

      await _controller.executeScript('removeRoute($routeId);');
    } catch (e) {
      print('경로 제거 오류: $e');
    }
  }

  // 모든 경로 및 마커 제거
  Future<void> clearMap() async {
    try {
      await waitForInitialization();

      await _controller.executeScript('clearMarkers();');
      await _controller.executeScript('clearRoutes();');
    } catch (e) {
      print('지도 초기화 오류: $e');
    }
  }

  // 카카오 모빌리티 API를 사용한 경로 최적화 (실제 앱에서 구현 필요)
  Future<List<RoutePoint>> optimizeRoute(List<RoutePoint> points) async {
    // 이 부분은 실제 카카오 모빌리티 API 연동 필요
    // 현재는 더미 구현으로 원래 포인트를 그대로 반환
    return points;
  }

  // 지도 중심 이동
  Future<void> moveCenter(double lat, double lng, {int zoomLevel = 3}) async {
    try {
      await waitForInitialization();

      await _controller.executeScript('map.setCenter(new kakao.maps.LatLng($lat, $lng));'
          'map.setLevel($zoomLevel);');
    } catch (e) {
      print('지도 중심 이동 오류: $e');
    }
  }

  // 웹뷰에 메시지 보내기
  Future<void> sendMessageToWebView(Map<String, dynamic> data) async {
    try {
      await _controller.postWebMessage(jsonEncode(data));
    } catch (e) {
      print('메시지 전송 오류: $e');
    }
  }

  // 웹뷰 dispose
  Future<void> dispose() async {
    try {
      await _controller.dispose();
      _isMapInitialized = false;
      _isControllerInitialized = false;
    } catch (e) {
      print('WebView 종료 오류: $e');
    }
  }
}

// 디버그 모드 확인용
const bool kDebugMode = true;

// Completer 확장 - 완료 여부 확인
extension CompleterExtension<T> on Completer<T> {
  bool get isCompleted => this.isCompleted;
}
