import 'package:flutter_application_kimpoedu_shuttlebus_manager/services/synology_api.dart';
import 'package:get/get.dart';

// Synology 연결 정보를 전역으로 관리하는 컨트롤러
class SynologyController extends GetxController {
  SynologyApi? api;
  String naverClientId = '';

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
