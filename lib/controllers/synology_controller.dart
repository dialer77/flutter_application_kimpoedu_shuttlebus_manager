import 'dart:convert';
import 'dart:io';
import 'package:flutter_application_kimpoedu_shuttlebus_manager/services/synology_api.dart';
import 'package:flutter_application_kimpoedu_shuttlebus_manager/services/route_manager.dart';
import 'package:get/get.dart';

// Synology 연결 정보를 전역으로 관리하는 컨트롤러
class SynologyController extends GetxController {
  SynologyApi? api;
  String naverClientId = '';

  // 경로 파일 저장 경로를 config.json과 동일한 폴더로 변경
  final String defaultRoutePath = '/Navigation';

  // 고정된 파일명 (항상 같은 파일에 저장)
  final String fixedRouteFileName = 'current_routes.json';

  // 전체 경로 (고정 파일)
  String get fixedRoutePath => '$defaultRoutePath/$fixedRouteFileName';

  // 임시 로컬 파일 경로
  final String localRoutePath = 'current_routes.json';

  // 연결 상태
  final RxBool isConnected = false.obs;

  // 사용자 인증 정보
  final RxString quickConnectId = ''.obs;
  final RxString username = ''.obs;
  final RxString password = ''.obs;

  // SynologyAPI 초기화 및 연결
  Future<void> initializeConnection(String quickId, String user, String pass) async {
    quickConnectId.value = quickId;
    username.value = user;
    password.value = pass;

    try {
      final tempApi = SynologyApi(quickId);
      await tempApi.login(user, pass);
      api = tempApi;
      isConnected.value = true;
      update();
    } catch (e) {
      print('시놀로지 NAS 연결 실패: $e');
      isConnected.value = false;
      update();
    }
  }

  // 설정 파일 로드
  Future<String> loadConfigFile(String path) async {
    if (api == null || !isConnected.value) {
      throw Exception('시놀로지 API가 연결되지 않았습니다.');
    }

    if (await api!.fileExists(path)) {
      return await api!.getFile(path);
    } else {
      throw Exception('파일을 찾을 수 없습니다: $path');
    }
  }

  // 경로 데이터 저장 (고정 파일명 사용)
  Future<bool> saveRouteData(RouteManager routeManager) async {
    if (api == null || !isConnected.value) {
      throw Exception('시놀로지 API가 연결되지 않았습니다.');
    }

    try {
      // 경로 매니저에서 경로 정보 가져오기
      final routeData = routeManager.exportToJson();
      await File(localRoutePath).writeAsString(jsonEncode(routeData));

      return true;
      // JSON 문자열로 변환
      // final jsonString = jsonEncode(routeData);

      // // 디렉토리 확인 및 생성
      // final directory = defaultRoutePath;
      // if (!await api!.fileExists(directory)) {
      //   await api!.createDirectory(directory);
      // }

      // // 항상 같은 파일에 저장
      // if (await api!.saveFile(fixedRoutePath, jsonString)) {
      //   print('경로 데이터 저장 성공: $fixedRoutePath');
      //   return true;
      // } else {
      //   print('경로 데이터 저장 실패: $fixedRoutePath');
      //   return false;
      // }

      // print('경로 데이터 저장 성공: $fixedRoutePath');
      // return true;
    } catch (e) {
      print('경로 데이터 저장 실패: $e');
      return false;
    }
  }

  // 경로 데이터 로드 (고정 파일명 사용)
  Future<bool> loadRouteData(RouteManager routeManager) async {
    if (api == null || !isConnected.value) {
      throw Exception('시놀로지 API가 연결되지 않았습니다.');
    }

    try {
      // 임시로 로컬에서 읽어오는걸로 동작
      // 추후 시놀로지에서 읽어오는 기능 추가 필요

      final localFile = File(localRoutePath);
      final jsonString = await localFile.readAsString();

      // JSON 파싱
      final Map<String, dynamic> routeData = jsonDecode(jsonString);
      routeManager.importFromJson(routeData);

      return true;

      // 파일 존재 여부 확인
      // if (!await api!.fileExists(fixedRoutePath)) {
      //   print('고정 경로 파일이 존재하지 않습니다: $fixedRoutePath');
      //   return false;
      // }

      // // 파일 내용 가져오기
      // final jsonString = await api!.getFile(fixedRoutePath);

      // // JSON 파싱
      // final Map<String, dynamic> routeData = jsonDecode(jsonString);

      // // 경로 매니저로 데이터 임포트
      // routeManager.importFromJson(routeData);

      // print('경로 데이터 로드 성공: $fixedRoutePath');
      // return true;
    } catch (e) {
      print('경로 데이터 로드 실패: $e');
      return false;
    }
  }

  // 로그아웃
  Future<void> logout() async {
    if (api != null && isConnected.value) {
      await api!.logout();
      isConnected.value = false;
      update();
    }
  }

  @override
  void onClose() {
    logout();
    super.onClose();
  }
}
