import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:js' as js;

import '../models/route_point.dart';
import '../models/route_info.dart';

class KakaoMapWebService {
  static final KakaoMapWebService _instance = KakaoMapWebService._internal();
  factory KakaoMapWebService() => _instance;
  KakaoMapWebService._internal();

  // Kakao Developers에서 발급받은 JavaScript 앱 키
  static const String kakaoMapApiKey = '7261c06ab1f8493085156e1c60751ed4';

  bool _isMapInitialized = false;
  final List<Completer<void>> _pendingOperations = [];
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  String _mapElementId = 'kakao-map-container';

  // 메시지 스트림 가져오기
  Stream<String> get onMessage => _messageController.stream;

  // 지도 초기화 여부 확인
  bool get isMapInitialized => _isMapInitialized;

  // 웹 빌드에 필요한 JavaScript 통신 설정
  void _setupJavaScriptCommunication() {
    // 글로벌 콜백 함수 등록
    js.context['kakaoMapCallback'] = js.allowInterop((String message) {
      try {
        final data = jsonDecode(message);
        if (data['event'] == 'mapInitialized') {
          _completeInitialization();
        }
        _messageController.add(message);
      } catch (e) {
        print('메시지 처리 오류: $e');
      }
    });
  }

  // 지도 초기화 완료 처리
  void _completeInitialization() {
    if (_isMapInitialized) return;

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

  // 지도 초기화
  Future<void> initMap(String elementId) async {
    try {
      _mapElementId = elementId;

      // 이전 초기화 상태 리셋
      _isMapInitialized = false;

      // JavaScript 통신 설정
      _setupJavaScriptCommunication();

      // 카카오맵 SDK 스크립트 로드
      final kakaoMapScript = html.ScriptElement()
        ..src = 'https://dapi.kakao.com/v2/maps/sdk.js?appkey=$kakaoMapApiKey'
        ..type = 'text/javascript';

      html.document.head!.append(kakaoMapScript);

      // 스크립트 로드 완료 후 지도 초기화
      kakaoMapScript.onLoad.listen((event) {
        _initializeKakaoMap();
      });

      print('카카오맵 스크립트 로드 시작');
    } catch (e) {
      print('카카오맵 초기화 오류: $e');
      rethrow;
    }
  }

  // 카카오맵 초기화
  void _initializeKakaoMap() {
    try {
      // 카카오맵 초기화 JavaScript 코드 실행
      js.context.callMethod('eval', [
        '''
        // 콜백 함수 정의
        function sendToFlutter(data) {
          if (window.kakaoMapCallback) {
            window.kakaoMapCallback(JSON.stringify(data));
          }
        }
        
        // 지도 객체
        var map = null;
        // 마커 목록
        var markers = {};
        // 경로선 목록
        var polylines = {};
        
        // 지도 초기화
        kakao.maps.load(function() {
          try {
            // 지도 객체 생성
            var container = document.getElementById('$_mapElementId');
            var options = {
              center: new kakao.maps.LatLng(37.5666805, 126.9784147), // 서울시청
              level: 3
            };
            
            map = new kakao.maps.Map(container, options);
            
            // 클릭 이벤트 등록
            kakao.maps.event.addListener(map, 'click', function(mouseEvent) {
              sendToFlutter({
                event: 'mapClicked',
                lat: mouseEvent.latLng.getLat(),
                lng: mouseEvent.latLng.getLng()
              });
            });
            
            // 초기화 완료 메시지 전송
            sendToFlutter({ event: 'mapInitialized' });
          } catch (e) {
            console.error('카카오맵 초기화 오류:', e);
            sendToFlutter({ 
              event: 'error', 
              message: '카카오맵 초기화 오류: ' + e.message 
            });
          }
        });
        
        // 마커 추가 함수
        window.addMarker = function(lat, lng, label, type) {
          if (!map) return;
          
          try {
            var markerId = 'marker_' + label + '_' + Date.now();
            var position = new kakao.maps.LatLng(lat, lng);
            
            // 마커 이미지 설정
            var imageSrc, imageSize, imageOption;
            
            if (type === 'start') {
              imageSrc = 'https://t1.daumcdn.net/localimg/localimages/07/mapapidoc/red_b.png';
              imageSize = new kakao.maps.Size(50, 45);
              imageOption = { offset: new kakao.maps.Point(15, 43) };
            } else if (type === 'end') {
              imageSrc = 'https://t1.daumcdn.net/localimg/localimages/07/mapapidoc/blue_b.png';
              imageSize = new kakao.maps.Size(50, 45);
              imageOption = { offset: new kakao.maps.Point(15, 43) };
            } else {
              imageSrc = 'https://t1.daumcdn.net/localimg/localimages/07/mapapidoc/marker_number_blue.png';
              imageSize = new kakao.maps.Size(36, 37);
              imageOption = { offset: new kakao.maps.Point(13, 37) };
            }
            
            var markerImage = new kakao.maps.MarkerImage(imageSrc, imageSize, imageOption);
            
            // 마커 생성
            var marker = new kakao.maps.Marker({
              position: position,
              image: markerImage,
              map: map,
              title: label
            });
            
            // 인포윈도우 생성
            var infoWindow = new kakao.maps.InfoWindow({
              content: '<div style="padding:5px;font-size:12px;">' + label + '</div>',
              removable: true
            });
            
            // 클릭 이벤트 등록
            kakao.maps.event.addListener(marker, 'click', function() {
              infoWindow.open(map, marker);
            });
            
            // 마커 저장
            markers[markerId] = {
              marker: marker,
              infoWindow: infoWindow
            };
            
            return markerId;
          } catch (e) {
            console.error('마커 추가 오류:', e);
            sendToFlutter({ 
              event: 'error', 
              message: '마커 추가 오류: ' + e.message 
            });
          }
        };
        
        // 경로 그리기 함수
        window.drawRoute = function(routeId, pointsJson, color) {
          if (!map) return;
          
          try {
            // 기존 경로선 제거
            if (polylines[routeId]) {
              polylines[routeId].setMap(null);
              delete polylines[routeId];
            }
            
            var points = JSON.parse(pointsJson);
            var linePath = [];
            
            for (var i = 0; i < points.length; i++) {
              var point = points[i];
              linePath.push(new kakao.maps.LatLng(point.lat, point.lng));
            }
            
            // 경로선 생성
            var polyline = new kakao.maps.Polyline({
              path: linePath,
              strokeWeight: 5,
              strokeColor: color,
              strokeOpacity: 0.7,
              strokeStyle: 'solid'
            });
            
            polyline.setMap(map);
            
            // 경로선 저장
            polylines[routeId] = polyline;
            
            // 경로 범위로 지도 조정
            if (linePath.length > 0) {
              var bounds = new kakao.maps.LatLngBounds();
              for (var i = 0; i < linePath.length; i++) {
                bounds.extend(linePath[i]);
              }
              map.setBounds(bounds);
            }
          } catch (e) {
            console.error('경로 그리기 오류:', e);
            sendToFlutter({ 
              event: 'error', 
              message: '경로 그리기 오류: ' + e.message 
            });
          }
        };
        
        // 모든 마커 제거
        window.clearMarkers = function() {
          if (!map) return;
          
          try {
            for (var id in markers) {
              markers[id].marker.setMap(null);
              markers[id].infoWindow.close();
            }
            markers = {};
          } catch (e) {
            console.error('마커 제거 오류:', e);
            sendToFlutter({ 
              event: 'error', 
              message: '마커 제거 오류: ' + e.message 
            });
          }
        };
        
        // 모든 경로선 제거
        window.clearRoutes = function() {
          if (!map) return;
          
          try {
            for (var id in polylines) {
              polylines[id].setMap(null);
            }
            polylines = {};
          } catch (e) {
            console.error('경로선 제거 오류:', e);
            sendToFlutter({ 
              event: 'error', 
              message: '경로선 제거 오류: ' + e.message 
            });
          }
        };
        
        // 지도 중심 이동
        window.moveCenter = function(lat, lng, zoomLevel) {
          if (!map) return;
          
          try {
            map.setCenter(new kakao.maps.LatLng(lat, lng));
            map.setLevel(zoomLevel);
          } catch (e) {
            console.error('지도 중심 이동 오류:', e);
            sendToFlutter({ 
              event: 'error', 
              message: '지도 중심 이동 오류: ' + e.message 
            });
          }
        };
      '''
      ]);

      print('카카오맵 초기화 JavaScript 실행 완료');
    } catch (e) {
      print('카카오맵 JavaScript 실행 오류: $e');
    }
  }

  // 지도 로드
  Future<void> loadMap() async {
    // 이미 초기화됨
    print('카카오맵 로드 중...');
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

      // JavaScript 함수 호출
      js.context.callMethod('addMarker', [point.latitude, point.longitude, point.name, pointType]);
    } catch (e) {
      print('마커 추가 오류: $e');
    }
  }

  // 경로 표시
  Future<void> displayRoute(RouteInfo routeInfo) async {
    try {
      await waitForInitialization();

      final routeColor = routeInfo.isAM ? '#2196F3' : '#F44336'; // 오전:파란색, 오후:빨간색

      // 포인트 목록 변환
      final pointsJson = jsonEncode(routeInfo.points
          .map((point) => {
                'lat': point.latitude,
                'lng': point.longitude,
              })
          .toList());

      // JavaScript 함수 호출
      js.context.callMethod('drawRoute', [routeInfo.routeId, pointsJson, routeColor]);

      // 마커 추가
      for (var point in routeInfo.points) {
        await addMarker(point);
      }
    } catch (e) {
      print('경로 표시 오류: $e');
    }
  }

  // 경로 제거
  Future<void> removeRoute(int routeId) async {
    try {
      await waitForInitialization();

      js.context.callMethod('removeRoute', [routeId]);
    } catch (e) {
      print('경로 제거 오류: $e');
    }
  }

  // 모든 경로 및 마커 제거
  Future<void> clearMap() async {
    try {
      await waitForInitialization();

      js.context.callMethod('clearMarkers', []);
      js.context.callMethod('clearRoutes', []);
    } catch (e) {
      print('지도 초기화 오류: $e');
    }
  }

  // 경로 최적화 (실제 앱에서는 카카오 API 활용)
  Future<List<RoutePoint>> optimizeRoute(List<RoutePoint> points) async {
    // 더미 구현으로 원래 포인트를 그대로 반환
    return points;
  }

  // 지도 중심 이동
  Future<void> moveCenter(double lat, double lng, {int zoomLevel = 10}) async {
    try {
      await waitForInitialization();

      js.context.callMethod('moveCenter', [lat, lng, zoomLevel]);
    } catch (e) {
      print('지도 중심 이동 오류: $e');
    }
  }

  // 현재 URL 확인
  String getCurrentUrl() {
    try {
      return html.window.location.href;
    } catch (e) {
      print('URL 확인 오류: $e');
      return 'Error: $e';
    }
  }

  // 웹뷰 dispose
  Future<void> dispose() async {
    try {
      _isMapInitialized = false;
    } catch (e) {
      print('지도 종료 오류: $e');
    }
  }
}
