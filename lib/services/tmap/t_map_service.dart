import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_application_kimpoedu_shuttlebus_manager/services/local_web_server.dart';
import 'package:webview_windows/webview_windows.dart';
import 'dart:async';
import 'package:get/get.dart';
import 'dart:math';

import '../../models/route_point.dart';
import '../../models/route_info.dart';
import '../../controllers/synology_controller.dart';

class TMapService {
  static final TMapService _instance = TMapService._internal();
  factory TMapService() => _instance;
  TMapService._internal();

  // SynologyController에서 클라이언트 ID 가져오기
  String get _tmapClientId => Get.find<SynologyController>().tmapClientId;

  final WebviewController _controller = WebviewController();
  bool _isMapInitialized = false;
  bool _isControllerInitialized = false;
  final List<Completer<void>> _pendingOperations = [];
  final StreamController<Map<String, dynamic>> _messageController = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _messageSubscription;
  final Map<String, Completer<List<Map<String, dynamic>>>> _searchCompleters = {};
  final Map<String, Completer<Map<String, dynamic>>> _optimizationCompleters = {};

  // 지도 초기화 여부 확인
  bool get isMapInitialized => _isMapInitialized;

  // 컨트롤러 가져오기
  WebviewController get controller => _controller;

  // 메시지 스트림을 외부에 제공하는 getter
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // 컨트롤러 초기화
  Future<void> _initWebViewController() async {
    if (_isControllerInitialized) return;

    try {
      // 클라이언트 ID 유효성 확인
      if (_tmapClientId.isEmpty) {
        throw Exception('티맵 클라이언트 ID가 설정되지 않았습니다. 시놀로지 NAS 연결을 확인하세요.');
      }
      await _controller.initialize();
      // 웹뷰 설정
      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      // 메시지 수신 설정 (한 번만 설정)
      _messageSubscription = _controller.webMessage.listen((event) {
        try {
          final data = jsonDecode(event);
          // 콘솔 로그 처리
          if (data['event'] == 'console') {
            if (data['type'] == 'log') {
              print('WebView 콘솔 로그: ${data['message']}');
            } else if (data['type'] == 'error') {
              print('WebView 콘솔 에러: ${data['message']}');
            }
          }
          // 지도 초기화 완료 이벤트 처리
          else if (data['event'] == 'mapInitialized') {
            _completeInitialization();
          }
          // 검색 완료 이벤트 처리
          else if (data['event'] == 'searchComplete') {
            _handleSearchComplete(data);
          }
          // 경로 최적화 완료 이벤트 처리
          else if (data['event'] == 'optimizationComplete') {
            _handleOptimizationComplete(data);
          }

          // 스트림을 통해 메시지 브로드캐스트
          _messageController.add(data);
        } catch (e) {
          print('메시지 처리 오류: $e');
        }
      });

      _isControllerInitialized = true;
      print('웹 컨트롤러 초기화 완료');
    } catch (e) {
      print('웹 컨트롤러 초기화 오류: $e');
      _isControllerInitialized = false;
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

  // 지도 초기화 대기 - 타임아웃 추가
  Future<void> waitForInitialization({Duration timeout = const Duration(seconds: 30)}) async {
    if (_isMapInitialized) {
      print('지도가 이미 초기화되어 있습니다.');
      return;
    }

    print('지도 초기화 대기 시작...');
    final completer = Completer<void>();
    _pendingOperations.add(completer);

    // 타임아웃 추가
    Future.delayed(timeout, () {
      if (!completer.isCompleted) {
        print('지도 초기화 타임아웃 발생 (${timeout.inSeconds}초)');

        // 디버깅 정보 출력
        _controller.executeScript('console.log("DEBUG: 현재 지도 상태", typeof Tmapv3, typeof Tmapv3?.Map)').then((value) {
          print('지도 디버깅 정보: $value');
        }).catchError((e) {
          print('지도 디버깅 정보 가져오기 실패: $e');
        });

        // 자동으로 지도 리로드 시도
        try {
          print('지도 자동 리로드 시도...');
          loadMap();
        } catch (e) {
          print('지도 자동 리로드 실패: $e');
        }

        completer.completeError('지도 초기화 타임아웃');
      }
    });

    return completer.future;
  }

  // 지도 로드 - API 키를 포함한 HTML 템플릿 사용
  Future<void> loadMap() async {
    try {
      if (!_isControllerInitialized) {
        await _initWebViewController();
      }

      // 이전 초기화 상태 리셋
      _isMapInitialized = false;

      // 대기 중인 작업들 취소
      for (var completer in _pendingOperations) {
        if (!completer.isCompleted) {
          completer.completeError('지도 다시 로드로 인한 취소');
        }
      }
      _pendingOperations.clear();

      // 클라이언트 ID 유효성 확인
      if (_tmapClientId.isEmpty) {
        throw Exception('티맵 클라이언트 ID가 설정되지 않았습니다. 시놀로지 NAS 연결을 확인하세요.');
      }

      // 로컬 웹 서버가 실행 중인지 확인하고 필요시 시작
      final webServer = LocalWebServer();
      if (!webServer.isRunning) {
        await webServer.startServer(_tmapClientId);
      }

      if (webServer.serverUrl == null) {
        throw Exception('웹 서버를 시작할 수 없습니다');
      }

      final url = '${webServer.serverUrl}/t_map.html';
      print('TMap HTML 로드: $url');
      await _controller.loadUrl(url);

      print('지도 로드 완료. 초기화 대기 중...');
    } catch (e) {
      print('지도 로드 오류: $e');
      rethrow;
    }
  }

  // 마커 추가 - 필요한 함수 로드 후 실행
  Future<void> addMarker(RoutePoint point, int count) async {
    try {
      await waitForInitialization();

      await _controller.executeScript('addMarker("${point.id}", "${point.name}", ${point.longitude}, ${point.latitude}, "${point.type}", $count);');
    } catch (e) {
      print('마커 추가 오류: $e');
    }
  }

  // 마커 삭제
  Future<void> removeMarker(String id) async {
    try {
      await waitForInitialization();

      print('마커 삭제: id=$id');
      await _controller.executeScript('removeMarker("$id");');
    } catch (e) {
      print('마커 삭제 오류: $e');
      rethrow;
    }
  }

  // 모든 마커 삭제
  Future<void> clearAllMarkers() async {
    try {
      await waitForInitialization();
      await _controller.executeScript('clearMarkers();');
    } catch (e) {
      print('모든 마커 삭제 오류: $e');
    }
  }

  // 경로선 그리기
  Future<void> drawRoute(String id, List<Map<String, dynamic>> coordinates, String color, int width) async {
    try {
      await waitForInitialization();
      return;
      // JSON 문자열로 변환
      final coordsJson = jsonEncode(coordinates);

      await _controller.executeScript('''
        drawRoute('$id', $coordsJson, '$color', $width);
      ''');

      print('경로선 그리기: id=$id, 좌표 개수=${coordinates.length}');
    } catch (e) {
      print('경로선 그리기 오류: $e');
      rethrow;
    }
  }

  // 경로 제거 (함수 직접 실행 방식)
  Future<void> removeRoute(String routeId) async {
    try {
      await waitForInitialization();

      await _controller.executeScript('''
        try {
          if (routes['$routeId']) {
            routes['$routeId'].setMap(null);
            delete routes['$routeId'];
            console.log('경로 제거 성공: $routeId');
          } else {
            console.log('제거할 경로를 찾을 수 없음: $routeId');
          }
        } catch (error) {
          console.error('경로 제거 오류:', error);
        }
      ''');

      print('경로 제거: id=$routeId');
    } catch (e) {
      print('경로 제거 오류: $e');
      rethrow;
    }
  }

  // 모든 경로 및 마커 제거 (함수 직접 실행 방식)
  Future<void> clearMap() async {
    try {
      await waitForInitialization();

      // 모든 마커 제거 - 함수 정의 대신 직접 코드 실행
      await _controller.executeScript('''
        try {
          for (const id in markers) {
            markers[id].setMap(null);
          }
          markers = {};
          console.log('모든 마커 제거됨');
        } catch (error) {
          console.error('모든 마커 제거 오류:', error);
        }
      ''');

      // 모든 경로선 제거 - 함수 정의 대신 직접 코드 실행
      await _controller.executeScript('''
        try {
          for (const id in routes) {
            routes[id].setMap(null);
          }
          routes = {};
          console.log('모든 경로선 제거됨');
        } catch (error) {
          console.error('모든 경로선 제거 오류:', error);
        }
      ''');
    } catch (e) {
      print('지도 초기화 오류: $e');
    }
  }

  // 특정 위치로 지도 이동 (함수 직접 실행 방식)
  Future<void> moveToLocation(double lat, double lng, int zoomLevel) async {
    try {
      await waitForInitialization();

      await _controller.executeScript('''
        try {
          if (!map) {
            throw new Error('지도가 초기화되지 않았습니다.');
          }
          
          const position = new Tmapv3.LatLng($lat, $lng);
          map.setCenter(position);
          
          if ($zoomLevel) {
            map.setZoom($zoomLevel);
          }
          
          console.log('지도 위치 이동 성공: $lat, $lng, 줌레벨: $zoomLevel');
        } catch (error) {
          console.error('지도 위치 이동 오류:', error);
        }
      ''');

      print('지도 위치 이동: lat=$lat, lng=$lng, zoom=$zoomLevel');
    } catch (e) {
      print('지도 이동 오류: $e');
      rethrow;
    }
  }

  // 위치 검색 - 티맵 지도 API의 주소 검색 서비스 사용
  Future<List<Map<String, dynamic>>> searchLocation(String query) async {
    try {
      if (query.isEmpty) return [];

      await waitForInitialization();

      // 검색 ID 생성
      final searchId = 'search_${DateTime.now().millisecondsSinceEpoch}';

      // Completer 생성 및 저장
      final completer = Completer<List<Map<String, dynamic>>>();
      _searchCompleters[searchId] = completer;

      // 검색 JavaScript 실행 - 함수 호출 대신 직접 코드 실행
      await _controller.executeScript('''
        searchLocation("$searchId", "$query");
      ''');

      // 결과 대기 (최대 10초)
      final results = await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
        print('검색 타임아웃: $query');
        _searchCompleters.remove(searchId);
        return [];
      });

      return results;
    } catch (e) {
      print('위치 검색 오류: $e');
      return []; // 오류 발생 시 빈 목록 반환
    }
  }

  // 경로 표시 (함수 직접 실행 방식)
  Future<void> displayRoute(RouteInfo routeInfo) async {
    try {
      await waitForInitialization();

      final routeColor = routeInfo.isAM ? '#2196F3' : '#F44336'; // 오전:파란색, 오후:빨간색
      const routeWidth = 4; // 선 두께

      // 포인트 목록 변환
      final pointsJson = jsonEncode(routeInfo.points
          .map((point) => {
                'lat': point.latitude,
                'lng': point.longitude,
              })
          .toList());

      // 경로선 그리기 - 함수 직접 실행
      await _controller.executeScript('''
        try {
          if (!map) {
            throw new Error('지도가 초기화되지 않았습니다.');
          }
          
          const coordinates = $pointsJson;
          
          // 이미 같은 ID의 경로가 있으면 제거
          if (routes['${routeInfo.routeId}']) {
            routes['${routeInfo.routeId}'].setMap(null);
          }
          
          // 경로 좌표 배열 생성
          const path = coordinates.map(coord => new Tmapv3.LatLng(coord.lat, coord.lng));
          
          // 경로선 생성
          const polyline = new Tmapv3.Polyline({
            path: path,
            strokeColor: "$routeColor",
            strokeWeight: $routeWidth,
            map: map
          });
          
          // 경로 저장
          routes['${routeInfo.routeId}'] = polyline;
          
          console.log('경로 그리기 성공: ${routeInfo.routeId}, 좌표 수: ' + coordinates.length);
        } catch (error) {
          console.error('경로 그리기 오류:', error);
        }
      ''');

      // 마커 추가
      for (var point in routeInfo.points) {
        await addMarker(point, routeInfo.points.indexOf(point) + 1);
      }
    } catch (e) {
      print('경로 표시 오류: $e');
    }
  }

  // 경로 최적화 API 호출
  Future<Map<String, dynamic>> optimizeRoute(List<RoutePoint> points) async {
    if (points.length < 2) {
      throw Exception('경로 최적화에는 최소 출발지와 도착지가 필요합니다');
    }

    try {
      await waitForInitialization();

      // 출발지와 도착지 분리
      RoutePoint startPoint = points.first;
      RoutePoint endPoint = points.last;
      for (var point in points) {
        if (point.type == 'start') {
          startPoint = point;
        } else if (point.type == 'end') {
          endPoint = point;
        }
      }

      // 중간 경유지 목록 생성 (출발지와 도착지 제외)
      final viaPoints = points.where((point) => point.type != 'start' && point.type != 'end').toList();

      // API 요청용 JSON 데이터 생성
      final requestData = {
        "reqCoordType": "WGS84GEO",
        "resCoordType": "WGS84GEO", // 응답도 WGS84 좌표계로 받기
        "startName": startPoint.name,
        "startX": startPoint.longitude.toString(),
        "startY": startPoint.latitude.toString(),
        "startTime": _getCurrentTimeString(),
        "endName": endPoint.name,
        "endX": endPoint.longitude.toString(),
        "endY": endPoint.latitude.toString(),
        "searchOption": "0", // 최적화 옵션: 0-최단거리, 1-최적경로
        "viaPoints": viaPoints
            .map((point) => {
                  "viaPointId": point.id,
                  "viaPointName": point.name,
                  "viaX": point.longitude.toString(),
                  "viaY": point.latitude.toString(),
                })
            .toList()
      };

      // WebView에서 경로 최적화 API 호출
      final optimizationId = 'optimization_${DateTime.now().millisecondsSinceEpoch}';
      final completer = Completer<Map<String, dynamic>>();

      // Completer 등록
      _optimizationCompleters[optimizationId] = completer;

      // 스크립트에 JSON 문자열을 전달하여 실행
      await _controller.executeScript('''
        try {
          optimizeRoute('$optimizationId', ${jsonEncode(requestData)});
        } catch(error) {
          console.error('경로 최적화 호출 오류:', error);
          window.chrome.webview.postMessage({
            event: 'optimizationComplete',
            optimizationId: '$optimizationId',
            error: error.toString()
          });
        }
      ''');

      // 최적화 결과 대기 (최대 30초)
      final resultData = await completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
        _optimizationCompleters.remove(optimizationId);
        throw TimeoutException('경로 최적화 시간 초과');
      });

      // 결과 처리 및 경로 그리기
      await _processRouteOptimizationResult(resultData);

      return resultData;
    } catch (e) {
      print('경로 최적화 오류: $e');
      throw Exception('경로 최적화 실패: $e');
    }
  }

  // 경로 최적화 결과 처리 및 지도에 표시
  Future<void> _processRouteOptimizationResult(Map<String, dynamic> resultData) async {
    try {
      if (!resultData.containsKey('features')) {
        throw Exception('유효하지 않은 경로 결과 데이터');
      }

      // 경로 정보 추출
      final properties = resultData['properties'];
      final features = resultData['features'] as List;

      // 기존 경로 삭제
      await _controller.executeScript('''
        // 기존 경로 제거
        for (const id in routes) {
          routes[id].setMap(null);
        }
        routes = {};
      ''');

      // 최적화된 순서대로 경로 정보 생성
      List<List<Map<String, double>>> allCoordinates = [];

      // 경로 세그먼트 추출
      for (var feature in features) {
        final geometry = feature['geometry'];

        if (geometry['type'] == 'LineString') {
          final List coordinates = geometry['coordinates'];
          List<Map<String, double>> pathCoordinates = [];

          for (var coord in coordinates) {
            // EPSG3857에서 WGS84로 변환 (필요한 경우)
            if (resultData['properties']['resCoordType'] == 'EPSG3857') {
              await _controller.executeScript('''
                const point = new Tmapv3.Point(${coord[0]}, ${coord[1]});
                const convertPoint = new Tmapv3.Projection.convertEPSG3857ToWGS84GEO(point);
                console.log("변환된 좌표:", convertPoint._lat, convertPoint._lng);
              ''');

              // 여기서는 응답 좌표계를 WGS84GEO로 요청했으므로 변환 필요 없음
            }

            pathCoordinates.add({
              'lat': coord[1].toDouble(),
              'lng': coord[0].toDouble(),
            });
          }

          allCoordinates.add(pathCoordinates);
        }
      }

      // 모든 경로 세그먼트 그리기
      for (int i = 0; i < allCoordinates.length; i++) {
        final pathCoordinates = allCoordinates[i];
        final routeId = 'optimized_route_$i';

        // 경로 색상 랜덤 생성 (구간별 구분을 위해)
        final color = '#${((1 << 24) * (Random().nextDouble())).floor().toRadixString(16).padLeft(6, '0')}';

        // 지도에 경로 그리기
        await _controller.executeScript('''
          try {
            const path = ${jsonEncode(pathCoordinates)}.map(
              coord => new Tmapv3.LatLng(coord.lat, coord.lng)
            );
            
            const polyline = new Tmapv3.Polyline({
              path: path,
              strokeColor: "$color",
              strokeWeight: 5,
              map: map
            });
            
            routes['$routeId'] = polyline;
            console.log('경로 세그먼트 $i 그리기 완료 (${pathCoordinates.length}개 지점)');
          } catch (error) {
            console.error('경로 그리기 오류:', error);
          }
        ''');
      }

      // 총 거리, 시간, 요금 정보 콘솔에 출력
      final totalDistance = (properties['totalDistance'] / 1000).toStringAsFixed(1);
      final totalTime = (properties['totalTime'] / 60).toStringAsFixed(0);
      final totalFare = properties['totalFare'];

      print('경로 최적화 완료: 총 거리 ${totalDistance}km, 총 시간 $totalTime분, 총 요금 $totalFare원');

      // 경유지 최적화 순서 반환
      final List<String> optimizedOrder = properties['viaPointOptimizationResult']?.map<String>((v) => v['viaPointId'].toString())?.toList() ?? [];
      print('최적화된 경유지 순서: $optimizedOrder');
    } catch (e) {
      print('경로 결과 처리 오류: $e');
      throw Exception('경로 결과 처리 실패: $e');
    }
  }

  // 현재 시간을 TMap API 형식(YYYYMMDDHHmm)으로 변환
  String _getCurrentTimeString() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  }

  // 웹뷰 dispose
  Future<void> dispose() async {
    try {
      await _controller.dispose();
      _isMapInitialized = false;
      _isControllerInitialized = false;
      _messageSubscription?.cancel();
      _messageController.close();
      _searchCompleters.clear();
      _optimizationCompleters.clear();
    } catch (e) {
      print('WebView 종료 오류: $e');
    }
  }

  // 검색 완료 이벤트 처리 메서드
  void _handleSearchComplete(Map<String, dynamic> data) {
    final searchId = data['searchId'] as String?;

    print('검색 완료 이벤트 수신: (ID: $searchId)');

    // 해당 검색 ID에 대한 completer 찾기
    final completer = _searchCompleters[searchId];
    if (completer != null && !completer.isCompleted) {
      if (data['error'] != null) {
        print('검색 오류: ${data['error']}');
        completer.complete([]);
      } else {
        // 결과 변환
        final results = (data['results'] as List?)?.map((item) {
              return Map<String, dynamic>.from(item);
            }).toList() ??
            [];

        print('검색 결과 수신: ${results.length}개 항목');
        completer.complete(results);
      }
      // 완료된 completer 제거
      _searchCompleters.remove(searchId);
    }
  }

  // 경로 최적화 완료 이벤트 처리 메서드
  void _handleOptimizationComplete(Map<String, dynamic> data) {
    final optimizationId = data['optimizationId'] as String?;

    print('경로 최적화 완료 이벤트 수신: (ID: $optimizationId)');

    // 해당 최적화 ID에 대한 completer 찾기
    final completer = _optimizationCompleters[optimizationId];
    if (completer != null && !completer.isCompleted) {
      if (data['error'] != null) {
        print('최적화 오류: ${data['error']}');
        completer.completeError(data['error']);
      } else {
        completer.complete(data['result']);
      }
      // 완료된 completer 제거
      _optimizationCompleters.remove(optimizationId);
    }
  }
}

// Completer 확장 - 완료 여부 확인
extension CompleterExtension<T> on Completer<T> {
  bool get isCompleted => this.isCompleted;
}
