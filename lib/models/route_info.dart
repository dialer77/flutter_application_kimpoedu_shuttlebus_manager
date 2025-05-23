import 'route_point.dart';

// 경로 정보를 저장하는 클래스
class RouteInfo {
  int vehicleId;
  String vehicleName;

  final List<RoutePoint> points;
  double totalDistance;
  int estimatedTime;
  bool isActive; // 경로 활성화 상태
  final DateTime createdAt;
  List<List<double>> coordinates = []; // 경로 선 좌표 추가

  RouteInfo({
    required this.vehicleId,
    required this.vehicleName,
    required this.points,
    required this.totalDistance,
    required this.estimatedTime,
    DateTime? createdAt,
    this.isActive = true, // 기본값은 활성화 상태
    List<List<double>>? coordinates,
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
    return '차량: ${vehicleId + 1}호차, 차량명 : $vehicleName, '
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
      'vehicleId': vehicleId,
      'vehicleName': vehicleName,
      'points': points.map((p) => p.toJson()).toList(),
      'totalDistance': totalDistance,
      'estimatedTime': estimatedTime,
      'isActive': isActive,
      'coordinates': coordinates, // 좌표 정보 추가
    };
  }

  // JSON에서 생성
  factory RouteInfo.fromJson(Map<String, dynamic> json) {
    List<List<double>> coords = [];
    if (json.containsKey('coordinates')) {
      final coordsData = json['coordinates'] as List;
      for (var coord in coordsData) {
        if (coord is List) {
          coords.add(coord.map<double>((e) => e is num ? e.toDouble() : 0.0).toList());
        }
      }
    }

    return RouteInfo(
      vehicleId: json['vehicleId'],
      vehicleName: json['vehicleName'],
      points: (json['points'] as List).map((p) => RoutePoint.fromJson(p)).toList(),
      totalDistance: json['totalDistance'],
      estimatedTime: json['estimatedTime'],
      isActive: json['isActive'] ?? true,
      coordinates: coords,
    );
  }
}
