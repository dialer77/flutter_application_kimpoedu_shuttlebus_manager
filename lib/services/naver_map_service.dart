import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'dart:async';
import 'package:get/get.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'local_web_server.dart';

import '../models/route_point.dart';
import '../models/route_info.dart';
import '../controllers/synology_controller.dart';

class NaverMapService {
  static final NaverMapService _instance = NaverMapService._internal();
  factory NaverMapService() => _instance;
  NaverMapService._internal();

  // SynologyController에서 클라이언트 ID 가져오기
  String get _naverMapClientId => Get.find<SynologyController>().naverClientId;

  final WebviewController _controller = WebviewController();
  bool _isMapInitialized = false;
  bool _isControllerInitialized = false;
  final List<Completer<void>> _pendingOperations = [];
  final StreamController<Map<String, dynamic>> _messageController = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _messageSubscription;
  final Map<String, Completer<List<Map<String, dynamic>>>> _searchCompleters = {};

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
      if (_naverMapClientId.isEmpty) {
        throw Exception('네이버 클라이언트 ID가 설정되지 않았습니다. 시놀로지 NAS 연결을 확인하세요.');
      }

      print('네이버 클라이언트 ID: $_naverMapClientId'); // 로그 추가

      await _controller.initialize();

      // 웹뷰 설정
      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      // 메시지 수신 설정 (한 번만 설정)
      _messageSubscription = _controller.webMessage.listen((event) {
        try {
          final data = jsonDecode(event);
          print('WebView 메시지 수신: ${data['event']}');

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

    print('지도 초기화 완료!');
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
        _controller.executeScript('console.log("DEBUG: 현재 지도 상태", typeof naver, typeof naver?.maps)').then((value) {
          print('지도 디버깅 정보: $value');
        }).catchError((e) {
          print('지도 디버깅 정보 가져오기 실패: $e');
        });

        // 현재 URL 확인
        getCurrentUrl().then((url) {
          print('타임아웃 시점의 URL: $url');
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

  // HTML 파일을 임시 디렉토리에 복사하고 클라이언트 ID 삽입
  Future<String> _prepareHtmlFile() async {
    try {
      // 임시 디렉토리 가져오기
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/naver_map.html';

      // HTML 파일 로드
      String content = await rootBundle.loadString('assets/html/naver_map.html');

      // 클라이언트 ID 삽입
      content = content.replaceAll('CLIENT_ID_PLACEHOLDER', _naverMapClientId);

      // 디버깅 정보
      print('HTML 파일에 삽입된 클라이언트 ID: $_naverMapClientId');

      // 파일로 저장
      final file = File(filePath);
      await file.writeAsString(content);

      print('HTML 파일 생성됨: $filePath');
      return filePath;
    } catch (e) {
      print('HTML 파일 준비 오류: $e');
      rethrow;
    }
  }

  // 지도 로드 - 로컬 웹 서버 사용, JavaScript로 동적 API 로드
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

      // 로컬 웹 서버가 실행 중인지 확인하고 필요시 시작
      final webServer = LocalWebServer();
      if (!webServer.isRunning) {
        await webServer.startServer();
      }

      if (webServer.serverUrl == null) {
        throw Exception('웹 서버를 시작할 수 없습니다');
      }

      // 웹 서버를 통해 HTML 로드
      final url = '${webServer.serverUrl}/naver_map.html';
      print('네이버 맵 HTML 로드: $url');
      await _controller.loadUrl(url);

      // HTML 로드 후 클라이언트 ID 전달하여 API 로드
      await Future.delayed(const Duration(milliseconds: 500));
      print('JavaScript로 네이버 지도 API 로드 요청, 클라이언트 ID: $_naverMapClientId');
      await _controller.executeScript('''
        loadNaverMapsAPI("$_naverMapClientId")
          .then(() => {
            console.log("API 로드 완료, 지도 초기화됨");
          })
          .catch(error => {
            console.error("API 로드 실패:", error);
          });
      ''');
    } catch (e) {
      print('지도 로드 오류: $e');
      rethrow;
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

  // 마커 추가 (ID 지정 버전)
  Future<void> addMarkerWithId(String id, double lat, double lng, String name, String type) async {
    try {
      await waitForInitialization();

      await _controller.executeScript('''
        addMarker('$id', $lat, $lng, '${name.replaceAll("'", "\\'")}', '$type');
      ''');

      print('마커 추가: id=$id, lat=$lat, lng=$lng, name=$name');
    } catch (e) {
      print('마커 추가 오류: $e');
      rethrow;
    }
  }

  // 마커 삭제
  Future<void> removeMarker(String id) async {
    try {
      await waitForInitialization();

      await _controller.executeScript('''
        removeMarker('$id');
      ''');

      print('마커 삭제: id=$id');
    } catch (e) {
      print('마커 삭제 오류: $e');
      rethrow;
    }
  }

  // 경로선 그리기
  Future<void> drawRoute(String id, List<Map<String, dynamic>> coordinates, String color, int width) async {
    try {
      await waitForInitialization();

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

  // 경로 최적화 (실제 앱에서는 네이버 API 활용)
  Future<List<RoutePoint>> optimizeRoute(List<RoutePoint> points) async {
    // 이 부분은 실제 네이버 Directions API 연동 필요
    // 현재는 더미 구현으로 원래 포인트를 그대로 반환
    return points;
  }

  // 지도 중심 이동
  Future<void> moveCenter(double lat, double lng, {int zoomLevel = 10}) async {
    try {
      await waitForInitialization();

      await _controller.executeScript('moveCenter($lat, $lng, $zoomLevel);');
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
      _messageSubscription?.cancel();
      _messageController.close();
      _searchCompleters.clear();
    } catch (e) {
      print('WebView 종료 오류: $e');
    }
  }

  // 네이버 지도 API 상태 확인
  Future<Map<String, dynamic>> checkApiStatus() async {
    try {
      if (!_isControllerInitialized) {
        await _initWebViewController();
      }

      final resultString = await _controller.executeScript('''
        (function() {
          return new Promise((resolve, reject) => {
            fetch('https://openapi.map.naver.com/openapi/v3/maps.js?ncpClientId=$_naverMapClientId', { 
              method: 'HEAD',
              mode: 'no-cors'
            })
            .then(response => {
              resolve(JSON.stringify({
                status: response.status,
                statusText: response.statusText,
                ok: response.ok
              }));
            })
            .catch(err => {
              resolve(JSON.stringify({
                error: err.message
              }));
            });
          });
        })();
      ''');

      return jsonDecode(resultString);
    } catch (e) {
      print('API 상태 확인 오류: $e');
      return {'error': e.toString()};
    }
  }

  // 현재 URL 확인 메서드 추가
  Future<String> getCurrentUrl() async {
    try {
      if (!_isControllerInitialized) {
        await _initWebViewController();
      }

      // location.href 값 가져오기
      final urlString = await _controller.executeScript('location.href');
      print('현재 WebView URL: $urlString');
      return urlString;
    } catch (e) {
      print('URL 확인 오류: $e');
      return 'Error: $e';
    }
  }

  // 일반 웹 페이지 로드 (URL 확인용)
  Future<void> loadWebPage(String url) async {
    try {
      if (!_isControllerInitialized) {
        await _initWebViewController();
      }

      print('웹 페이지 로드: $url');

      // 기존 초기화 상태 리셋
      _isMapInitialized = false;

      // URL 로드
      await _controller.loadUrl(url);

      // URL 확인 스크립트 추가
      await _controller.executeScript('''
        // 페이지 로드 완료 시 URL 로깅
        document.addEventListener('DOMContentLoaded', function() {
          console.log('페이지 로드 완료, URL: ' + location.href);
          try {
            window.chrome.webview.postMessage(JSON.stringify({
              event: 'urlInfo',
              url: location.href,
              timestamp: new Date().toISOString()
            }));
          } catch(e) {
            console.error('메시지 전송 오류:', e);
          }
        });
      ''');

      // 1초 후 URL 확인
      Future.delayed(const Duration(seconds: 1), () async {
        final currentUrl = await getCurrentUrl();
        print('현재 웹 페이지 URL: $currentUrl');
      });
    } catch (e) {
      print('웹 페이지 로드 오류: $e');
      rethrow;
    }
  }

  // 검색 완료 이벤트 처리 메서드
  void _handleSearchComplete(Map<String, dynamic> data) {
    final query = data['query'] as String?;
    final searchId = data['searchId'] as String?;

    print('검색 완료 이벤트 수신: $query (ID: $searchId)');

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

  // 위치 검색 - 네이버 지도 API의 주소 검색 서비스 사용
  Future<List<Map<String, dynamic>>> searchLocation(String query) async {
    try {
      if (query.isEmpty) return [];

      await waitForInitialization(); // 지도가 초기화되었는지 확인

      // 검색 ID 생성
      final searchId = 'search_${DateTime.now().millisecondsSinceEpoch}';

      // Completer 생성 및 저장
      final completer = Completer<List<Map<String, dynamic>>>();
      _searchCompleters[searchId] = completer;

      // 검색 JavaScript 실행 - 결과는 메시지로 받음
      await _controller.executeScript('''
        console.log("검색 시작: ${query.replaceAll('"', '\\"')}");
        searchAddress("${query.replaceAll('"', '\\"')}", "$searchId");
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

  // 특정 위치로 지도 이동
  Future<void> moveToLocation(double lat, double lng, int zoomLevel) async {
    try {
      await waitForInitialization();

      await _controller.executeScript('''
        moveCenter($lat, $lng, $zoomLevel);
      ''');

      print('지도 위치 이동: lat=$lat, lng=$lng, zoom=$zoomLevel');
    } catch (e) {
      print('지도 이동 오류: $e');
      rethrow;
    }
  }

  // 모든 마커 제거
  Future<void> clearAllMarkers() async {
    try {
      await waitForInitialization();

      await _controller.executeScript('''
        clearAllMarkers();
      ''');

      print('모든 마커 제거됨');
    } catch (e) {
      print('마커 제거 오류: $e');
      rethrow;
    }
  }

  // 모든 경로선 제거
  Future<void> clearAllRoutes() async {
    try {
      await waitForInitialization();

      await _controller.executeScript('''
        clearAllRoutes();
      ''');

      print('모든 경로선 제거됨');
    } catch (e) {
      print('경로선 제거 오류: $e');
      rethrow;
    }
  }
}

// Completer 확장 - 완료 여부 확인
extension CompleterExtension<T> on Completer<T> {
  bool get isCompleted => this.isCompleted;
}
