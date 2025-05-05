import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:universal_html/html.dart' as html;
import 'package:get/get.dart';
import 'dart:js' as js;

import '../models/route_point.dart';
import '../models/route_info.dart';
import '../controllers/synology_controller.dart';

class NaverMapWebService {
  static final NaverMapWebService _instance = NaverMapWebService._internal();
  factory NaverMapWebService() => _instance;
  NaverMapWebService._internal();

  // SynologyController에서 클라이언트 ID 가져오기
  String get _naverMapClientId => Get.find<SynologyController>().naverClientId;

  bool _isMapInitialized = false;
  final List<Completer<void>> _pendingOperations = [];
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  String _mapElementId = 'naver-map-container';

  // 메시지 스트림 가져오기
  Stream<String> get onMessage => _messageController.stream;

  // 지도 초기화 여부 확인
  bool get isMapInitialized => _isMapInitialized;

  // 웹 빌드에 필요한 JavaScript 통신 설정
  void _setupJavaScriptCommunication() {
    // 글로벌 콜백 함수 등록
    js.context['naverMapCallback'] = js.allowInterop((String message) {
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

      // 클라이언트 ID 유효성 확인
      if (_naverMapClientId.isEmpty) {
        throw Exception('네이버 클라이언트 ID가 설정되지 않았습니다. 시놀로지 NAS 연결을 확인하세요.');
      }

      print('네이버 클라이언트 ID: $_naverMapClientId');

      // 네이버맵 SDK 스크립트 로드
      final naverMapScript = html.ScriptElement()
        ..src = 'https://openapi.map.naver.com/openapi/v3/maps.js?ncpClientId=$_naverMapClientId'
        ..type = 'text/javascript';

      html.document.head!.append(naverMapScript);

      // 스크립트 로드 완료 후 지도 초기화
      naverMapScript.onLoad.listen((event) {
        _initializeNaverMap();
      });

      print('네이버 지도 스크립트 로드 시작');
    } catch (e) {
      print('네이버 지도 초기화 오류: $e');
      rethrow;
    }
  }

  // 네이버 지도 초기화
  void _initializeNaverMap() {
    try {
      // 네이버 지도 초기화 JavaScript 코드 실행
      js.context.callMethod('eval', [
        '''
        // 콜백 함수 정의
        function sendToFlutter(data) {
          if (window.naverMapCallback) {
            window.naverMapCallback(JSON.stringify(data));
          }
        }
        
        // 지도 객체
        var map = null;
        // 마커 목록
        var markers = {};
        // 경로선 목록
        var polylines = {};
        
        try {
          // 지도 객체 생성
          var container = document.getElementById('$_mapElementId');
          var options = {
            center: new naver.maps.LatLng(37.5666805, 126.9784147), // 서울시청
            zoom: 10,
            mapTypeId: naver.maps.MapTypeId.NORMAL
          };
          
          map = new naver.maps.Map(container, options);
          
          // 클릭 이벤트 등록
          naver.maps.Event.addListener(map, 'click', function(e) {
            sendToFlutter({
              event: 'mapClicked',
              lat: e.coord.lat(),
              lng: e.coord.lng()
            });
          });
          
          // 초기화 완료 메시지 전송
          sendToFlutter({ event: 'mapInitialized' });
          
          console.log('네이버 지도 초기화 완료');
        } catch (e) {
          console.error('네이버 지도 초기화 오류:', e);
          sendToFlutter({ 
            event: 'error', 
            message: '네이버 지도 초기화 오류: ' + e.message 
          });
        }
        
        // 마커 추가 함수
        window.addNaverMarker = function(lat, lng, label, type) {
          if (!map) return;
          
          try {
            var markerId = 'marker_' + label + '_' + Date.now();
            var position = new naver.maps.LatLng(lat, lng);
            
            // 마커 옵션 설정
            var markerOptions = {
              position: position,
              map: map,
              title: label
            };
            
            // 마커 타입에 따른 아이콘 설정
            if (type === 'start') {
              markerOptions.icon = {
                content: '<div style="width:24px;height:24px;background-color:green;border-radius:50%;display:flex;justify-content:center;align-items:center;color:white;font-weight:bold;">S</div>',
                anchor: new naver.maps.Point(12, 12)
              };
            } else if (type === 'end') {
              markerOptions.icon = {
                content: '<div style="width:24px;height:24px;background-color:red;border-radius:50%;display:flex;justify-content:center;align-items:center;color:white;font-weight:bold;">E</div>',
                anchor: new naver.maps.Point(12, 12)
              };
            } else {
              markerOptions.icon = {
                content: '<div style="width:20px;height:20px;background-color:blue;border-radius:50%;display:flex;justify-content:center;align-items:center;color:white;font-size:10px;">●</div>',
                anchor: new naver.maps.Point(10, 10)
              };
            }
            
            // 마커 생성
            var marker = new naver.maps.Marker(markerOptions);
            
            // 정보창 생성
            var infoWindow = new naver.maps.InfoWindow({
              content: '<div style="padding:10px;min-width:100px;">' + label + '</div>',
              borderWidth: 1,
              borderColor: '#888',
              backgroundColor: 'white'
            });
            
            // 클릭 이벤트 등록
            naver.maps.Event.addListener(marker, 'click', function() {
              if (infoWindow.getMap()) {
                infoWindow.close();
              } else {
                infoWindow.open(map, marker);
              }
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
        window.drawNaverRoute = function(routeId, pointsJson, color) {
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
              linePath.push(new naver.maps.LatLng(point.lat, point.lng));
            }
            
            // 경로선 생성
            var polyline = new naver.maps.Polyline({
              path: linePath,
              strokeWeight: 5,
              strokeColor: color,
              strokeOpacity: 0.7,
              map: map
            });
            
            // 경로선 저장
            polylines[routeId] = polyline;
            
            // 경로 범위로 지도 조정
            if (linePath.length > 0) {
              var bounds = new naver.maps.LatLngBounds();
              for (var i = 0; i < linePath.length; i++) {
                bounds.extend(linePath[i]);
              }
              map.fitBounds(bounds);
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
        window.clearNaverMarkers = function() {
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
        window.clearNaverRoutes = function() {
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
        window.moveNaverCenter = function(lat, lng, zoomLevel) {
          if (!map) return;
          
          try {
            map.setCenter(new naver.maps.LatLng(lat, lng));
            map.setZoom(zoomLevel);
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

      print('네이버 지도 초기화 JavaScript 실행 완료');
    } catch (e) {
      print('네이버 지도 JavaScript 실행 오류: $e');
    }
  }

  // 지도 로드
  Future<void> loadMap() async {
    // 이미 초기화됨
    print('네이버 지도 로드 중...');
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
      js.context.callMethod('addNaverMarker', [point.latitude, point.longitude, point.name, pointType]);
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
      js.context.callMethod('drawNaverRoute', [routeInfo.routeId, pointsJson, routeColor]);

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

      // '해당 ID의 경로선만 제거' 기능은 구현되어 있지 않음
      // 전체 경로를 지우고 남은 경로를 다시 그리는 방식으로 처리
    } catch (e) {
      print('경로 제거 오류: $e');
    }
  }

  // 모든 경로 및 마커 제거
  Future<void> clearMap() async {
    try {
      await waitForInitialization();

      js.context.callMethod('clearNaverMarkers', []);
      js.context.callMethod('clearNaverRoutes', []);
    } catch (e) {
      print('지도 초기화 오류: $e');
    }
  }

  // 경로 최적화 (실제 앱에서는 네이버 API 활용)
  Future<List<RoutePoint>> optimizeRoute(List<RoutePoint> points) async {
    // 더미 구현으로 원래 포인트를 그대로 반환
    return points;
  }

  // 지도 중심 이동
  Future<void> moveCenter(double lat, double lng, {int zoomLevel = 10}) async {
    try {
      await waitForInitialization();

      js.context.callMethod('moveNaverCenter', [lat, lng, zoomLevel]);
    } catch (e) {
      print('지도 중심 이동 오류: $e');
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

  // 현재 URL 확인
  String getCurrentUrl() {
    try {
      return html.window.location.href;
    } catch (e) {
      print('URL 확인 오류: $e');
      return 'Error: $e';
    }
  }
}
