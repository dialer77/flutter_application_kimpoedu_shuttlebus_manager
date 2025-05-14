import 'route_point.dart';

// 경로 정보를 저장하는 클래스
class RouteInfo {
  final int routeId;
  int vehicleId;
  bool isAM;
  final List<RoutePoint> points;
  double totalDistance;
  int estimatedTime;
  bool isActive; // 경로 활성화 상태
  final DateTime createdAt;
  List<List<List<double>>> coordinates = []; // 경로 선 좌표 추가

  RouteInfo({
    required this.routeId,
    required this.vehicleId,
    required this.isAM,
    required this.points,
    required this.totalDistance,
    required this.estimatedTime,
    DateTime? createdAt,
    this.isActive = true, // 기본값은 활성화 상태
    List<List<List<double>>>? coordinates,
  })  : createdAt = createdAt ?? DateTime.now(),
        coordinates = coordinates ?? [];

  // 경로의 시작점
  RoutePoint get startPoint => points.first;

  // 경로의 종점
  RoutePoint get endPoint => points.last;

  // 중간 경유지 포인트들
  List<RoutePoint> get waypoints => points.sublist(1, points.length - 1);

  // 관련 정보를 문자열로 변환
  @override
  String toString() {
    return '경로 ID: $routeId, 차량: $vehicleId호차, 시간대: ${isAM ? '오전' : '오후'}, '
        '거리: ${totalDistance.toStringAsFixed(1)}km, 예상 시간: $estimatedTime분';
  }

  // 시퀀스 순으로 정렬된 포인트 반환
  List<RoutePoint> get sortedPoints {
    final sorted = List<RoutePoint>.from(points);
    sorted.sort((a, b) => a.sequence.compareTo(b.sequence));
    return sorted;
  }

  // 새 포인트 추가 시 시퀀스 자동 할당
  void addPoint(RoutePoint point) {
    // 시퀀스가 0이면 자동 할당
    if (point.sequence == 0) {
      // 기존 최대 시퀀스 찾기
      int maxSequence = 0;
      if (points.isNotEmpty) {
        maxSequence = points.map((p) => p.sequence).reduce((max, seq) => max > seq ? max : seq);
      }

      // 새 시퀀스 번호로 포인트 추가
      points.add(point.copyWith(sequence: maxSequence + 1));
    } else {
      // 지정된 시퀀스로 추가
      points.add(point);
    }
  }

  // JSON 변환
  Map<String, dynamic> toJson() {
    return {
      'routeId': routeId,
      'vehicleId': vehicleId,
      'isAM': isAM,
      'points': points.map((p) => p.toJson()).toList(),
      'totalDistance': totalDistance,
      'estimatedTime': estimatedTime,
      'isActive': isActive,
      'coordinates': coordinates, // 좌표 정보 추가
    };
  }

  // JSON에서 생성
  factory RouteInfo.fromJson(Map<String, dynamic> json) {
    List<List<List<double>>> coords = [];
    if (json.containsKey('coordinates')) {
      final coordsData = json['coordinates'] as List;
      for (var coord in coordsData) {
        if (coord is List) {
          coords.add(coord.map<List<double>>((e) => e is List ? e.map<double>((f) => f is num ? f.toDouble() : 0.0).toList() : []).toList());
        }
      }
    }

    return RouteInfo(
      routeId: json['routeId'],
      vehicleId: json['vehicleId'],
      isAM: json['isAM'],
      points: (json['points'] as List).map((p) => RoutePoint.fromJson(p)).toList(),
      totalDistance: json['totalDistance'],
      estimatedTime: json['estimatedTime'],
      isActive: json['isActive'] ?? true,
      coordinates: coords,
    );
  }
}
