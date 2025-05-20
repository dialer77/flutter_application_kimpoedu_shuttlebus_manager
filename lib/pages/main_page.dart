// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_application_kimpoedu_shuttlebus_manager/constants/enum_types.dart';
import 'package:flutter_application_kimpoedu_shuttlebus_manager/models/route_point.dart';
import 'package:get/get.dart';
import 'package:webview_windows/webview_windows.dart';

import '../services/route_manager.dart';
import '../services/tmap/t_map_service.dart';
import '../controllers/synology_controller.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final RouteManager _routeManager = RouteManager();
  final TMapService _tMapService = TMapService();
  final TextEditingController _searchController = TextEditingController();

  bool _isMapInitialized = false;
  bool _isMapLoading = false;
  bool _isSearching = false;
  int _selectedVehicleId = 0; // 현재 선택된 차량 인덱스
  RoutePoint? _selectedRoute;

  List<Map<String, dynamic>> _searchResults = [];

  // 날짜 및 시간 선택 변수 추가
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  // StreamSubscription 필드 추가
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    // 직접 초기화 호출
    _initializeMap();
  }

  // 지도 초기화
  Future<void> _initializeMap() async {
    setState(() {
      _isMapLoading = true;
    });

    try {
      // Synology Controller에서 티맵 클라이언트 ID 확인
      final synologyController = Get.find<SynologyController>();
      if (synologyController.tmapClientId.isEmpty) {
        print('티맵 클라이언트 ID가 설정되지 않았습니다.');
        throw Exception('티맵 클라이언트 ID가 설정되지 않았습니다. 시놀로지 NAS 연결을 확인하세요.');
      }

      // 티맵 지도 서비스 초기화
      await _loadMap();

      if (_routeManager.allRoutes.isNotEmpty) {
        _selectedRoute = _routeManager.allRoutes.first.startPoint;
      }

      // 메시지 리스너 설정 - 새로운 메시지 스트림 사용
      _messageSubscription = _tMapService.messageStream.listen(_handleMapMessage);
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
      } else if (data['event'] == 'consoleLog') {
        print('지도 콘솔[${data['level']}]: ${data['message']}');
      } else if (data['event'] == 'mapClicked') {
        print('지도 클릭: ${data['lat']}, ${data['lng']}');
      } else if (data['event'] == 'mapRightClick') {
        _selectedRoute?.updatePoint(data['lat'], data['lng']);
        final vehicleId = _selectedVehicleId;

        // 지도에 표시된 모든 마커 초기화
        _tMapService.clearAllMarkers();

        // 선택된 차량의 경로 포인트 가져오기
        final routePoints = _routeManager.getRoutePoints(vehicleId);

        // 경로 포인트를 유형별로 분류
        final startPoints = routePoints.where((point) => point.type == PointType.start).toList();
        final wayPoints = routePoints.where((point) => point.type == PointType.waypoint).toList();
        final endPoints = routePoints.where((point) => point.type == PointType.end).toList();

        // 1. 시작 지점 마커 추가
        for (int i = 0; i < startPoints.length; i++) {
          _tMapService.addMarker(startPoints[i], i);
        }

        // 2. 경유 지점 마커 추가
        for (int i = 0; i < wayPoints.length; i++) {
          _tMapService.addMarker(wayPoints[i], i);
        }

        // 3. 도착 지점 마커 추가
        for (int i = 0; i < endPoints.length; i++) {
          _tMapService.addMarker(endPoints[i], i);
        }
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
      await _tMapService.loadMap();

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

  @override
  void dispose() {
    _messageSubscription?.cancel(); // 구독 취소
    _tMapService.dispose();
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    '경로 설정',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  // 차량 호차 수 설정 부분을 추가/제거 버튼으로 교체
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          // 차량 추가 다이얼로그 표시
                          _showAddVehicleDialog();
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('차량 추가'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: vehicleCount > 0
                            ? () {
                                setState(() {
                                  // 현재 차량 수 확인
                                  final currentCount = vehicleCount;

                                  if (currentCount > 0) {
                                    int index = _routeManager.allRoutes.indexOf(_routeManager.getRoutesByVehicle(_selectedVehicleId).first);

                                    if (index == vehicleCount - 1) {
                                      index--;
                                    }
                                    // 선택된 차량 제거
                                    _routeManager.removeVehicle(_selectedVehicleId);

                                    _selectedVehicleId = index < 0 ? 0 : _routeManager.allRoutes[index].vehicleId;

                                    // 선택된 차량의 경로 마커 및 경로선 제거
                                    _tMapService.clearMap();

                                    // UI 업데이트
                                    if (_routeManager.allRoutes.isNotEmpty) {
                                      _updateVehicleRouteInfo();
                                    }
                                  }
                                });
                              }
                            : null, // 차량이 1대만 있으면 비활성화
                        icon: const Icon(Icons.remove),
                        label: const Text('차량 제거'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  // 호차 선택 버튼들
                  Wrap(
                    spacing: 15,
                    runSpacing: 4,
                    children: List.generate(
                      vehicleCount, // vehicleCount getter 사용
                      (index) => ElevatedButton(
                        onPressed: () {
                          setState(() {
                            final routeInfo = _routeManager.allRoutes[index];
                            _selectedVehicleId = routeInfo.vehicleId;

                            // 선택된 차량의 시작 지점 확인
                            final startPoint = _routeManager.getStartPoint(index);

                            // 시작 지점이 있으면 지도를 해당 위치로 이동
                            if (startPoint != null) {
                              _tMapService.moveToLocation(startPoint.latitude, startPoint.longitude, 14 // 줌 레벨
                                  );
                            }

                            // 선택된 차량의 경로 포인트 표시 업데이트
                            _updateVehicleRouteInfo();
                            if (_routeManager.getRoutesByVehicle(_selectedVehicleId).first.points.isNotEmpty) {
                              _selectedRoute = _routeManager.getRoutesByVehicle(_selectedVehicleId).first.startPoint;
                            } else {
                              _selectedRoute = null;
                            }
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedVehicleId == _routeManager.allRoutes[index].vehicleId ? Colors.blue : Colors.grey[300],
                          foregroundColor: _selectedVehicleId == _routeManager.allRoutes[index].vehicleId ? Colors.white : Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        child: Text(_routeManager.allRoutes[index].vehicleName),
                      ),
                    ),
                  ),

                  // 경로 저장 버튼 위치 변경: 날짜/시간 선택과 최적화 버튼 추가
                  const Divider(),

                  // 날짜/시간 선택과 최적화 버튼을 함께 배치
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 날짜/시간 선택 행 (출발 일시 텍스트 제거)
                        Row(
                          children: [
                            // 날짜 선택 버튼
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.calendar_today, size: 18),
                                label: Text(
                                  '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                onPressed: () async {
                                  final pickedDate = await showDatePicker(
                                    context: context,
                                    initialDate: _selectedDate,
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (pickedDate != null) {
                                    setState(() {
                                      _selectedDate = pickedDate;
                                    });
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 시간 선택 버튼
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.access_time, size: 18),
                                label: Text(
                                  '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                onPressed: () async {
                                  final pickedTime = await showTimePicker(
                                    context: context,
                                    initialTime: _selectedTime,
                                  );
                                  if (pickedTime != null) {
                                    setState(() {
                                      _selectedTime = pickedTime;
                                    });
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 현재 시간으로 설정 버튼 (이동됨)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.update, size: 16),
                              label: const Text('현재 시간', style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                setState(() {
                                  _selectedDate = DateTime.now();
                                  _selectedTime = TimeOfDay.now();
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),
                        // 경로 최적화 버튼과 일반 경로 버튼을 한 줄에 배치 (현재 시간 버튼 제거됨)
                        Row(
                          children: [
                            // 경로 최적화 버튼
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.route),
                                label: const Text('경로 최적화'),
                                onPressed: () async {
                                  try {
                                    // 로딩 표시
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('경로 최적화 중...'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );

                                    // 경로 최적화 실행 (비동기 대기)
                                    final routePoints = _routeManager.getRoutePoints(_selectedVehicleId);
                                    if (routePoints.length < 2) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('최소 출발지와 도착지가 필요합니다'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }

                                    // 출발 일시 설정 (선택된 날짜와 시간 조합)
                                    final departureDateTime = DateTime(
                                      _selectedDate.year,
                                      _selectedDate.month,
                                      _selectedDate.day,
                                      _selectedTime.hour,
                                      _selectedTime.minute,
                                    );

                                    // 최적화 요청 시 출발 일시 전달
                                    await _tMapService.optimizeRoute(
                                      routePoints,
                                      _selectedVehicleId,
                                      departureDateTime, // 출발 일시 전달
                                    );

                                    // 성공 메시지 표시
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('경로 최적화 완료'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );

                                    // UI 갱신 (RouteManager가 이미 내부적으로 업데이트됨)
                                    setState(() {
                                      _updateVehicleRouteInfo();
                                      // 경로 목록 UI 갱신
                                    });
                                  } catch (e) {
                                    // 오류 메시지 표시
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('경로 최적화 실패: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 일반 경로 버튼 추가
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.alt_route),
                                label: const Text('일반 경로'),
                                onPressed: () async {
                                  try {
                                    // 로딩 표시
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('일반 경로 계산 중...'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );

                                    // 일반 경로 계산 실행
                                    final routePoints = _routeManager.getRoutePoints(_selectedVehicleId);
                                    if (routePoints.length < 2) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('최소 출발지와 도착지가 필요합니다'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }

                                    // 출발 일시 설정 (선택된 날짜와 시간 조합)
                                    final departureDateTime = DateTime(
                                      _selectedDate.year,
                                      _selectedDate.month,
                                      _selectedDate.day,
                                      _selectedTime.hour,
                                      _selectedTime.minute,
                                    );

                                    // 일반 경로 요청 시 출발 일시 전달
                                    await _tMapService.calculateNormalRoute(
                                      routePoints,
                                      _selectedVehicleId,
                                      departureDateTime, // 출발 일시 전달
                                    );

                                    // 성공 메시지 표시
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('일반 경로 계산 완료'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );

                                    // UI 갱신
                                    setState(() {
                                      // 경로 목록 UI 갱신
                                    });
                                  } catch (e) {
                                    // 오류 메시지 표시
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('일반 경로 계산 실패: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 선택된 호차 경로 정보 표시
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 경로 제목과 개수 정보
                              Expanded(
                                child: Text(
                                  _routeManager.allRoutes.isNotEmpty
                                      ? '${_routeManager.getVehicleName(_selectedVehicleId)} 경로 (${_routeManager.getRoutePointCount(_selectedVehicleId)}개 지점)'
                                      : '경로 정보가 없습니다',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // 시작 지점 표시 (있는 경우)
                          _buildSingleRoutePoint(_routeManager.getStartPoint(_selectedVehicleId), true),

                          // 경로 목록 (스크롤 가능) - 경유지만 표시
                          Expanded(
                            child: ReorderableListView.builder(
                              key: ValueKey('route_list_${_routeManager.getRoutePoints(_selectedVehicleId).map((p) => p.id).join('_')}'),
                              shrinkWrap: true,
                              // 필터링해서 경유지만 카운트
                              itemCount: _routeManager.getRoutePoints(_selectedVehicleId).where((point) => point.type == PointType.waypoint).length,
                              itemBuilder: (context, idx) {
                                // 경유지만 필터링해서 가져오기 (매번 새로 가져와서 최신 상태 유지)
                                final waypointsOnly = _routeManager.getRoutePoints(_selectedVehicleId).where((point) => point.type == PointType.waypoint).toList();
                                final routePoint = waypointsOnly[idx];
                                return _buildDraggableRoutePointTile(
                                    routePoint,
                                    // 원래 인덱스 찾기
                                    _routeManager.getRoutePoints(_selectedVehicleId).indexOf(routePoint));
                              },
                              onReorder: (oldIndex, newIndex) {
                                setState(() {
                                  // 경유지만 필터링한 리스트
                                  final waypointsOnly = _routeManager.getRoutePoints(_selectedVehicleId).where((point) => point.type == PointType.waypoint).toList();

                                  // 실제 전체 리스트에서의 인덱스 계산
                                  final oldRealIndex = _routeManager.getRoutePoints(_selectedVehicleId).indexOf(waypointsOnly[oldIndex]);

                                  // newIndex가 이동 후 위치를 나타내므로 조정 필요
                                  if (newIndex > oldIndex) newIndex--;

                                  final newRealIndex = _routeManager.getRoutePoints(_selectedVehicleId).indexOf(waypointsOnly[newIndex]);

                                  // RouteManager를 통해 경로점 순서 변경
                                  _routeManager.reorderRoutePoint(_selectedVehicleId, oldRealIndex, newRealIndex);

                                  // 경로선 업데이트
                                  _updateVehicleRouteInfo();
                                });
                              },
                            ),
                          ),

                          // 종료 지점 표시 (있는 경우) - 경유지 아래에 배치
                          _buildSingleRoutePoint(_routeManager.getEndPoint(_selectedVehicleId), false),

                          // 경로 정보 요약 (거리/시간)
                          if (_routeManager.getRoutesByVehicle(_selectedVehicleId).isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.route, color: Colors.blue, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    '총 거리: ${_routeManager.getRoutesByVehicle(_selectedVehicleId).first.totalDistance.toStringAsFixed(1)}km',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '예상 시간: ${_routeManager.getRoutesByVehicle(_selectedVehicleId).first.estimatedTime}분',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // 경로 저장 버튼을 맨 아래로 이동
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
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
                                      _registSearchResult(item);

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
                        child: _isMapInitialized ? Webview(_tMapService.controller) : const Center(child: CircularProgressIndicator()),
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
      // TMapService의 searchLocation 메서드 호출
      final results = await _tMapService.searchLocation(query);

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

        // 첫 번째 검색 결과 위치로 지도 이동
        if (_searchResults.isNotEmpty && _searchResults[0].containsKey('lat') && _searchResults[0].containsKey('lng')) {
          final firstResult = _searchResults[0];
          await _tMapService.moveToLocation(firstResult['lat'], firstResult['lng'], 16 // 줌 레벨
              );
        }
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

  void _registSearchResult(Map<String, dynamic> location) {
    if (location.containsKey('lat') && location.containsKey('lng')) {
      // 마커 고유 ID 생성
      final markerId = 'vehicle_${_selectedVehicleId + 1}_${DateTime.now().millisecondsSinceEpoch}';

      // 포인트 타입 결정
      PointType pointType = PointType.waypoint; // 기본값은 경유지

      // 첫 번째 포인트인 경우 시작 지점으로 설정
      if (_routeManager.getRoutePointCount(_selectedVehicleId) == 0) {
        pointType = PointType.start;
      }

      // 지도 위치 이동
      _tMapService.moveToLocation(location['lat'], location['lng'], 16);

      // RouteManager를 통해 선택된 차량의 동선에 위치 추가 (현재 시간대 지정)
      setState(() {
        // RoutePoint 객체 생성
        final routePoint = RoutePoint(
            id: markerId,
            name: location['name'] ?? '위치',
            address: location['roadAddress'] ?? location['address'] ?? '',
            latitude: location['lat'],
            longitude: location['lng'],
            type: pointType, // 결정된 포인트 타입 사용
            sequence: _routeManager.getRoutePointCount(_selectedVehicleId) + 1);

        // RouteManager를 통해 경로점 추가 (현재 시간대 지정)
        _routeManager.addRoutePoint(_selectedVehicleId, routePoint);
        _selectedRoute ??= routePoint;

        // 경로 정보 갱신
        _updateVehicleRouteInfo();
      });

      // 사용자에게 알림
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${location['name'] ?? '선택된 위치'}가 ${_selectedVehicleId + 1}호차 동선에 추가되었습니다'),
        action: SnackBarAction(
          label: '실행취소',
          onPressed: () {
            setState(() {
              // 마지막 추가된 지점 제거
              final removedPoint = _routeManager.removeLastRoutePoint(_selectedVehicleId);
              if (removedPoint != null) {
                // 마커 제거
                _tMapService.removeMarker(removedPoint.id);
                // 경로선 업데이트
                _updateVehicleRouteInfo();
              }
            });
          },
        ),
      ));
    }
  }

  // 차량 경로 정보 UI 업데이트
  void _updateVehicleRouteInfo() {
    setState(() {
      // 지도에 표시된 모든 마커 초기화
      _tMapService.clearAllMarkers();
      if (_routeManager.allRoutes.isEmpty) {
        return;
      }

      final vehicleId = _selectedVehicleId;

      // 선택된 차량의 경로 포인트 가져오기
      final routePoints = _routeManager.getRoutePoints(vehicleId);

      // 경로 포인트를 유형별로 분류
      final startPoints = routePoints.where((point) => point.type == PointType.start).toList();
      final wayPoints = routePoints.where((point) => point.type == PointType.waypoint).toList();
      final endPoints = routePoints.where((point) => point.type == PointType.end).toList();

      // 1. 시작 지점 마커 추가
      for (int i = 0; i < startPoints.length; i++) {
        _tMapService.addMarker(startPoints[i], i);
      }

      // 2. 경유 지점 마커 추가
      for (int i = 0; i < wayPoints.length; i++) {
        _tMapService.addMarker(wayPoints[i], i);
      }

      // 3. 도착 지점 마커 추가
      for (int i = 0; i < endPoints.length; i++) {
        _tMapService.addMarker(endPoints[i], i);
      }

      final routeInfo = _routeManager.getRoutesByVehicle(vehicleId).first;
      _tMapService.drawRoute(routeInfo.coordinates, '#dd00dd');
    });
  }

  // 총 차량 수를 RouteManager에서 가져오는 getter 추가
  int get vehicleCount {
    // 고유한 차량 ID 목록 가져오기
    return _routeManager.allRoutes.length;
  }

  // 단일 시작/종료 포인트 표시를 위한 메서드 수정
  Widget _buildSingleRoutePoint(RoutePoint? point, bool isStart) {
    if (point == null) return const SizedBox.shrink();

    // 시작 또는 종료 지점인지 확인
    final isCorrectType = isStart ? point.type == PointType.start : point.type == PointType.end;

    // 타입이 일치하지 않으면 표시하지 않음
    if (!isCorrectType) return const SizedBox.shrink();

    final IconData icon = isStart ? Icons.play_circle : Icons.stop_circle;
    final Color color = isStart ? Colors.green : Colors.red;
    final String typeText = isStart ? '출발지' : '도착지';

    // 현재 선택된 경로 포인트인지 확인
    final isSelected = _selectedRoute?.id == point.id;

    return GestureDetector(
      onTap: () {
        // 지점 클릭 시 지도 이동
        _tMapService.moveToLocation(point.latitude, point.longitude, 16);

        // 클릭된 포인트를 선택된 경로로 설정
        setState(() {
          _selectedRoute = point;
        });
      },
      child: Container(
        margin: EdgeInsets.only(
          top: isStart ? 0 : 8,
          bottom: isStart ? 8 : 0,
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.2) // 선택된 경우 더 진한 배경색
              : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: color, width: 1.5) // 선택된 경우 더 두꺼운 테두리
              : Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: isSelected ? color.withOpacity(0.7) : color, // 선택된 경우 더 진한 아이콘 색상
                size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    typeText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, // 선택된 경우 굵게
                      color: color,
                    ),
                  ),
                  Text(
                    point.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, // 선택된 경우 굵게
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    point.address,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 삭제 버튼
            IconButton(
              icon: const Icon(Icons.delete, size: 16),
              tooltip: '지점 삭제',
              onPressed: () {
                final index = _routeManager.getRoutePoints(_selectedVehicleId).indexWhere((p) => p.id == point.id);
                if (index >= 0) {
                  setState(() {
                    // RouteManager를 통해 해당 지점 삭제
                    final removedPoint = _routeManager.removeRoutePoint(_selectedVehicleId, index);
                    if (removedPoint != null) {
                      // 마커 제거
                      _tMapService.removeMarker(removedPoint.id);
                      // 경로선 업데이트
                      _updateVehicleRouteInfo();
                    }
                  });
                }
              },
              color: Colors.grey,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ),
      ),
    );
  }

  // 드래그 가능한 경로 포인트 타일 위젯 수정
  Widget _buildDraggableRoutePointTile(RoutePoint routePoint, int index) {
    // 포인트 유형에 따른 아이콘 및 색상 설정
    Color iconColor;

    switch (routePoint.type) {
      case PointType.start:
        iconColor = Colors.green;
        break;
      case PointType.end:
        iconColor = Colors.red;
        break;
      default:
        iconColor = Colors.blue;
    }

    // 원래 목록에서의 순서 계산 (경유지만 고려)
    final waypointsOnly = _routeManager.getRoutePoints(_selectedVehicleId).where((point) => point.type == PointType.waypoint).toList();
    final waypointIndex = waypointsOnly.indexOf(routePoint) + 1; // 1부터 시작하는 인덱스

    // 현재 선택된 경로인지 확인
    final isSelected = _selectedRoute?.id == routePoint.id;

    // 선택된 경로에 대한 스타일 적용을 위해 ListTile을 Container로 감싸기
    return Container(
      key: ValueKey(routePoint.id), // 드래그 앤 드롭용 키 추가
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        // 선택된 항목은 밝은 파란색 배경과 테두리 적용
        color: isSelected ? Colors.blue.withOpacity(0.1) : null,
        borderRadius: BorderRadius.circular(6),
        border: isSelected ? Border.all(color: Colors.blue, width: 1.5) : null,
      ),
      child: ListTile(
        dense: true,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 번호를 채워진 원 안에 흰색으로 표시
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue.shade700 : iconColor, // 선택된 경우 더 진한 파란색
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                "$waypointIndex",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        title: Text(
          routePoint.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, // 선택된 경우 굵게 표시
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 시작 지점으로 설정 버튼
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 16),
              tooltip: '시작 지점으로 설정',
              onPressed: routePoint.type != PointType.start
                  ? () {
                      setState(() {
                        // 시작 지점으로 설정
                        _routeManager.setStartPoint(_selectedVehicleId, index);
                        // 경로선 업데이트
                        _updateVehicleRouteInfo();
                      });
                    }
                  : null,
              color: Colors.green,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
            // 종료 지점으로 설정 버튼
            IconButton(
              icon: const Icon(Icons.stop, size: 16),
              tooltip: '종료 지점으로 설정',
              onPressed: routePoint.type != PointType.end
                  ? () {
                      setState(() {
                        // 종료 지점으로 설정
                        _routeManager.setEndPoint(_selectedVehicleId, index);
                        // 경로선 업데이트
                        _updateVehicleRouteInfo();
                      });
                    }
                  : null,
              color: Colors.red,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
            // 삭제 버튼
            IconButton(
              icon: const Icon(Icons.delete, size: 16),
              tooltip: '지점 삭제',
              onPressed: () {
                setState(() {
                  // RouteManager를 통해 특정 경로점 삭제
                  final removedPoint = _routeManager.removeRoutePoint(_selectedVehicleId, index);
                  if (removedPoint != null) {
                    // 마커 제거
                    _tMapService.removeMarker(removedPoint.id);
                    // 경로선 업데이트
                    _updateVehicleRouteInfo();
                  }
                });
              },
              color: Colors.grey,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ),
        // 클릭 시 해당 위치로 지도 이동
        onTap: () {
          _tMapService.moveToLocation(routePoint.latitude, routePoint.longitude, 16);
          setState(() {
            _selectedRoute = routePoint; // 선택된 경로 업데이트
          });
        },
      ),
    );
  }

  // 차량 추가 다이얼로그 표시
  void _showAddVehicleDialog() {
    final TextEditingController nameController = TextEditingController();
    final FocusNode focusNode = FocusNode();
    bool isProcessing = false; // 중복 처리 방지

    // 차량 추가 처리 함수
    void processVehicleAdd() {
      if (isProcessing) return; // 이미 처리 중이면 중복 실행 방지
      isProcessing = true;

      final String vehicleName = nameController.text.trim();

      // 현재 차량 수 확인
      final currentCount = vehicleCount;

      // 최대 10대까지만 추가 가능
      if (currentCount < 10) {
        try {
          // RouteManager를 통해 새 차량 추가 (이름 포함)
          _routeManager.ensureVehicleCount(currentCount + 1, vehicleName);

          setState(() {
            // 새로 추가된 차량으로 자동 선택
            _selectedVehicleId = _routeManager.allRoutes.last.vehicleId;

            // UI 업데이트
            _updateVehicleRouteInfo();
          });
        } catch (e) {
          print('차량 추가 오류: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('차량 추가 중 오류가 발생했습니다: $e')),
          );
        }
      } else {
        // 최대 차량 수 초과 알림
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('최대 10대까지만 추가할 수 있습니다')),
        );
      }

      Navigator.of(context).pop();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('차량 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: '차량 이름',
                hintText: '예: 1호차 오전, 2호차 오후, 3호차 오전 등',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              // 편집 완료 시 호출됨 (엔터 키 누를 때)
              onEditingComplete: processVehicleAdd,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: processVehicleAdd,
            child: const Text('추가'),
          ),
        ],
      ),
    ).then((_) {
      // 다이얼로그가 닫힐 때 컨트롤러와 포커스 노드 해제
      nameController.dispose();
      focusNode.dispose();
    });
  }
}
