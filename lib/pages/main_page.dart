import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_application_kimpoedu_shuttlebus_manager/models/route_point.dart';
import 'package:get/get.dart';
import 'package:webview_windows/webview_windows.dart';

import '../models/vehicle_route_info.dart';
import '../models/route_info.dart';
import '../services/route_manager.dart';
import '../services/naver_map_service.dart';
import '../controllers/synology_controller.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int vehicleCount = 1;
  List<bool> timeSelections = [true, false]; // [오전, 오후]
  List<VehicleRouteInfo> routeInfoList = [VehicleRouteInfo(id: 1, isAM: true)];
  final RouteManager _routeManager = RouteManager();

  final NaverMapService _naverMapService = NaverMapService();

  bool _isMapInitialized = false;
  bool _isMapLoading = false;

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  int _selectedVehicleIndex = 0; // 현재 선택된 차량 인덱스

  @override
  void initState() {
    super.initState();

    // 직접 초기화 호출
    _initializeMap();

    // 지도 초기화 후에 데이터 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _displayLoadedRoutes();
    });
  }

  // 지도 초기화
  Future<void> _initializeMap() async {
    setState(() {
      _isMapLoading = true;
    });

    try {
      // Synology Controller에서 네이버 클라이언트 ID 확인
      final synologyController = Get.find<SynologyController>();
      if (synologyController.naverClientId.isEmpty) {
        print('네이버 클라이언트 ID가 설정되지 않았습니다.');
        throw Exception('네이버 클라이언트 ID가 설정되지 않았습니다. 시놀로지 NAS 연결을 확인하세요.');
      }

      // 네이버 지도 서비스 초기화
      await _loadMap();

      // 메시지 리스너 설정 - 새로운 메시지 스트림 사용
      _messageSubscription = _naverMapService.messageStream.listen(_handleMapMessage);
    } catch (e) {
      print('지도 초기화 오류: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('오류'),
            content: Text('지도를 초기화하는 중 오류가 발생했습니다: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isMapLoading = false;
      });
    }
  }

  // 메시지 처리
  void _handleMapMessage(Map<String, dynamic> data) {
    try {
      if (data['event'] == 'error' || data['event'] == 'jsError' || data['event'] == 'apiError' || data['event'] == 'initError') {
        print('지도 오류: ${data['message']}');
        // 오류 다이얼로그 표시
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('지도 오류'),
              content: Text(data['message'] ?? '알 수 없는 오류'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('확인'),
                ),
              ],
            ),
          );
        }
      } else if (data['event'] == 'mapInitialized') {
        setState(() {
          _isMapInitialized = true;
        });
        // 초기화 완료 후 URL 확인
        _naverMapService.getCurrentUrl().then((url) {
          print('지도 초기화 완료 후 URL: $url');
        });
      } else if (data['event'] == 'urlInfo' || data['event'] == 'urlChanged') {
        // URL 정보 로깅
        print('WebView URL 정보 [${data['event']}]: ${data['url']}');
        print('타임스탬프: ${data['timestamp']}');
      } else if (data['event'] == 'apiStatus') {
        print('API 상태: ${data['status']} ${data['statusText']}');
      } else if (data['event'] == 'consoleLog') {
        print('지도 콘솔[${data['level']}]: ${data['message']}');
      } else if (data['event'] == 'mapClicked') {
        // 지도 클릭 이벤트 처리
        print('지도 클릭: ${data['lat']}, ${data['lng']}');
      }
    } catch (e) {
      print('메시지 파싱 오류: $e');
    }
  }

  // 지도 로드
  Future<void> _loadMap() async {
    setState(() {
      _isMapLoading = true;
      _isMapInitialized = false;
    });

    try {
      await _naverMapService.loadMap();

      setState(() {
        _isMapInitialized = true;
        _isMapLoading = false;
      });
    } catch (e) {
      setState(() {
        _isMapLoading = false;
      });

      print('지도 로드 오류: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('오류'),
            content: Text('지도를 로드하는 중 오류가 발생했습니다: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    }
  }

  // 경로 정보 업데이트
  void _updateRouteInfoList() {
    // 호차 수에 맞게 리스트 업데이트
    if (vehicleCount > routeInfoList.length) {
      // 호차 추가
      for (int i = routeInfoList.length + 1; i <= vehicleCount; i++) {
        routeInfoList.add(VehicleRouteInfo(id: i, isAM: timeSelections[0]));
      }
    } else if (vehicleCount < routeInfoList.length) {
      // 호차 제거
      routeInfoList = routeInfoList.sublist(0, vehicleCount);
    }
  }

  // StreamSubscription 필드 추가
  StreamSubscription? _messageSubscription;

  @override
  void dispose() {
    _messageSubscription?.cancel(); // 구독 취소
    _naverMapService.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 좌측 설정 패널
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.5),
                    spreadRadius: 1,
                    blurRadius: 7,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '경로 설정',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  // 차량 호차 수 설정
                  Row(
                    children: [
                      const Text('차량 호차 수: ', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 10),
                      DropdownButton<int>(
                        value: vehicleCount,
                        items: List.generate(10, (index) => index + 1)
                            .map((count) => DropdownMenuItem<int>(
                                  value: count,
                                  child: Text(count.toString()),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            // 이전 차량 수 저장
                            final previousCount = vehicleCount;
                            vehicleCount = value!;

                            // RouteManager를 통해 차량 수 업데이트
                            _routeManager.ensureVehicleCount(vehicleCount, timeSelections[0]);

                            // 차량이 추가된 경우 신규 추가된 마지막 차량으로 자동 선택
                            if (value > previousCount) {
                              _selectedVehicleIndex = vehicleCount - 1;
                            }
                            // 차량이 감소한 경우 범위를 벗어나지 않도록 조정
                            else if (_selectedVehicleIndex >= vehicleCount) {
                              _selectedVehicleIndex = vehicleCount - 1;
                            }

                            // UI 업데이트
                            _updateVehicleRouteInfo();

                            // 선택된 차량의 경로 표시 강조
                            _highlightSelectedVehicleRoute();
                          });
                        },
                      ),
                    ],
                  ),

                  // 운행 시간 선택 (오전/오후)
                  Row(
                    children: [
                      ToggleButtons(
                        isSelected: timeSelections,
                        onPressed: (index) {
                          setState(() {
                            for (int i = 0; i < timeSelections.length; i++) {
                              timeSelections[i] = i == index;
                            }

                            // 선택된 모든 호차의 시간 변경 (RouteManager 사용)
                            final isAM = timeSelections[0];
                            _routeManager.updateAllRoutesTime(isAM);

                            // UI 업데이트
                            _updateVehicleRouteInfo();
                          });
                        },
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text('오전'),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text('오후'),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // 호차 선택 버튼들
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: List.generate(
                      vehicleCount,
                      (index) => ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedVehicleIndex = index;
                            // 선택된 차량의 경로 강조 표시
                            _highlightSelectedVehicleRoute();
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedVehicleIndex == index ? Colors.blue : Colors.grey[300],
                          foregroundColor: _selectedVehicleIndex == index ? Colors.white : Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        child: Text('${index + 1}호차'),
                      ),
                    ),
                  ),

                  // 선택된 호차 경로 정보 표시
                  if (_routeManager.getRoutePointCount(_selectedVehicleIndex) > 0)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_selectedVehicleIndex + 1}호차 경로 (${_routeManager.getRoutePointCount(_selectedVehicleIndex)}개 지점)',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            // 경로 목록 (최대 3개만 표시, 스크롤 가능)
                            SizedBox(
                              height: 200,
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _routeManager.getRoutePointCount(_selectedVehicleIndex),
                                itemBuilder: (context, idx) {
                                  final routePoint = _routeManager.getRoutePoints(_selectedVehicleIndex)[idx];
                                  return ListTile(
                                    dense: true,
                                    title: Text(routePoint.name),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, size: 18),
                                      onPressed: () {
                                        setState(() {
                                          // RouteManager를 통해 특정 경로점 삭제
                                          _routeManager.removeRoutePoint(_selectedVehicleIndex, idx);
                                          // 마커 제거
                                          _naverMapService.removeMarker(routePoint.id);
                                          // 경로선 업데이트
                                          _updateRoutePolyline(_selectedVehicleIndex);
                                        });
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 경로 저장 기능만 유지
                  const SizedBox(height: 20),
                  const Divider(),

                  // 경로 저장 버튼
                  ElevatedButton.icon(
                    onPressed: () async {
                      // 경로 저장 처리
                      final synologyController = Get.find<SynologyController>();

                      if (!synologyController.isConnected.value) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('NAS 연결이 필요합니다. 설정에서 먼저 연결해주세요.')));
                        return;
                      }

                      // 저장 진행 (고정 파일명 사용)
                      final success = await synologyController.saveRouteData(_routeManager);

                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('경로 정보가 성공적으로 저장되었습니다'),
                          duration: Duration(seconds: 2),
                        ));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('경로 정보 저장 중 오류가 발생했습니다'),
                          backgroundColor: Colors.red,
                        ));
                      }
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('경로 저장'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                  ),

                  // 추가 설정 항목
                ],
              ),
            ),
          ),

          // 우측 지도 패널
          Expanded(
            flex: 7,
            child: Column(
              children: [
                // 검색창
                Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.white,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: '장소 검색...',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                              ),
                              onSubmitted: (value) => _searchLocation(value),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _searchLocation(_searchController.text),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('검색'),
                          ),
                        ],
                      ),

                      // 검색 중 표시
                      if (_isSearching)
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('검색 중...'),
                            ],
                          ),
                        ),

                      // 검색 결과 목록 표시
                      _searchResults.isNotEmpty
                          ? Container(
                              // 검색 결과 개수에 따라 동적으로 높이 계산 (최대 300)
                              height: min(_searchResults.length * 80.0, 300.0),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.3),
                                    spreadRadius: 1,
                                    blurRadius: 3,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ListView.builder(
                                itemCount: _searchResults.length,
                                // 높이 제한으로 스크롤이 필요한 경우 스크롤 가능하도록 설정
                                shrinkWrap: true,
                                itemBuilder: (context, index) {
                                  final item = _searchResults[index];
                                  return ListTile(
                                    dense: _searchResults.length > 5, // 항목이 많으면 더 조밀하게 표시
                                    title: Text(
                                      item['name'] ?? '이름 없음',
                                      style: TextStyle(
                                        fontSize: _searchResults.length > 5 ? 14.0 : 16.0,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      item['roadAddress'] ?? item['address'] ?? '주소 정보 없음',
                                      style: TextStyle(
                                        fontSize: _searchResults.length > 5 ? 12.0 : 14.0,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: _searchResults.length > 5 ? 4 : 8),
                                    onTap: () {
                                      // 선택한 항목을 지도에 표시
                                      _showSearchResultOnMap(item);

                                      // 검색 결과 목록 닫기
                                      setState(() {
                                        _searchResults = [];
                                      });
                                    },
                                  );
                                },
                              ),
                            )
                          : const SizedBox.shrink(),
                    ],
                  ),
                ),

                // 지도 영역 (기존 코드)
                Expanded(
                  child: Stack(
                    children: [
                      // 기졸 WebView 코드
                      Container(
                        color: Colors.grey[200],
                        child: _isMapInitialized ? Webview(_naverMapService.controller) : const Center(child: CircularProgressIndicator()),
                      ),
                      if (_isMapLoading)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 검색 수행 메서드 추가
  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    try {
      // NaverMapService의 searchLocation 메서드 호출
      final results = await _naverMapService.searchLocation(query);

      // 검색 결과 처리
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });

      if (_searchResults.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('검색 결과가 없습니다: $query')));
      } else {
        // 키보드 숨기기
        FocusScope.of(context).unfocus();

        // 검색 결과가 있음을 알림
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_searchResults.length}개의 검색 결과를 찾았습니다')));
      }
    } catch (e) {
      print('위치 검색 오류: $e');
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('검색 중 오류가 발생했습니다: $e')));
    }
  }

  // _showSearchResultOnMap 함수 수정
  void _showSearchResultOnMap(Map<String, dynamic> location) {
    if (location.containsKey('lat') && location.containsKey('lng')) {
      // 마커 고유 ID 생성
      final markerId = 'vehicle_${_selectedVehicleIndex + 1}_${DateTime.now().millisecondsSinceEpoch}';

      // 마커 추가
      _naverMapService.addMarkerWithId(markerId, location['lat'], location['lng'], location['name'] ?? '선택된 위치', 'route' // 마커 타입
          );

      // 지도 위치 이동
      _naverMapService.moveToLocation(location['lat'], location['lng'], 16 // 줌 레벨
          );

      // RouteManager를 통해 선택된 차량의 동선에 위치 추가
      setState(() {
        // RoutePoint 객체 생성
        final routePoint = RoutePoint(
            id: markerId,
            name: location['name'] ?? '위치',
            address: location['roadAddress'] ?? location['address'] ?? '',
            latitude: location['lat'],
            longitude: location['lng'],
            type: 'waypoint', // 기본 타입: 경유지
            sequence: _routeManager.getRoutePointCount(_selectedVehicleIndex) + 1);

        // RouteManager를 통해 경로점 추가
        _routeManager.addRoutePoint(_selectedVehicleIndex, routePoint);

        // 경로 정보 갱신
        _updateVehicleRouteInfo();
      });

      // 사용자에게 알림
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${location['name'] ?? '선택된 위치'}가 ${_selectedVehicleIndex + 1}호차 동선에 추가되었습니다'),
        action: SnackBarAction(
          label: '실행취소',
          onPressed: () {
            setState(() {
              // RouteManager를 통해 마지막 추가 지점 삭제
              final removedPoint = _routeManager.removeLastRoutePoint(_selectedVehicleIndex);
              if (removedPoint != null) {
                // 마커도 삭제
                _naverMapService.removeMarker(removedPoint.id);
                // 경로 정보 갱신
                _updateVehicleRouteInfo();
              }
            });
          },
        ),
      ));

      // 경로선 그리기
      _updateRoutePolyline(_selectedVehicleIndex);
    }
  }

  // 선택된 차량의 경로를 강조 표시하는 새로운 메서드
  void _highlightSelectedVehicleRoute() {
    // 모든 차량의 경로선 두께와 투명도 업데이트
    for (int i = 0; i < vehicleCount; i++) {
      final routePoints = _routeManager.getRoutePoints(i);
      if (routePoints.length >= 2) {
        List<Map<String, dynamic>> coordinates = routePoints.map((point) {
          return {'lat': point.latitude, 'lng': point.longitude};
        }).toList();

        // 경로선 색상 지정 (차량마다 다른 색상)
        String color;
        switch (i % 5) {
          case 0:
            color = '#FF5722';
            break; // 주황
          case 1:
            color = '#4CAF50';
            break; // 녹색
          case 2:
            color = '#2196F3';
            break; // 파랑
          case 3:
            color = '#9C27B0';
            break; // 보라
          case 4:
            color = '#FFC107';
            break; // 노랑
          default:
            color = '#FF5722';
        }

        // 선택된 차량은 더 두껍게 표시
        final thickness = (i == _selectedVehicleIndex) ? 8 : 5;
        // 선택된 차량은 불투명하게, 나머지는 반투명하게
        final opacity = (i == _selectedVehicleIndex) ? 1.0 : 0.7;

        // 경로선 그리기
        _naverMapService.drawRoute('route_${i + 1}', coordinates, color, thickness);
      }
    }
  }

  // 경로선 업데이트 함수 수정
  void _updateRoutePolyline(int vehicleIndex) {
    // RouteManager를 통해 경로점 목록 가져오기
    final routePoints = _routeManager.getRoutePoints(vehicleIndex);

    // 경로점이 2개 이상인 경우에만 경로선 그리기
    if (routePoints.length >= 2) {
      List<Map<String, dynamic>> coordinates = routePoints.map((point) {
        return {'lat': point.latitude, 'lng': point.longitude};
      }).toList();

      // 경로선 색상 지정 (차량마다 다른 색상)
      String color;
      switch (vehicleIndex % 5) {
        case 0:
          color = '#FF5722';
          break; // 주황
        case 1:
          color = '#4CAF50';
          break; // 녹색
        case 2:
          color = '#2196F3';
          break; // 파랑
        case 3:
          color = '#9C27B0';
          break; // 보라
        case 4:
          color = '#FFC107';
          break; // 노랑
        default:
          color = '#FF5722';
      }

      // 선택된 차량은 더 두껍게 표시
      final thickness = (vehicleIndex == _selectedVehicleIndex) ? 8 : 5;
      // 선택된 차량은 불투명하게, 나머지는 반투명하게
      final opacity = (vehicleIndex == _selectedVehicleIndex) ? 1.0 : 0.7;

      // 경로선 그리기
      _naverMapService.drawRoute('route_${vehicleIndex + 1}', coordinates, color, thickness);
    }
  }

  // 차량 경로 정보 UI 업데이트
  void _updateVehicleRouteInfo() {
    // RouteManager에서 각 차량의 경로 정보 갱신
    setState(() {
      // 필요한 경우 차량 수에 맞게 경로 정보 업데이트
      _routeManager.ensureVehicleCount(vehicleCount, timeSelections[0]);

      // 모든 차량의 경로선 업데이트
      for (int i = 0; i < vehicleCount; i++) {
        _updateRoutePolyline(i);
      }
    });
  }

  // 이미 로드된 경로 데이터 표시
  void _displayLoadedRoutes() {
    try {
      // 경로 매니저에서 데이터 가져오기
      setState(() {
        // 차량 수에 맞게 경로 정보 업데이트
        _routeManager.ensureVehicleCount(vehicleCount, timeSelections[0]);

        // 모든 경로 표시 업데이트
        for (int i = 0; i < vehicleCount; i++) {
          _updateRoutePolyline(i);
        }
      });
    } catch (e) {
      print('경로 데이터 표시 중 오류 발생: $e');
    }
  }
}
