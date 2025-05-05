// 셔틀 노선 정보를 담는 모델 클래스
class ShuttleRoute {
  final int busNumber;
  final String name;
  final List<RouteTime> times;

  ShuttleRoute({
    required this.busNumber,
    required this.name,
    required this.times,
  });

  factory ShuttleRoute.fromJson(Map<String, dynamic> json) {
    return ShuttleRoute(
      busNumber: json['busNumber'],
      name: json['name'],
      times: (json['times'] as List).map((timeJson) => RouteTime.fromJson(timeJson)).toList(),
    );
  }
}

// 노선의 시간별(오전/오후) 정보
class RouteTime {
  final bool isMorning;
  final List<dynamic> routeData; // 경로 좌표 등 (나중에 필요한 형태로 구체화)

  RouteTime({
    required this.isMorning,
    required this.routeData,
  });

  factory RouteTime.fromJson(Map<String, dynamic> json) {
    return RouteTime(
      isMorning: json['isMorning'],
      routeData: json['routeData'],
    );
  }
}
