import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_kimpoedu_shuttlebus_manager/controllers/synology_controller.dart';
import 'package:flutter_application_kimpoedu_shuttlebus_manager/pages/main_page.dart';
import 'package:flutter_application_kimpoedu_shuttlebus_manager/services/route_manager.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:get/get.dart';
import 'services/local_web_server.dart';

// 인증 정보를 로컬 파일에서 읽어오는 함수
Future<Map<String, dynamic>> loadAuthConfig() async {
  try {
    // 앱 문서 디렉토리에서 인증 설정 파일 경로 생성
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/auth_config.json');

    // 파일이 존재하는지 확인
    if (await file.exists()) {
      final contents = await file.readAsString();
      return json.decode(contents);
    }

    // 파일이 없을 경우 assets에서 기본 설정 로드
    try {
      final configString = await rootBundle.loadString('assets/config/auth_config.json');
      // 기본 설정을 로컬에 저장 (처음 실행 시)
      await file.writeAsString(configString);
      return json.decode(configString);
    } catch (e) {
      print('Assets에서 인증 설정 로드 실패: $e');
      // 기본값 반환
      return {
        'synology': {'quickConnectId': 'gimpoedu', 'username': 'gimpo1234', 'password': '12341234'}
      };
    }
  } catch (e) {
    print('인증 설정 로드 오류: $e');
    // 오류 시 기본값 반환
    return {
      'synology': {'quickConnectId': 'gimpoedu', 'username': 'gimpo1234', 'password': '12341234'}
    };
  }
}

// 인증 정보 저장 함수 (나중에 설정 화면 등에서 사용 가능)
Future<void> saveAuthConfig(Map<String, dynamic> config) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/auth_config.json');
    await file.writeAsString(json.encode(config));
    print('인증 설정이 저장되었습니다.');
  } catch (e) {
    print('인증 설정 저장 오류: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // GetX 초기화
  await initializeGetX();

  // 기본 클라이언트 ID (fallback용)
  String naverClientId = '';

  // 인증 정보 로드
  final authConfig = await loadAuthConfig();
  final synologyConfig = authConfig['synology'] as Map<String, dynamic>;

  final quickConnectId = synologyConfig['quickConnectId'];
  final username = synologyConfig['username'];
  final password = synologyConfig['password'];

  // SynologyController 등록 및 초기화
  final synologyController = Get.put(SynologyController(), permanent: true);
  await synologyController.initializeConnection(quickConnectId, username, password);

  // 경로 매니저 초기화
  final routeManager = Get.put(RouteManager(), permanent: true);

  // NAS에서 설정 파일 로드 시도
  try {
    if (synologyController.isConnected.value) {
      // 1. 네이버 API 설정 로드
      const configPath = '/Navigation/config.json';
      final jsonString = await synologyController.loadConfigFile(configPath);
      final config = json.decode(jsonString);

      if (config['naverMap'] != null && config['naverMap']['clientId'] != null) {
        naverClientId = config['naverMap']['clientId'];
        synologyController.naverClientId = naverClientId;
        print('NAS에서 네이버 클라이언트 ID 로드 성공: $naverClientId');
      }

      // 2. 경로 데이터 로드
      await synologyController.loadRouteData(routeManager);
    }
  } catch (e) {
    print('설정 또는 경로 데이터 로드 오류: $e');
  }

  // 웹 서버 시작
  final webServer = LocalWebServer();
  final serverUrl = await webServer.startServer();
  print('서버 URL: $serverUrl');

  runApp(const MainApp());
}

// GetX 초기화 함수
Future<void> initializeGetX() async {
  Get.lazyPut(() => SynologyController(), fenix: true);
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const GetMaterialApp(
      title: '셔틀버스 앱',
      home: MainPage(),
    );
  }
}
