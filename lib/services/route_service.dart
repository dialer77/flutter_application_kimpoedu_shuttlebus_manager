import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../models/shuttle_route.dart';

class RouteService extends GetxService {
  // 경로 로드 완료 여부
  final RxBool isLoaded = false.obs;

  // 모든 셔틀 노선 정보
  final RxList<ShuttleRoute> routes = <ShuttleRoute>[].obs;

  // 테스트용 기본 데이터
  final List<ShuttleRoute> _defaultRoutes = [
    ShuttleRoute(
      busNumber: 1,
      name: "1호차",
      times: [
        RouteTime(isMorning: true, routeData: []),
        RouteTime(isMorning: false, routeData: []),
      ],
    ),
    ShuttleRoute(
      busNumber: 2,
      name: "2호차",
      times: [
        RouteTime(isMorning: true, routeData: []),
        RouteTime(isMorning: false, routeData: []),
      ],
    ),
  ];

  // 초기화 메서드
  Future<RouteService> init() async {
    try {
      // 실제로는 assets 또는 네트워크에서 로드
      await loadRoutesFromAsset('assets/routes.json');
    } catch (e) {
      print('노선 데이터 로드 실패, 기본 데이터 사용: $e');
      // 오류 시 기본 데이터 사용
      routes.value = _defaultRoutes;
    }

    isLoaded.value = true;
    return this;
  }

  // 에셋에서 노선 데이터 로드
  Future<void> loadRoutesFromAsset(String assetPath) async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final jsonData = json.decode(jsonString) as List;

      routes.value = jsonData.map((routeJson) => ShuttleRoute.fromJson(routeJson)).toList();

      print('${routes.length}개 노선 로드 완료');
    } catch (e) {
      print('에셋에서 노선 데이터 로드 실패: $e');
      rethrow;
    }
  }

  // 네트워크에서 노선 데이터 로드 (필요 시 구현)
  Future<void> loadRoutesFromNetwork(String url) async {
    // HTTP 요청 구현
  }

  // 사용 가능한 버스 번호 목록 가져오기
  List<int> getAvailableBusNumbers() {
    return routes.map((route) => route.busNumber).toList();
  }

  // 특정 버스와 시간대의 경로 데이터 가져오기
  List<dynamic>? getRouteData(int busNumber, bool isMorning) {
    final route = routes.firstWhereOrNull((r) => r.busNumber == busNumber);
    if (route == null) return null;

    final time = route.times.firstWhereOrNull((t) => t.isMorning == isMorning);
    return time?.routeData;
  }
}
