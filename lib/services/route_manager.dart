import 'dart:math';

import '../models/route_info.dart';
import '../models/route_point.dart';

// 경로 관리자 클래스
class RouteManager {
  static final RouteManager _instance = RouteManager._internal();
  factory RouteManager() => _instance;
  RouteManager._internal();

  final List<RouteInfo> _routes = [];
  int _nextRouteId = 1;

  // 모든 경로 가져오기
  List<RouteInfo> get allRoutes => List.unmodifiable(_routes);

  // 특정 차량의 경로 가져오기
  List<RouteInfo> getRoutesByVehicle(int vehicleId) {
    return _routes.where((route) => route.vehicleId == vehicleId).toList();
  }

  // 오전/오후 경로 가져오기
  List<RouteInfo> getRoutesByTimeOfDay(bool isAM) {
    return _routes.where((route) => route.isAM == isAM).toList();
  }

  // 새 경로 추가
  RouteInfo addRoute({
    required int vehicleId,
    required bool isAM,
    required List<RoutePoint> points,
    required double totalDistance,
    required int estimatedTime,
  }) {
    final route = RouteInfo(
      routeId: _nextRouteId++,
      vehicleId: vehicleId,
      isAM: isAM,
      points: points,
      totalDistance: totalDistance,
      estimatedTime: estimatedTime,
    );

    _routes.add(route);
    return route;
  }

  // 경로 삭제
  bool removeRoute(int routeId) {
    final index = _routes.indexWhere((route) => route.routeId == routeId);
    if (index >= 0) {
      _routes.removeAt(index);
      return true;
    }
    return false;
  }

  // 경로 상태 변경 (활성/비활성)
  bool toggleRouteStatus(int routeId) {
    final route = _routes.firstWhere(
      (route) => route.routeId == routeId,
      orElse: () => throw Exception('Route not found'),
    );

    route.isActive = !route.isActive;
    return route.isActive;
  }

  // 모든 경로 초기화
  void clearAllRoutes() {
    _routes.clear();
    _nextRouteId = 1;
  }

  // 특정 차량 ID의 경로점 개수 가져오기
  int getRoutePointCount(int vehicleId) {
    // 해당 차량의 경로 목록 가져오기
    final routes = getRoutesByVehicle(vehicleId);

    // 경로가 있는 경우 첫 번째 경로의 포인트 개수 반환
    if (routes.isNotEmpty) {
      return routes.first.points.length;
    }

    return 0;
  }

  // 특정 차량 ID의 경로점 목록 가져오기
  List<RoutePoint> getRoutePoints(int vehicleId) {
    // 해당 차량의 경로 목록 가져오기
    final routes = getRoutesByVehicle(vehicleId);

    // 경로가 있는 경우 첫 번째 경로의 포인트 반환
    if (routes.isNotEmpty) {
      return routes.first.points;
    }

    return [];
  }

  // 차량 경로에 포인트 추가
  void addRoutePoint(int vehicleId, RoutePoint point) {
    // 해당 차량의 경로 확인
    final routes = getRoutesByVehicle(vehicleId);

    // 경로가 없는 경우 새 경로 생성
    if (routes.isEmpty) {
      // 새 경로를 추가하고, 해당 경로에 포인트 추가
      const isAM = true; // 기본값, 필요에 따라 변경
      final newRoute = addRoute(
        vehicleId: vehicleId,
        isAM: isAM,
        points: [point],
        totalDistance: 0.0, // 초기값
        estimatedTime: 0, // 초기값
      );
    } else {
      // 기존 경로에 포인트 추가 (첫 번째 경로 사용)
      routes.first.points.add(point);

      // 거리 및 시간 재계산 (필요한 경우)
      _recalculateRouteInfo(routes.first);
    }
  }

  // 경로 정보 재계산 (거리, 시간)
  void _recalculateRouteInfo(RouteInfo route) {
    if (route.points.length < 2) {
      route.totalDistance = 0.0;
      route.estimatedTime = 0;
      return;
    }

    // 점 사이의 거리 계산
    double totalDist = 0.0;
    for (int i = 0; i < route.points.length - 1; i++) {
      final p1 = route.points[i];
      final p2 = route.points[i + 1];
      totalDist += _calculateDistance(p1.latitude, p1.longitude, p2.latitude, p2.longitude);
    }

    route.totalDistance = totalDist;

    // 예상 시간 계산 (평균 속도 40km/h 가정)
    // 거리(km) / 속도(km/h) * 60 = 시간(분)
    route.estimatedTime = (totalDist / 40.0 * 60).round();
  }

  // 두 지점 간 거리 계산 (하버사인 공식)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371.0; // 지구 반경 (km)
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) + cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  // 각도를 라디안으로 변환
  double _toRadians(double degree) {
    return degree * pi / 180.0;
  }

  // 차량의 마지막 경로점 제거 (제거된 포인트 반환)
  RoutePoint? removeLastRoutePoint(int vehicleId) {
    final routes = getRoutesByVehicle(vehicleId);
    if (routes.isEmpty || routes.first.points.isEmpty) {
      return null;
    }

    // 마지막 포인트 제거 및 반환
    final removedPoint = routes.first.points.removeLast();

    // 거리 및 시간 재계산
    _recalculateRouteInfo(routes.first);

    return removedPoint;
  }

  // 특정 인덱스의 경로점 제거
  RoutePoint? removeRoutePoint(int vehicleId, int index) {
    final routes = getRoutesByVehicle(vehicleId);

    if (routes.isEmpty || index < 0 || index >= routes.first.points.length) {
      return null;
    }

    // 특정 인덱스의 포인트 제거 및 반환
    final removedPoint = routes.first.points.removeAt(index);

    // 거리 및 시간 재계산
    _recalculateRouteInfo(routes.first);

    return removedPoint;
  }

  // 차량 수 확인 및 업데이트
  void ensureVehicleCount(int count, bool isAM) {
    // 기존 차량 ID 수집
    final existingVehicleIds = <int>{};
    for (final route in _routes) {
      existingVehicleIds.add(route.vehicleId);
    }

    // 필요한 차량 ID들
    final neededVehicleIds = List.generate(count, (index) => index + 1);

    // 각 필요한 차량 ID에 대해 경로 확인 및 생성
    for (final vehicleId in neededVehicleIds) {
      if (!existingVehicleIds.contains(vehicleId)) {
        // 차량에 대한 경로가 없으면 빈 경로 생성
        addRoute(
          vehicleId: vehicleId,
          isAM: isAM,
          points: [],
          totalDistance: 0.0,
          estimatedTime: 0,
        );
      }
    }
  }

  // 모든 경로의 시간 설정 업데이트
  void updateAllRoutesTime(bool isAM) {
    for (final route in _routes) {
      route.isAM = isAM;
    }
  }

  // 특정 경로 가져오기 (없으면 생성)
  RouteInfo getOrCreateRoute(int vehicleId, bool isAM) {
    // 해당 차량의 경로 찾기
    final routes = getRoutesByVehicle(vehicleId);

    if (routes.isEmpty) {
      // 경로가 없으면 새로 생성
      return addRoute(
        vehicleId: vehicleId,
        isAM: isAM,
        points: [],
        totalDistance: 0.0,
        estimatedTime: 0,
      );
    } else {
      // 있으면 첫 번째 경로 반환
      return routes.first;
    }
  }
}
