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

  // 현재 선택된 시간대 저장
  bool _currentIsAM = true;

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

  // 특정 차량 ID의 경로점 개수 가져오기 (수정)
  int getRoutePointCount(int vehicleId, {bool? isAM}) {
    // isAM이 제공되면 해당 시간대의 경로만 확인, 아니면 현재 선택된 시간대
    final currentIsAM = isAM ?? _currentIsAM;

    // 해당 차량 및 시간대(오전/오후)의 경로 목록 가져오기
    final routes = _routes.where((route) => route.vehicleId == vehicleId && route.isAM == currentIsAM).toList();

    // 경로가 있는 경우 첫 번째 경로의 포인트 개수 반환
    if (routes.isNotEmpty) {
      return routes.first.points.length;
    }

    return 0;
  }

  // 특정 차량 ID의 경로점 목록 가져오기 (수정)
  List<RoutePoint> getRoutePoints(int vehicleId, {bool? isAM}) {
    // isAM이 제공되면 해당 시간대의 경로만 확인, 아니면 현재 선택된 시간대
    final currentIsAM = isAM ?? _currentIsAM;

    // 해당 차량 및 시간대(오전/오후)의 경로 목록 가져오기
    final routes = _routes.where((route) => route.vehicleId == vehicleId && route.isAM == currentIsAM).toList();

    // 경로가 있는 경우 첫 번째 경로의 포인트 반환
    if (routes.isNotEmpty) {
      return routes.first.points;
    }

    return [];
  }

  // 차량 경로에 포인트 추가 (시간대 고려하도록 수정)
  void addRoutePoint(int vehicleId, RoutePoint point, {bool? isAM}) {
    // isAM이 제공되면 해당 시간대의 경로만 확인, 아니면 현재 선택된 시간대
    final currentIsAM = isAM ?? _currentIsAM;

    // 해당 차량 및 시간대(오전/오후)의 경로 확인
    final routes = _routes.where((route) => route.vehicleId == vehicleId && route.isAM == currentIsAM).toList();

    // 경로가 없는 경우 새 경로 생성
    if (routes.isEmpty) {
      // 새 경로를 추가하고, 해당 경로에 포인트 추가
      // 첫 번째 포인트이므로 시작 지점으로 설정
      final newPoint = RoutePoint(
          id: point.id,
          name: point.name,
          address: point.address,
          latitude: point.latitude,
          longitude: point.longitude,
          type: 'start', // 첫 번째 포인트는 시작 지점으로 설정
          sequence: 1);

      final newRoute = addRoute(
        vehicleId: vehicleId,
        isAM: currentIsAM, // 현재 선택된 시간대(오전/오후)
        points: [newPoint],
        totalDistance: 0.0, // 초기값
        estimatedTime: 0, // 초기값
      );
    } else {
      final route = routes.first;

      // 기존 경로의 포인트 수 확인
      if (route.points.isEmpty) {
        // 첫 번째 포인트라면 시작 지점으로 설정
        final newPoint = RoutePoint(
            id: point.id,
            name: point.name,
            address: point.address,
            latitude: point.latitude,
            longitude: point.longitude,
            type: 'start', // 시작 지점
            sequence: 1);
        route.points.add(newPoint);
      } else {
        // 이미 포인트가 있는 경우
        // 마지막 포인트가 종료 지점으로 설정되어 있었다면 일반 경유지로 변경
        if (route.points.last.type == 'end') {
          route.points.last = RoutePoint(
              id: route.points.last.id,
              name: route.points.last.name,
              address: route.points.last.address,
              latitude: route.points.last.latitude,
              longitude: route.points.last.longitude,
              type: 'waypoint', // 경유지로 변경
              sequence: route.points.last.sequence);
        }

        // 새 포인트는 종료 지점으로 설정
        final newPoint = RoutePoint(
            id: point.id,
            name: point.name,
            address: point.address,
            latitude: point.latitude,
            longitude: point.longitude,
            type: 'end', // 종료 지점
            sequence: route.points.length + 1);
        route.points.add(newPoint);
      }

      // 거리 및 시간 재계산
      _recalculateRouteInfo(routes.first);
    }

    // 경로에 2개 이상의 지점이 있으면 첫 번째는 시작, 마지막은 종료 지점으로 설정
    _updateRouteEndpoints(vehicleId);
  }

  // 경로의 시작 지점과 종료 지점 업데이트
  void _updateRouteEndpoints(int vehicleId) {
    final routes = getRoutesByVehicle(vehicleId);
    if (routes.isEmpty || routes.first.points.isEmpty) {
      return;
    }

    final route = routes.first;
    final points = route.points;

    // 첫 번째 지점을 시작 지점으로 설정
    if (points.isNotEmpty && points.first.type != 'start') {
      points[0] = RoutePoint(
          id: points.first.id,
          name: points.first.name,
          address: points.first.address,
          latitude: points.first.latitude,
          longitude: points.first.longitude,
          type: 'start', // 시작 지점
          sequence: points.first.sequence);
    }

    // 마지막 지점을 종료 지점으로 설정
    if (points.length > 1 && points.last.type != 'end') {
      points[points.length - 1] = RoutePoint(
          id: points.last.id,
          name: points.last.name,
          address: points.last.address,
          latitude: points.last.latitude,
          longitude: points.last.longitude,
          type: 'end', // 종료 지점
          sequence: points.last.sequence);
    }
  }

  // 특정 인덱스의 경로점 제거 (시간대 고려)
  RoutePoint? removeRoutePoint(int vehicleId, int index, {bool? isAM}) {
    final currentIsAM = isAM ?? _currentIsAM;
    final routes = _routes.where((route) => route.vehicleId == vehicleId && route.isAM == currentIsAM).toList();

    if (routes.isEmpty || index < 0 || index >= routes.first.points.length) {
      return null;
    }

    // 특정 인덱스의 포인트 제거 및 반환
    final removedPoint = routes.first.points.removeAt(index);

    // 경로 지점이 없으면 처리할 필요 없음
    if (routes.first.points.isEmpty) {
      return removedPoint;
    }

    // 지점 제거 후 시작/종료 지점 재설정
    _updateRouteEndpoints(vehicleId);

    // 거리 및 시간 재계산
    _recalculateRouteInfo(routes.first);

    return removedPoint;
  }

  // 차량의 마지막 경로점 제거 (제거된 포인트 반환) (수정)
  RoutePoint? removeLastRoutePoint(int vehicleId) {
    final routes = getRoutesByVehicle(vehicleId);
    if (routes.isEmpty || routes.first.points.isEmpty) {
      return null;
    }

    // 마지막 포인트 제거 및 반환
    final removedPoint = routes.first.points.removeLast();

    // 포인트가 남아있으면 마지막 포인트를 종료 지점으로 설정
    if (routes.first.points.isNotEmpty) {
      final lastPoint = routes.first.points.last;
      routes.first.points[routes.first.points.length - 1] = RoutePoint(
          id: lastPoint.id,
          name: lastPoint.name,
          address: lastPoint.address,
          latitude: lastPoint.latitude,
          longitude: lastPoint.longitude,
          type: 'end', // 종료 지점으로 설정
          sequence: lastPoint.sequence);
    }

    // 거리 및 시간 재계산
    _recalculateRouteInfo(routes.first);

    return removedPoint;
  }

  // 차량 경로의 시작 지점 가져오기 (시간대 고려)
  RoutePoint? getStartPoint(int vehicleId, {bool? isAM}) {
    final currentIsAM = isAM ?? _currentIsAM;
    final points = getRoutePoints(vehicleId, isAM: currentIsAM);

    for (final point in points) {
      if (point.type == 'start') {
        return point;
      }
    }

    // 시작 지점이 명시적으로 설정되지 않은 경우, 첫 번째 지점 반환
    return points.isNotEmpty ? points.first : null;
  }

  // 차량 경로의 종료 지점 가져오기 (시간대 고려)
  RoutePoint? getEndPoint(int vehicleId, {bool? isAM}) {
    final currentIsAM = isAM ?? _currentIsAM;
    final points = getRoutePoints(vehicleId, isAM: currentIsAM);

    for (final point in points) {
      if (point.type == 'end') {
        return point;
      }
    }

    // 종료 지점이 명시적으로 설정되지 않은 경우, 마지막 지점 반환
    return points.isNotEmpty ? points.last : null;
  }

  // 특정 지점을 시작 지점으로 설정
  bool setStartPoint(int vehicleId, int pointIndex) {
    final routes = getRoutesByVehicle(vehicleId);
    if (routes.isEmpty || routes.first.points.isEmpty || pointIndex < 0 || pointIndex >= routes.first.points.length) {
      return false;
    }

    final route = routes.first;

    // 먼저 기존 시작 지점이 있으면 경유지로 변경
    for (int i = 0; i < route.points.length; i++) {
      if (route.points[i].type == 'start' && i != pointIndex) {
        final point = route.points[i];
        route.points[i] = RoutePoint(
            id: point.id,
            name: point.name,
            address: point.address,
            latitude: point.latitude,
            longitude: point.longitude,
            type: 'waypoint', // 경유지로 변경
            sequence: point.sequence);
      }
    }

    // 선택한 지점을 시작 지점으로 설정
    final point = route.points[pointIndex];
    route.points[pointIndex] = RoutePoint(
        id: point.id,
        name: point.name,
        address: point.address,
        latitude: point.latitude,
        longitude: point.longitude,
        type: 'start', // 시작 지점으로 설정
        sequence: point.sequence);

    return true;
  }

  // 특정 지점을 종료 지점으로 설정
  bool setEndPoint(int vehicleId, int pointIndex) {
    final routes = getRoutesByVehicle(vehicleId);
    if (routes.isEmpty || routes.first.points.isEmpty || pointIndex < 0 || pointIndex >= routes.first.points.length) {
      return false;
    }

    final route = routes.first;

    // 먼저 기존 종료 지점이 있으면 경유지로 변경
    for (int i = 0; i < route.points.length; i++) {
      if (route.points[i].type == 'end' && i != pointIndex) {
        final point = route.points[i];
        route.points[i] = RoutePoint(
            id: point.id,
            name: point.name,
            address: point.address,
            latitude: point.latitude,
            longitude: point.longitude,
            type: 'waypoint', // 경유지로 변경
            sequence: point.sequence);
      }
    }

    // 선택한 지점을 종료 지점으로 설정
    final point = route.points[pointIndex];
    route.points[pointIndex] = RoutePoint(
        id: point.id,
        name: point.name,
        address: point.address,
        latitude: point.latitude,
        longitude: point.longitude,
        type: 'end', // 종료 지점으로 설정
        sequence: point.sequence);

    return true;
  }

  // 경로 순서 최적화 (시작 지점에서 종료 지점까지)
  bool optimizeRoute(int vehicleId, {bool? isAM}) {
    final currentIsAM = isAM ?? _currentIsAM;
    final routes = _routes.where((route) => route.vehicleId == vehicleId && route.isAM == currentIsAM).toList();

    if (routes.isEmpty || routes.first.points.length < 3) {
      // 최소 3개 이상의 지점이 있어야 최적화 가능
      return false;
    }

    final route = routes.first;
    final startPoint = getStartPoint(vehicleId, isAM: currentIsAM);
    final endPoint = getEndPoint(vehicleId, isAM: currentIsAM);

    if (startPoint == null || endPoint == null) {
      return false;
    }

    // 시작과 종료 지점을 제외한 경유지만 추출
    final waypoints = route.points.where((p) => p.type != 'start' && p.type != 'end').toList();

    if (waypoints.isEmpty) {
      // 경유지가 없으면 최적화할 필요 없음
      return true;
    }

    // 경유지를 거리에 따라 정렬 (간단한 최근접 이웃 알고리즘)
    List<RoutePoint> sortedWaypoints = [];
    List<RoutePoint> remainingWaypoints = List.from(waypoints);

    // 시작 지점부터 시작
    RoutePoint current = startPoint;

    while (remainingWaypoints.isNotEmpty) {
      // 현재 지점에서 가장 가까운 다음 지점 찾기
      int nearestIndex = 0;
      double minDistance = double.infinity;

      for (int i = 0; i < remainingWaypoints.length; i++) {
        final distance = _calculateDistance(current.latitude, current.longitude, remainingWaypoints[i].latitude, remainingWaypoints[i].longitude);

        if (distance < minDistance) {
          minDistance = distance;
          nearestIndex = i;
        }
      }

      // 가장 가까운 지점을 경로에 추가
      current = remainingWaypoints[nearestIndex];
      sortedWaypoints.add(current);
      remainingWaypoints.removeAt(nearestIndex);
    }

    // 최적화된 경로로 기존 경로 대체
    route.points.clear();
    route.points.add(startPoint); // 시작 지점
    route.points.addAll(sortedWaypoints); // 정렬된 경유지
    route.points.add(endPoint); // 종료 지점

    // 시퀀스 번호 업데이트
    for (int i = 0; i < route.points.length; i++) {
      final point = route.points[i];
      route.points[i] = RoutePoint(id: point.id, name: point.name, address: point.address, latitude: point.latitude, longitude: point.longitude, type: point.type, sequence: i + 1);
    }

    // 거리 및 시간 재계산
    _recalculateRouteInfo(route);

    return true;
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

  // 차량 수 확인 및 업데이트
  void ensureVehicleCount(int count, bool isAM) {
    // 기존 차량 ID 수집
    final existingVehicleIds = <int>{};
    for (final route in _routes) {
      existingVehicleIds.add(route.vehicleId);
    }

    // 필요한 차량 ID들
    final neededVehicleIds = List.generate(count, (index) => index);

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
    // 현재 시간대 업데이트
    _currentIsAM = isAM;

    // 다른 메서드에서는 이미 현재 선택된 시간대를 참조하므로
    // 여기서는 추가 작업이 필요 없음
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

  // 모든 경로 데이터를 JSON으로 내보내기
  Map<String, dynamic> exportToJson() {
    final routesJson = _routes
        .map((route) => {
              'routeId': route.routeId,
              'vehicleId': route.vehicleId,
              'isAM': route.isAM,
              'points': route.points
                  .map((point) => {
                        'id': point.id,
                        'name': point.name,
                        'latitude': point.latitude,
                        'longitude': point.longitude,
                        'address': point.address,
                        'type': point.type,
                        'sequence': point.sequence,
                      })
                  .toList(),
              'totalDistance': route.totalDistance,
              'estimatedTime': route.estimatedTime,
              'isActive': route.isActive,
              'coordinates': route.coordinates,
            })
        .toList();

    return {
      'routes': routesJson,
      'nextRouteId': _nextRouteId,
      'version': '1.0', // 버전 정보 추가
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // JSON에서 경로 데이터 가져오기
  void importFromJson(Map<String, dynamic> json) {
    // 기존 데이터 초기화
    clearAllRoutes();

    // 라우트 ID 설정
    if (json.containsKey('nextRouteId')) {
      _nextRouteId = json['nextRouteId'];
    }

    // 경로 데이터 로드
    if (json.containsKey('routes')) {
      final routesJson = json['routes'] as List;

      for (var routeJson in routesJson) {
        final List<RoutePoint> points = [];

        // 포인트 데이터 로드
        if (routeJson.containsKey('points')) {
          final pointsJson = routeJson['points'] as List;

          for (var pointJson in pointsJson) {
            points.add(RoutePoint(
              id: pointJson['id'],
              name: pointJson['name'],
              latitude: pointJson['latitude'],
              longitude: pointJson['longitude'],
              address: pointJson['address'],
              type: pointJson['type'],
              sequence: pointJson['sequence'] ?? 0,
            ));
          }
        }

        // 경로 좌표 로드
        List<List<double>> coordinates = [];
        if (routeJson.containsKey('coordinates')) {
          final coordsJson = routeJson['coordinates'] as List;
          for (var coord in coordsJson) {
            if (coord is List) {
              coordinates.add(coord.map<double>((e) => e is num ? e.toDouble() : 0.0).toList());
            }
          }
        }

        // 경로 추가
        final route = RouteInfo(
          routeId: routeJson['routeId'],
          vehicleId: routeJson['vehicleId'],
          isAM: routeJson['isAM'],
          points: points,
          totalDistance: routeJson['totalDistance'],
          estimatedTime: routeJson['estimatedTime'],
          isActive: routeJson['isActive'] ?? true,
          coordinates: coordinates,
        );

        _routes.add(route);
      }
    }
  }

  // 특정 차량 ID의 모든 경로 제거
  void removeVehicle(int vehicleId) {
    _routes.removeWhere((route) => route.vehicleId == vehicleId);

    // 나머지 차량에 대한 경로가 있는지 확인하고 필요한 경우 생성
    final remainingVehicleIds = <int>{};
    for (final route in _routes) {
      remainingVehicleIds.add(route.vehicleId);
    }

    // 차량 ID 정렬 (순서대로)
    final sortedVehicleIds = remainingVehicleIds.toList()..sort();
  }

  // 현재 시간대(오전/오후)에 맞는 경로 가져오기
  RouteInfo? getCurrentRoute(int vehicleId, bool isAM) {
    final routes = _routes.where((route) => route.vehicleId == vehicleId && route.isAM == isAM).toList();

    return routes.isNotEmpty ? routes.first : null;
  }

  // 현재 시간대 설정
  void setCurrentTimeOfDay(bool isAM) {
    _currentIsAM = isAM;
  }

  // 현재 시간대 확인
  bool get currentIsAM => _currentIsAM;

  // 경로의 전체 포인트 목록 업데이트
  void updateRoutePoints(List<RoutePoint> newPoints, {int? vehicleId, bool? isAM}) {
    // 경로 업데이트를 적용할 차량 ID 결정
    final targetVehicleId = vehicleId ?? (newPoints.isNotEmpty ? int.tryParse(newPoints.first.id.split('_')[1]) ?? 0 : 0);

    // 시간대 결정 (제공되지 않으면 현재 시간대 사용)
    final currentIsAM = isAM ?? _currentIsAM;

    // 해당 차량의 경로 찾기
    final routes = _routes.where((route) => route.vehicleId == targetVehicleId && route.isAM == currentIsAM).toList();

    if (routes.isEmpty) {
      // 해당 경로가 없으면 새로 생성
      if (newPoints.isNotEmpty) {
        addRoute(
          vehicleId: targetVehicleId,
          isAM: currentIsAM,
          points: newPoints,
          totalDistance: 0.0, // 나중에 재계산됨
          estimatedTime: 0, // 나중에 재계산됨
        );

        // 경로 정보 재계산
        _recalculateRouteInfo(_routes.last);

        // 시작점과 끝점 타입 업데이트
        _updateRouteEndpoints(targetVehicleId);
      }
      return;
    }

    // 기존 경로에 새 포인트 목록 적용
    final route = routes.first;
    route.points.clear();

    if (newPoints.isNotEmpty) {
      // 새 포인트 추가 및 시퀀스 업데이트
      for (int i = 0; i < newPoints.length; i++) {
        final point = newPoints[i];
        // 기존 포인트 타입 유지하면서 시퀀스만 업데이트
        route.points.add(RoutePoint(
          id: point.id,
          name: point.name,
          address: point.address,
          latitude: point.latitude,
          longitude: point.longitude,
          type: point.type, // 기존 타입 유지
          sequence: i + 1, // 시퀀스 업데이트
        ));
      }

      // 시작점과 끝점 타입 설정 확인
      _updateRouteEndpoints(targetVehicleId);

      // 경로 정보 재계산
      _recalculateRouteInfo(route);
    }

    print('차량 ID $targetVehicleId의 경로 포인트가 업데이트되었습니다. 포인트 수: ${route.points.length}');
  }

  // 경로 선 좌표 업데이트 - 단순화된 버전
  void updateRouteCoordinates(int vehicleId, List<List<double>> coordinates, {bool? isAM}) {
    final currentIsAM = isAM ?? _currentIsAM;
    final routes = _routes.where((route) => route.vehicleId == vehicleId && route.isAM == currentIsAM).toList();

    if (routes.isNotEmpty) {
      routes.first.coordinates = coordinates;
      print('차량 ID $vehicleId의 경로 좌표가 업데이트되었습니다. 좌표 수: ${coordinates.length}');
    }
  }

  // 경로 선 좌표 가져오기 - 단순화된 버전
  List<List<double>> getRouteCoordinates(int vehicleId, {bool? isAM}) {
    final currentIsAM = isAM ?? _currentIsAM;
    final routes = _routes.where((route) => route.vehicleId == vehicleId && route.isAM == currentIsAM).toList();

    if (routes.isNotEmpty) {
      return routes.first.coordinates;
    }
    return [];
  }
}
