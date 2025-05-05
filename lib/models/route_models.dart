// 경로 웨이포인트 모델
class RouteWaypoint {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String type; // 'start', 'waypoint', 'end' 등

  RouteWaypoint({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.type,
  });
}

// 차량 경로 정보 모델
class VehicleRouteInfo {
  final int id;
  bool isAM;
  List<RouteWaypoint> waypoints = [];

  VehicleRouteInfo({
    required this.id,
    required this.isAM,
  });

  void addWaypoint(RouteWaypoint waypoint) {
    waypoints.add(waypoint);
  }

  void clearWaypoints() {
    waypoints.clear();
  }
}
