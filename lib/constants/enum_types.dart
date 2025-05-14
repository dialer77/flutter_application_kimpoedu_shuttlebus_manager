// 애플리케이션 내에서 사용되는 Enum 타입 모음

// 경로 포인트 유형 열거형
enum PointType {
  start, // 시작점
  waypoint, // 경유지
  end // 도착점
}

// PointType Enum을 문자열로 변환하는 확장 메서드
extension PointTypeExtension on PointType {
  String toValue() {
    return toString().split('.').last;
  }

  // 문자열에서 PointType으로 변환하는 정적 메서드
  static PointType fromValue(String value) {
    return PointType.values.firstWhere(
      (type) => type.toValue() == value,
      orElse: () => PointType.waypoint, // 기본값 설정
    );
  }
}
