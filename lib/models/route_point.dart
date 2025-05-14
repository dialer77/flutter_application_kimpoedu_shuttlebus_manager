import '../constants/enum_types.dart'; // Enum 타입 import

// 경로 포인트 클래스
class RoutePoint {
  final String id; // 고유 식별자
  final String name; // 장소명
  final double latitude;
  final double longitude;
  final String address; // 주소 (null 허용하지 않음)
  final PointType type; // 포인트 유형 (Enum 타입으로 변경)
  final int sequence; // 경로 내 순서

  RoutePoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.type,
    required this.sequence,
  });

  // JSON 변환 메서드
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'lat': latitude,
      'lng': longitude,
      'address': address,
      'type': type.toValue(), // Enum을 String으로 변환
      'sequence': sequence,
    };
  }

  // JSON으로부터 객체 생성
  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    return RoutePoint(
      id: json['id'],
      name: json['name'],
      latitude: json['lat'],
      longitude: json['lng'],
      address: json['address'] ?? '',
      type: PointTypeExtension.fromValue(json['type']), // String을 Enum으로 변환
      sequence: json['sequence'] ?? 0,
    );
  }

  // 복사본 생성 (특정 속성 변경 가능)
  RoutePoint copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    String? address,
    PointType? type,
    int? sequence,
  }) {
    return RoutePoint(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      type: type ?? this.type,
      sequence: sequence ?? this.sequence,
    );
  }
}
