import 'dart:math';

import 'package:flutter_application_kimpoedu_shuttlebus_manager/constants/enum_types.dart';

import '../models/route_info.dart';
import '../models/route_point.dart';

// 경로 관리자 클래스
class RouteManager {
  static final RouteManager _instance = RouteManager._internal();
  factory RouteManager() => _instance;
  RouteManager._internal() {
    // 기본 그룹 생성
    _routeGroups[defaultGroupName] = [];
  }

  // 그룹별로 경로를 관리하는 Map 구조로 변경
  final Map<String, List<RouteInfo>> _routeGroups = {};
  int _nextRouteId = 1;

  // 기본 그룹명
  static const String defaultGroupName = '기본 그룹';

  // 현재 활성 그룹
  String _currentGroup = defaultGroupName;

  // 현재 선택된 시간대 저장
  bool _currentIsAM = true;

  // 현재 그룹 설정/가져오기
  String get currentGroup => _currentGroup;
  void setCurrentGroup(String groupName) {
    _currentGroup = groupName;
    // 그룹이 없으면 생성
    if (!_routeGroups.containsKey(groupName)) {
      _routeGroups[groupName] = [];
    }
  }

  // 모든 그룹명 가져오기
  List<String> get allGroupNames => _routeGroups.keys.toList();

  // 특정 그룹의 모든 경로 가져오기
  List<RouteInfo> getRoutesByGroup(String groupName) {
    return List.unmodifiable(_routeGroups[groupName] ?? []);
  }

  // 현재 그룹의 모든 경로 가져오기 (기존 API 호환성)
  List<RouteInfo> get allRoutes => getRoutesByGroup(_currentGroup);

  // 전체 그룹의 모든 경로 가져오기
  List<RouteInfo> get allRoutesFromAllGroups {
    final allRoutes = <RouteInfo>[];
    for (final routes in _routeGroups.values) {
      allRoutes.addAll(routes);
    }
    return allRoutes;
  }

  // 특정 차량의 경로 가져오기 (현재 그룹에서)
  List<RouteInfo> getRoutesByVehicle(int vehicleId) {
    final currentRoutes = _routeGroups[_currentGroup] ?? [];
    return currentRoutes.where((route) => route.vehicleId == vehicleId).toList();
  }

  // 특정 그룹에서 특정 차량의 경로 가져오기
  List<RouteInfo> getRoutesByVehicleInGroup(int vehicleId, String groupName) {
    final routes = _routeGroups[groupName] ?? [];
    return routes.where((route) => route.vehicleId == vehicleId).toList();
  }

  // 새 경로 추가
  RouteInfo addRoute({
    required int vehicleId,
    required String vehicleName,
    required List<RoutePoint> points,
    required double totalDistance,
    required int estimatedTime,
    String? groupName,
  }) {
    final targetGroup = groupName ?? _currentGroup;

    // 그룹이 없으면 생성
    if (!_routeGroups.containsKey(targetGroup)) {
      _routeGroups[targetGroup] = [];
    }

    final route = RouteInfo(
      vehicleId: vehicleId,
      vehicleName: vehicleName,
      points: points,
      totalDistance: totalDistance,
      estimatedTime: estimatedTime,
    );

    _routeGroups[targetGroup]!.add(route);
    return route;
  }

  // 그룹 생성
  void createGroup(String groupName) {
    if (!_routeGroups.containsKey(groupName)) {
      _routeGroups[groupName] = [];
    }
  }

  // 그룹 삭제
  bool deleteGroup(String groupName) {
    if (groupName == defaultGroupName) {
      return false; // 기본 그룹은 삭제 불가
    }
    return _routeGroups.remove(groupName) != null;
  }

  // 그룹 이름 변경
  bool renameGroup(String oldName, String newName) {
    if (oldName == defaultGroupName || !_routeGroups.containsKey(oldName) || _routeGroups.containsKey(newName)) {
      return false;
    }

    final routes = _routeGroups.remove(oldName);
    if (routes != null) {
      _routeGroups[newName] = routes;

      // 현재 그룹이 변경된 그룹이면 업데이트
      if (_currentGroup == oldName) {
        _currentGroup = newName;
      }
      return true;
    }
    return false;
  }

  // 경로를 다른 그룹으로 이동
  bool moveRouteToGroup(int vehicleId, String fromGroup, String toGroup) {
    final fromRoutes = _routeGroups[fromGroup];
    if (fromRoutes == null) return false;

    final routeIndex = fromRoutes.indexWhere((route) => route.vehicleId == vehicleId);
    if (routeIndex == -1) return false;

    // 대상 그룹이 없으면 생성
    if (!_routeGroups.containsKey(toGroup)) {
      _routeGroups[toGroup] = [];
    }

    final route = fromRoutes.removeAt(routeIndex);
    _routeGroups[toGroup]!.add(route);

    return true;
  }

  // 그룹 내에서 차량 순서 변경
  bool reorderVehicleInGroup(String groupName, int oldIndex, int newIndex) {
    final routes = _routeGroups[groupName];
    if (routes == null || oldIndex < 0 || newIndex < 0 || oldIndex >= routes.length || newIndex >= routes.length) {
      return false;
    }

    final route = routes.removeAt(oldIndex);
    routes.insert(newIndex, route);
    return true;
  }

  // 모든 경로 초기화
  void _clearAllRoutes() {
    _routeGroups.clear();
    _nextRouteId = 1;
    // 기본 그룹 다시 생성
    _routeGroups[defaultGroupName] = [];
    _currentGroup = defaultGroupName;
  }

  // 특정 차량 ID의 경로점 개수 가져오기 (수정)
  int getRoutePointCount(int vehicleId) {
    return getRoutePoints(vehicleId).length;
  }

  String getVehicleName(int vehicleId) {
    // 현재 그룹에서 먼저 찾기
    final currentRoutes = _routeGroups[_currentGroup]?.where((route) => route.vehicleId == vehicleId).toList() ?? [];
    if (currentRoutes.isNotEmpty) {
      return currentRoutes.first.vehicleName;
    }

    // 현재 그룹에 없으면 모든 그룹에서 찾기
    for (final routes in _routeGroups.values) {
      final foundRoute = routes.where((route) => route.vehicleId == vehicleId).toList();
      if (foundRoute.isNotEmpty) {
        return foundRoute.first.vehicleName;
      }
    }

    return '';
  }

  // 특정 차량 ID의 경로점 목록 가져오기 (수정)
  List<RoutePoint> getRoutePoints(int vehicleId) {
    // 해당 차량의 경로 목록 가져오기
    final routes = _routeGroups[_currentGroup]?.where((route) => route.vehicleId == vehicleId).toList() ?? [];

    // 경로가 있는 경우 첫 번째 경로의 포인트 반환
    if (routes.isNotEmpty) {
      return routes.first.points;
    }

    return [];
  }

  // 차량 경로에 포인트 추가 (시간대 고려하도록 수정)
  void addRoutePoint(int vehicleId, RoutePoint point, {bool? isAM, String? name}) {
    // 해당 차량 및 시간대(오전/오후)의 경로 확인
    final routes = _routeGroups[_currentGroup]?.where((route) => route.vehicleId == vehicleId).toList() ?? [];

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
          type: PointType.start, // 첫 번째 포인트는 시작 지점으로 설정
          sequence: 1);

      addRoute(
        vehicleId: vehicleId,
        vehicleName: '',
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
            type: PointType.start, // 시작 지점
            sequence: 1);
        route.points.add(newPoint);
      } else {
        // end 포인트가 없으면 end 포인트로 설정
        if (route.points.where((point) => point.type == PointType.end).isEmpty) {
          route.points.last = RoutePoint(
              id: route.points.last.id,
              name: route.points.last.name,
              address: route.points.last.address,
              latitude: route.points.last.latitude,
              longitude: route.points.last.longitude,
              type: PointType.end, // 종료 지점
              sequence: route.points.last.sequence);
        }

        // 새 포인트는 일반경유지 지점으로 설정
        final newPoint = RoutePoint(
            id: point.id,
            name: point.name,
            address: point.address,
            latitude: point.latitude,
            longitude: point.longitude,
            type: PointType.waypoint, // 경유지
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
    if (points.isNotEmpty && points.first.type != PointType.start) {
      points[0] = RoutePoint(
          id: points.first.id,
          name: points.first.name,
          address: points.first.address,
          latitude: points.first.latitude,
          longitude: points.first.longitude,
          type: PointType.start, // 시작 지점
          sequence: points.first.sequence);
    }

    // 마지막 지점을 종료 지점으로 설정
    // end 포인트가 없으면 end 포인트로 설정
    if (points.length > 1 && points.where((point) => point.type == PointType.end).isEmpty) {
      points[points.length - 1] = RoutePoint(
          id: points.last.id,
          name: points.last.name,
          address: points.last.address,
          latitude: points.last.latitude,
          longitude: points.last.longitude,
          type: PointType.end, // 종료 지점
          sequence: points.last.sequence);
    }
  }

  // 특정 인덱스의 경로점 제거 (시간대 고려)
  RoutePoint? removeRoutePoint(int vehicleId, int index) {
    final routes = _routeGroups[_currentGroup]?.where((route) => route.vehicleId == vehicleId).toList() ?? [];

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
          type: PointType.end, // 종료 지점으로 설정
          sequence: lastPoint.sequence);
    }

    // 거리 및 시간 재계산
    _recalculateRouteInfo(routes.first);

    return removedPoint;
  }

  // 차량 경로의 시작 지점 가져오기 (시간대 고려)
  RoutePoint? getStartPoint(int vehicleId) {
    final points = getRoutePoints(vehicleId);

    for (final point in points) {
      if (point.type == PointType.start) {
        return point;
      }
    }

    // 시작 지점이 명시적으로 설정되지 않은 경우, 첫 번째 지점 반환
    return points.isNotEmpty ? points.first : null;
  }

  // 차량 경로의 종료 지점 가져오기 (시간대 고려)
  RoutePoint? getEndPoint(int vehicleId) {
    final points = getRoutePoints(vehicleId);

    for (final point in points) {
      if (point.type == PointType.end) {
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
      if (route.points[i].type == PointType.start && i != pointIndex) {
        final point = route.points[i];
        route.points[i] = RoutePoint(
            id: point.id,
            name: point.name,
            address: point.address,
            latitude: point.latitude,
            longitude: point.longitude,
            type: PointType.waypoint, // 경유지로 변경
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
        type: PointType.start, // 시작 지점으로 설정
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
      if (route.points[i].type == PointType.end && i != pointIndex) {
        final point = route.points[i];
        route.points[i] = RoutePoint(
            id: point.id,
            name: point.name,
            address: point.address,
            latitude: point.latitude,
            longitude: point.longitude,
            type: PointType.waypoint, // 경유지로 변경
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
        type: PointType.end, // 종료 지점으로 설정
        sequence: point.sequence);

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

  // 차량 수 확인 및 업데이트 (현재 그룹 기준)
  void ensureVehicleCount(int count, String vehicleName) {
    // 현재 그룹의 기존 차량 ID 수집
    final existingVehicleIds = <int>{};
    final currentRoutes = _routeGroups[_currentGroup] ?? [];
    for (final route in currentRoutes) {
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
          vehicleName: vehicleName,
          points: [],
          totalDistance: 0.0,
          estimatedTime: 0,
        );
      }
    }
  }

  // 특정 경로 가져오기 (없으면 생성)
  RouteInfo getOrCreateRoute(int vehicleId, {String? name}) {
    // 해당 차량의 경로 찾기
    final routes = getRoutesByVehicle(vehicleId);

    if (routes.isEmpty) {
      // 경로가 없으면 새로 생성
      return addRoute(
        vehicleId: vehicleId,
        vehicleName: '',
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
    // 그룹별 경로 데이터 구성
    final groupsJson = <String, dynamic>{};

    for (final groupName in _routeGroups.keys) {
      final routes = _routeGroups[groupName]!;
      groupsJson[groupName] = routes
          .map((route) => {
                'vehicleId': route.vehicleId,
                'vehicleName': route.vehicleName,
                'points': route.points
                    .map((point) => {
                          'id': point.id,
                          'name': point.name,
                          'latitude': point.latitude,
                          'longitude': point.longitude,
                          'address': point.address,
                          'type': point.type.toValue(),
                          'sequence': point.sequence,
                        })
                    .toList(),
                'totalDistance': route.totalDistance,
                'estimatedTime': route.estimatedTime,
                'isActive': route.isActive,
                'coordinates': route.coordinates,
              })
          .toList();
    }

    return {
      'routeGroups': groupsJson, // 새로운 그룹 구조
      'currentGroup': _currentGroup,
      'nextRouteId': _nextRouteId,
      'version': '2.0', // 그룹 지원 버전
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // JSON에서 경로 데이터 가져오기
  void importFromJson(Map<String, dynamic> json) {
    // 기존 데이터 초기화
    _clearAllRoutes();

    // 라우트 ID 설정
    if (json.containsKey('nextRouteId')) {
      _nextRouteId = json['nextRouteId'];
    }

    // 버전 확인 (기존 파일 호환성)
    final version = json['version'] ?? '1.0';

    if (version == '2.0' && json.containsKey('routeGroups')) {
      // 새로운 그룹 구조 로드 (버전 2.0)
      _importGroupedRoutes(json);
    } else if (json.containsKey('routes')) {
      // 기존 단일 리스트 구조 로드 (버전 1.0 호환성)
      _importLegacyRoutes(json);
    }

    // 현재 그룹 설정
    if (json.containsKey('currentGroup')) {
      final currentGroup = json['currentGroup'] as String;
      if (_routeGroups.containsKey(currentGroup)) {
        _currentGroup = currentGroup;
      }
    }

    // 기본 그룹이 없으면 생성
    if (!_routeGroups.containsKey(defaultGroupName)) {
      _routeGroups[defaultGroupName] = [];
    }
  }

  // 그룹 구조 경로 데이터 로드 (버전 2.0)
  void _importGroupedRoutes(Map<String, dynamic> json) {
    final routeGroupsJson = json['routeGroups'] as Map<String, dynamic>;

    for (final groupName in routeGroupsJson.keys) {
      final routesJson = routeGroupsJson[groupName] as List;
      final routes = <RouteInfo>[];

      for (var routeJson in routesJson) {
        final route = _parseRouteFromJson(routeJson);
        if (route != null) {
          routes.add(route);
        }
      }

      _routeGroups[groupName] = routes;
    }
  }

  // 기존 단일 리스트 구조 경로 데이터 로드 (버전 1.0 호환성)
  void _importLegacyRoutes(Map<String, dynamic> json) {
    final routesJson = json['routes'] as List;
    final routes = <RouteInfo>[];

    for (var routeJson in routesJson) {
      final route = _parseRouteFromJson(routeJson);
      if (route != null) {
        routes.add(route);
      }
    }

    // 기본 그룹에 모든 경로 추가
    _routeGroups[defaultGroupName] = routes;
  }

  // JSON에서 RouteInfo 객체 생성 (공통 파싱 로직)
  RouteInfo? _parseRouteFromJson(Map<String, dynamic> routeJson) {
    try {
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
            type: PointTypeExtension.fromValue(pointJson['type']),
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

      // 경로 생성
      return RouteInfo(
        vehicleId: routeJson['vehicleId'],
        vehicleName: routeJson['vehicleName'],
        points: points,
        totalDistance: routeJson['totalDistance'],
        estimatedTime: routeJson['estimatedTime'],
        isActive: routeJson['isActive'] ?? true,
        coordinates: coordinates,
      );
    } catch (e) {
      print('경로 파싱 오류: $e');
      return null;
    }
  }

  // 특정 차량 ID의 모든 경로 제거
  void removeVehicle(int vehicleId) {
    _routeGroups[_currentGroup]?.removeWhere((route) => route.vehicleId == vehicleId);
  }

  // 현재 시간대(오전/오후)에 맞는 경로 가져오기
  RouteInfo? getCurrentRoute(int vehicleId) {
    final routes = _routeGroups[_currentGroup]?.where((route) => route.vehicleId == vehicleId).toList() ?? [];

    return routes.isNotEmpty ? routes.first : null;
  }

  // 현재 시간대 설정
  void setCurrentTimeOfDay(bool isAM) {
    _currentIsAM = isAM;
  }

  // 현재 시간대 확인
  bool get currentIsAM => _currentIsAM;

  // 경로의 전체 포인트 목록 업데이트
  void updateRoutePoints(List<RoutePoint> newPoints, {int? vehicleId, bool? isAM, String? name}) {
    // 경로 업데이트를 적용할 차량 ID 결정
    final targetVehicleId = vehicleId ?? (newPoints.isNotEmpty ? int.tryParse(newPoints.first.id.split('_')[1]) ?? 0 : 0);

    // 해당 차량의 경로 찾기
    final routes = _routeGroups[_currentGroup]?.where((route) => route.vehicleId == targetVehicleId).toList() ?? [];

    if (routes.isEmpty) {
      // 해당 경로가 없으면 새로 생성
      if (newPoints.isNotEmpty) {
        addRoute(
          vehicleId: targetVehicleId,
          vehicleName: '',
          points: newPoints,
          totalDistance: 0.0, // 나중에 재계산됨
          estimatedTime: 0, // 나중에 재계산됨
        );

        // 경로 정보 재계산
        final currentRoutes = _routeGroups[_currentGroup];
        if (currentRoutes != null && currentRoutes.isNotEmpty) {
          _recalculateRouteInfo(currentRoutes.last);
        }

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
  }

  // 경로 선 좌표 업데이트 - 단순화된 버전
  void updateRouteSegments(int vehicleId, List<List<double>> coordinates) {
    final routes = _routeGroups[_currentGroup]?.where((route) => route.vehicleId == vehicleId).toList() ?? [];

    if (routes.isNotEmpty) {
      routes.first.coordinates = coordinates;
    }
  }

  // 경로 선 좌표 가져오기 - 단순화된 버전
  List<List<double>> getRouteCoordinates(int vehicleId) {
    final routes = _routeGroups[_currentGroup]?.where((route) => route.vehicleId == vehicleId).toList() ?? [];

    if (routes.isNotEmpty) {
      return routes.first.coordinates;
    }
    return [];
  }

  // 경로점 순서 변경
  void reorderRoutePoint(int vehicleId, int oldIndex, int newIndex) {
    final routes = getRoutesByVehicle(vehicleId);
    if (routes.isEmpty) return;

    final routePoints = routes.first.points;

    // 순서 변경
    if (oldIndex < newIndex) {
      // 아래로 이동할 때
      final point = routePoints.removeAt(oldIndex);
      routePoints.insert(newIndex, point);
    } else {
      // 위로 이동할 때
      final point = routePoints.removeAt(oldIndex);
      routePoints.insert(newIndex, point);
    }

    // 시퀀스 번호 업데이트
    for (int i = 0; i < routePoints.length; i++) {
      routePoints[i].sequence = i + 1;
    }
  }

  /// 경로 요약 정보(총 거리, 예상 시간) 업데이트
  void updateRouteSummary({required int vehicleId, required double totalDistance, required int estimatedTime}) {
    try {
      // 해당 차량의 경로를 모든 그룹에서 찾기
      RouteInfo? targetRoute;
      String? targetGroupName;
      int? targetIndex;

      for (final groupName in _routeGroups.keys) {
        final routes = _routeGroups[groupName]!;
        final routeIndex = routes.indexWhere((route) => route.vehicleId == vehicleId);

        if (routeIndex != -1) {
          targetRoute = routes[routeIndex];
          targetGroupName = groupName;
          targetIndex = routeIndex;
          break;
        }
      }

      if (targetRoute != null && targetGroupName != null && targetIndex != null) {
        // 경로가 존재하면 업데이트
        _routeGroups[targetGroupName]![targetIndex] = RouteInfo(
          vehicleId: targetRoute.vehicleId,
          vehicleName: targetRoute.vehicleName,
          points: targetRoute.points,
          totalDistance: totalDistance,
          estimatedTime: estimatedTime,
          isActive: targetRoute.isActive,
          coordinates: targetRoute.coordinates,
        );

        print('경로 요약 정보 업데이트: 차량 $vehicleId, 거리: $totalDistance km, 소요시간: $estimatedTime 분');
      } else {
        print('경로 요약 정보 업데이트 실패: 차량 $vehicleId에 대한 경로가 없습니다.');
      }
    } catch (e) {
      print('경로 요약 정보 업데이트 오류: $e');
    }
  }
}
