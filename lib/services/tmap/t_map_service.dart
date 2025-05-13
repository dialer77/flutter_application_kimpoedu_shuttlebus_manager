import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_application_kimpoedu_shuttlebus_manager/services/local_web_server.dart';
import 'package:flutter_application_kimpoedu_shuttlebus_manager/services/route_manager.dart';
import 'package:webview_windows/webview_windows.dart';
import 'dart:async';
import 'package:get/get.dart';
import 'dart:math';
import 'package:http/http.dart' as http;

import '../../models/route_point.dart';
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
  Future<void> drawRoute(String routeId, List<Map<String, double>> coordinates, String color, int thickness) async {
    await _controller.executeScript('''
      try {
        const path = ${jsonEncode(coordinates)}.map(
          coord => new Tmapv3.LatLng(coord.lat, coord.lng)
        );
        
        const polyline = new Tmapv3.Polyline({
          path: path,
          strokeColor: "$color",
          strokeWeight: $thickness,
          map: map
        });
        
        routes['$routeId'] = polyline;
        console.log('경로 $routeId 그리기 완료 (${coordinates.length}개 지점)');
      } catch (error) {
        console.error('경로 그리기 오류:', error);
      }
    ''');
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
       clearMarkers()
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

  // 위치 검색 - HTTP API 직접 호출 방식으로 변경
  Future<List<Map<String, dynamic>>> searchLocation(String query) async {
    try {
      if (query.isEmpty) return [];

      // HTTP 클라이언트 생성
      final client = http.Client();

      try {
        // TMap API 엔드포인트 URL 설정
        final url = Uri.parse('https://apis.openapi.sk.com/tmap/pois?version=1&format=json&callback=result');

        // API 요청 헤더 설정
        final headers = {'appKey': _tmapClientId, 'Content-Type': 'application/json'};

        // API 요청 파라미터 설정
        final params = {
          'searchKeyword': query,
          'resCoordType': 'WGS84GEO', // WebView에서는 EPSG3857를 사용했지만 변환 불필요하도록 변경
          'reqCoordType': 'WGS84GEO',
          'count': '10'
        };

        // URL에 쿼리 파라미터 추가
        final requestUrl = Uri(scheme: url.scheme, host: url.host, path: url.path, queryParameters: {...url.queryParameters, ...params});

        print('TMap 위치 검색 API 호출: $requestUrl');

        // API 요청 보내기
        final response = await client.get(requestUrl, headers: headers);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          // 결과 데이터 파싱
          final results = <Map<String, dynamic>>[];

          if (data['searchPoiInfo'] != null && data['searchPoiInfo']['pois'] != null && data['searchPoiInfo']['pois']['poi'] != null) {
            final pois = data['searchPoiInfo']['pois']['poi'] as List;

            for (var poi in pois) {
              // 좌표 추출 (이미 WGS84GEO 좌표계로 요청했으므로 변환 불필요)
              final lat = double.tryParse(poi['noorLat'] ?? '0') ?? 0.0;
              final lng = double.tryParse(poi['noorLon'] ?? '0') ?? 0.0;

              results.add({'id': poi['id'] ?? '', 'name': poi['name'] ?? '', 'lat': lat, 'lng': lng, 'distance': double.tryParse(poi['radius'] ?? '0') ?? 0.0});
            }
          }

          print('위치 검색 결과: ${results.length}개 항목');
          return results;
        } else {
          print('TMap API 오류: ${response.statusCode}, ${response.body}');
          return [];
        }
      } finally {
        client.close();
      }
    } catch (e) {
      print('위치 검색 오류: $e');
      return []; // 오류 발생 시 빈 목록 반환
    }
  }

  // 경로 최적화 API 호출
  Future<Map<String, dynamic>> optimizeRoute(List<RoutePoint> points) async {
    if (points.length < 2) {
      throw Exception('경로 최적화에는 최소 출발지와 도착지가 필요합니다');
    }

    try {
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
        "resCoordType": "WGS84GEO", // 원래 JavaScript에서 사용하던 좌표계
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

      // HTTP 클라이언트 생성
      final client = http.Client();

      try {
        // 정확한 API 엔드포인트 설정 (routeOptimization20)
        final url = Uri.parse('https://apis.openapi.sk.com/tmap/routes/routeOptimization20?version=1&format=json');

        // 헤더 설정
        final headers = {'appKey': _tmapClientId, 'Content-Type': 'application/json'};

        print('TMap 경로 최적화 API 호출: $url');
        print('요청 데이터: ${jsonEncode(requestData)}');

        // POST 요청 전송
        final response = await client.post(url, headers: headers, body: jsonEncode(requestData));

        if (response.statusCode == 200) {
          // 응답 JSON 파싱
          final responseData = jsonDecode(response.body) as Map<String, dynamic>;

          print('경로 최적화 성공: ${response.statusCode}');

          // 최적화된 경로 순서 추출 및 routeManager 업데이트
          _updateRouteOrder(responseData, points, startPoint, endPoint, viaPoints);

          // 결과 처리 및 경로 그리기
          await _processRouteOptimizationResult(responseData);

          return responseData;
        } else {
          print('TMap API 오류: ${response.statusCode}, ${response.body}');
          throw Exception('경로 최적화 API 오류: ${response.statusCode}');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      print('경로 최적화 오류: $e');
      throw Exception('경로 최적화 실패: $e');
    }
  }

  // 최적화된 경로 순서를 기반으로 RouteManager 업데이트
  void _updateRouteOrder(Map<String, dynamic> response, List<RoutePoint> originalPoints, RoutePoint startPoint, RoutePoint endPoint, List<RoutePoint> viaPoints) {
    try {
      // 응답에서 경로 순서 정보 추출
      if (response['features'] == null) {
        print('경로 순서 정보가 없습니다.');
        return;
      }

      // Point 타입 피처만 필터링하여 정렬된 포인트 목록 추출
      final List<Map<String, dynamic>> orderedPoints = [];

      for (var feature in response['features']) {
        // Point 타입 피처만 선택 (경로점)
        if (feature['geometry'] != null && feature['geometry']['type'] == 'Point' && feature['properties'] != null) {
          orderedPoints.add({
            'index': int.tryParse(feature['properties']['index'].toString()) ?? 9999,
            'pointType': feature['properties']['pointType'].toString(),
            'viaPointId': feature['properties']['viaPointId'].toString(),
            'viaPointName': feature['properties']['viaPointName'].toString()
          });
        }
      }

      // index 기준으로 정렬
      orderedPoints.sort((a, b) => a['index'].compareTo(b['index']));

      print('최적화된 경로 순서: ${orderedPoints.map((p) => '${p['index']}: ${p['viaPointName']}').join(' -> ')}');

      // 새로운 순서대로 RoutePoint 목록 생성
      final List<RoutePoint> reorderedPoints = [];

      for (var point in orderedPoints) {
        final String viaPointId = point['viaPointId'].toString();
        final String pointType = point['pointType'].toString();

        RoutePoint? routePoint;

        // 시작점
        if (pointType == 'S') {
          routePoint = startPoint;
        }
        // 도착점
        else if (pointType == 'E') {
          routePoint = endPoint;
        }
        // 경유지 (B1, B2, B3 등)
        else if (pointType.startsWith('B') && viaPointId.isNotEmpty) {
          // ID로 경유지 찾기
          routePoint = viaPoints.firstWhere(
            (p) => p.id == viaPointId,
          );
        }

        if (routePoint != null) {
          reorderedPoints.add(routePoint);
        } else {
          print('경고: ID: $viaPointId, 타입: $pointType에 해당하는 RoutePoint를 찾을 수 없습니다.');
        }
      }

      if (reorderedPoints.isNotEmpty) {
        // RouteManager 경로 순서 업데이트
        final routeManager = Get.find<RouteManager>();
        routeManager.updateRoutePoints(reorderedPoints);

        print('RouteManager 경로 순서가 업데이트되었습니다. 총 ${reorderedPoints.length}개 포인트');
      } else {
        print('경로 포인트를 찾을 수 없어 순서를 업데이트하지 않았습니다.');
      }
    } catch (e) {
      print('경로 순서 업데이트 중 오류 발생: $e');
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

      // 경로 좌표를 RouteManager에 저장하기 위한 좌표 목록
      List<List<double>> routeManagerCoordinates = [];

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

            // RouteManager용 좌표 배열에도 추가 (경도, 위도 순서)
            routeManagerCoordinates.add([coord[0].toDouble(), coord[1].toDouble()]);
          }

          allCoordinates.add(pathCoordinates);
        }
      }

      // 모든 경로 세그먼트 그리기
      for (int i = 0; i < allCoordinates.length; i++) {
        final pathCoordinates = allCoordinates[i];
        final routeId = 'optimized_route_$i';

        // 지도에 경로 그리기
        await _controller.executeScript('''
          try {
            const path = ${jsonEncode(pathCoordinates)}.map(
              coord => new Tmapv3.LatLng(coord.lat, coord.lng)
            );
            
            const polyline = new Tmapv3.Polyline({
              path: path,
              strokeColor: "#dd00dd",
              strokeWeight: 6,
              map: map
            });
            
            routes['$routeId'] = polyline;
            console.log('경로 세그먼트 $i 그리기 완료 (${pathCoordinates.length}개 지점)');
          } catch (error) {
            console.error('경로 그리기 오류:', error);
          }
        ''');
      }

      // RouteManager에 경로 좌표 저장
      if (routeManagerCoordinates.isNotEmpty) {
        // 최적화 요청에 사용된 경로점에서 차량 ID 추출
        final routeManager = Get.find<RouteManager>();

        // RouteManager의 현재 활성 차량 찾기
        int activeVehicleId = 0;

        // 현재 RouteManager가 가지고 있는 경로점에서 첫 번째 점의 ID에서 차량 ID 추출
        final routePoints = routeManager.allRoutes.isNotEmpty ? routeManager.allRoutes.first.points : [];

        if (routePoints.isNotEmpty && routePoints.first.id.contains('_')) {
          final idParts = routePoints.first.id.split('_');
          if (idParts.length > 1) {
            activeVehicleId = int.tryParse(idParts[1]) ?? 0;
          }
        }

        // 차량 ID가 유효하면 경로 좌표 업데이트
        if (activeVehicleId > 0) {
          routeManager.updateRouteCoordinates(activeVehicleId, routeManagerCoordinates);
          print('RouteManager에 경로 좌표 저장 완료: 차량 ID $activeVehicleId, 좌표 수: ${routeManagerCoordinates.length}');
        } else {
          print('경로 좌표를 저장할 차량 ID를 찾을 수 없습니다.');
        }
      }

      // properties에서 값 추출 후 적절한 타입으로 파싱
      final totalDistance = double.parse((double.parse(properties['totalDistance'].toString()) / 1000).toStringAsFixed(1));
      final totalTime = int.parse((double.parse(properties['totalTime'].toString()) / 60).toStringAsFixed(0));
      final totalFare = int.parse(properties['totalFare'].toString());

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
      _optimizationCompleters.clear();
    } catch (e) {
      print('WebView 종료 오류: $e');
    }
  }

  // 모든 경로 지우기
  Future<void> clearAllRoutes() async {
    await _controller.executeScript('''
      // 기존 경로 제거
      for (const id in routes) {
        routes[id].setMap(null);
      }
      routes = {};
    ''');
  }
}

// Completer 확장 - 완료 여부 확인
extension CompleterExtension<T> on Completer<T> {
  bool get isCompleted => this.isCompleted;
}
