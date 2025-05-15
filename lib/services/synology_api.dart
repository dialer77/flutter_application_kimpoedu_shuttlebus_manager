// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class SynologyApi {
  final String quickConnectId;
  String? baseUrl;
  String? sid;

  SynologyApi(this.quickConnectId);

  // QuickConnect ID를 통해 실제 NAS URL 가져오기
  Future<void> resolveQuickConnectUrl() async {
    try {
      // 주어진 URL 형식을 기반으로 직접 URL 구성
      // 예: https://gimpoedu.direct.quickconnect.to:5001/
      baseUrl = 'https://$quickConnectId.direct.quickconnect.to:5001';

      // URL이 유효한지 테스트
      final testResponse = await http.get(
        Uri.parse('$baseUrl/webapi/query.cgi?api=SYNO.API.Info&version=1&method=query'),
      );

      if (testResponse.statusCode != 200) {
        throw Exception('직접 접속 URL이 유효하지 않습니다.');
      }
    } catch (e) {
      // 직접 연결 실패 시 대체 전략으로 전환
      try {
        final response = await http.post(
          Uri.parse('https://global.quickconnect.to/Serv.php'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'version': 1,
            'method': 'get',
            'id': quickConnectId,
            'serverID': quickConnectId,
          }),
        );

        final data = json.decode(response.body);
        if (data['success']) {
          // 응답에서 서버 URL 추출
          final servers = data['servers'] as List;
          for (final server in servers) {
            // 외부 접속 가능한 URL 선택
            if (server['external'] == true && server['https'] == true) {
              baseUrl = 'https://${server['host']}:${server['port']}';
              break;
            }
          }

          if (baseUrl == null) {
            throw Exception('접속 가능한 서버를 찾을 수 없습니다');
          }
        } else {
          throw Exception('QuickConnect 서버 해석 실패');
        }
      } catch (fallbackError) {
        // 모든 방법이 실패하면 기본 QuickConnect URL 사용
        baseUrl = 'https://quickconnect.to/$quickConnectId';
      }
    }

    print('사용할 NAS URL: $baseUrl');
  }

  // 로그인 메서드 - FileStation 서비스 권한 추가
  Future<void> login(String username, String password) async {
    if (baseUrl == null) {
      await resolveQuickConnectUrl();
    }

    try {
      // 로그인 API 버전 확인
      final infoResponse = await http.get(
        Uri.parse('$baseUrl/webapi/query.cgi?api=SYNO.API.Info&version=1&method=query&query=SYNO.API.Auth,SYNO.FileStation.'),
      );

      final infoData = json.decode(infoResponse.body);
      if (!infoData['success']) {
        throw Exception('API 정보를 가져오는데 실패했습니다.');
      }

      // 로그인 요청 (FileStation 서비스 명시)
      final response = await http.post(Uri.parse('$baseUrl/webapi/auth.cgi'), body: {
        'api': 'SYNO.API.Auth',
        'version': '6', // API 버전
        'method': 'login',
        'account': username,
        'passwd': password,
        // FileStation 서비스에 대한 권한 요청
        'session': 'FileStation',
        // 다른 필요한 서비스들도 추가
        'service': 'FileStation, DSFile',
      });

      final data = json.decode(response.body);

      if (data['success']) {
        sid = data['data']['sid'];
        print('로그인 성공: $username, SID: $sid');

        await createDirectory('test');
      } else {
        if (data.containsKey('error')) {
          final errorCode = data['error']['code'];
          final errorMessage = _getErrorMessage(errorCode);
          throw Exception('로그인 실패 (코드: $errorCode): $errorMessage');
        } else {
          throw Exception('로그인 실패: 알 수 없는 오류');
        }
      }
    } catch (e) {
      print('로그인 오류: $e');
      rethrow;
    }
  }

  // 세션 권한 확인 메서드 (디버깅용)
  Future<void> _checkSessionPermissions() async {
    try {
      // FileStation 서비스 접근 가능 여부 테스트
      final response = await http.get(
        Uri.parse('$baseUrl/webapi/entry.cgi?api=SYNO.FileStation.Info&version=1&method=get&_sid=$sid'),
      );

      final data = json.decode(response.body);
      if (data['success']) {
        print('FileStation 접근 권한 확인됨');
        print('FileStation 정보: ${data['data']}');
      } else {
        print('FileStation 접근 권한 없음: ${data['error']}');
      }
    } catch (e) {
      print('세션 권한 확인 오류: $e');
    }
  }

  Future<String> getFile(String path) async {
    if (baseUrl == null) await resolveQuickConnectUrl();
    if (sid == null) throw Exception('로그인 필요');

    final response = await http.get(
      Uri.parse('$baseUrl/webapi/entry.cgi?api=SYNO.FileStation.Download&version=2&method=download&path=$path&_sid=$sid'),
    );

    if (response.statusCode == 200) {
      return utf8.decode(response.bodyBytes);
    } else {
      throw Exception('파일 다운로드 실패: ${response.statusCode}');
    }
  }

  Future<bool> fileExists(String path) async {
    if (baseUrl == null) await resolveQuickConnectUrl();
    if (sid == null) throw Exception('로그인 필요');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=getinfo&path=$path&_sid=$sid'),
      );

      final data = json.decode(response.body);
      return data['success'] && data['data']['files'] != null;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    if (baseUrl == null || sid == null) return;

    try {
      await http.get(
        Uri.parse('$baseUrl/webapi/auth.cgi?api=SYNO.API.Auth&version=1&method=logout&_sid=$sid'),
      );
    } finally {
      sid = null;
    }
  }

  // 1. 공유 폴더 목록 가져오기 (최상위 레벨 폴더)
  Future<List<String>> listSharedFolders() async {
    if (baseUrl == null) await resolveQuickConnectUrl();
    if (sid == null) throw Exception('로그인 필요');

    final response = await http.get(
      Uri.parse('$baseUrl/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=list_share&_sid=$sid'),
    );

    final data = json.decode(response.body);
    if (data['success']) {
      final shares = data['data']['shares'] as List;
      return shares.map<String>((share) => share['name'] as String).toList();
    } else {
      throw Exception('공유 폴더 목록 가져오기 실패');
    }
  }

  // 2. 특정 폴더 내 파일 목록 가져오기
  Future<List<Map<String, dynamic>>> listFiles(String folderPath) async {
    if (baseUrl == null) await resolveQuickConnectUrl();
    if (sid == null) throw Exception('로그인 필요');

    final encodedPath = Uri.encodeComponent(folderPath);
    final response = await http.get(
      Uri.parse('$baseUrl/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=list&folder_path=$encodedPath&_sid=$sid'),
    );

    final data = json.decode(response.body);
    if (data['success']) {
      return List<Map<String, dynamic>>.from(data['data']['files']);
    } else {
      throw Exception('파일 목록 가져오기 실패: ${data['error']['code']}');
    }
  }

  // 3. 볼륨 목록 가져오기 (시스템 볼륨 정보)
  Future<List<String>> listVolumes() async {
    if (baseUrl == null) await resolveQuickConnectUrl();
    if (sid == null) throw Exception('로그인 필요');

    try {
      // 일부 시놀로지 모델에서는 volume 정보에 직접 접근 가능
      final response = await http.get(
        Uri.parse('$baseUrl/webapi/entry.cgi?api=SYNO.Storage.Volume&version=1&method=list&_sid=$sid'),
      );

      final data = json.decode(response.body);
      if (data['success']) {
        final volumes = data['data']['volumes'] as List;
        return volumes.map<String>((volume) => volume['path'] as String).toList();
      } else {
        throw Exception('볼륨 정보 가져오기 실패');
      }
    } catch (e) {
      // 대안으로 직접 루트 경로 목록 반환
      return ['/volume1', '/volume2', '/volumeUSB1'];
    }
  }

  // 4. 루트 디렉토리 탐색 (통합 메소드)
  Future<Map<String, dynamic>> exploreRoot() async {
    if (baseUrl == null) await resolveQuickConnectUrl();
    if (sid == null) throw Exception('로그인 필요');

    final result = <String, dynamic>{};

    // 1. 공유 폴더 목록
    try {
      result['sharedFolders'] = await listSharedFolders();
    } catch (e) {
      result['sharedFolders'] = <String>[];
      result['sharedFoldersError'] = e.toString();
    }

    // 2. 볼륨 정보
    try {
      result['volumes'] = await listVolumes();
    } catch (e) {
      result['volumes'] = <String>[];
      result['volumesError'] = e.toString();
    }

    // 3. 루트 디렉토리 내용 (가능한 경우)
    try {
      result['rootFiles'] = await listFiles('/');
    } catch (e) {
      result['rootFiles'] = <Map<String, dynamic>>[];
      result['rootFilesError'] = e.toString();
    }

    return result;
  }

  // 디렉토리 생성 메서드 (문서에 맞게 수정)
  Future<bool> createDirectory(String path) async {
    if (baseUrl == null) await resolveQuickConnectUrl();
    if (sid == null) throw Exception('로그인 필요');

    try {
      // 경로를 부모 디렉토리와 새 폴더 이름으로 분리
      final lastSlashIndex = path.lastIndexOf('/');
      if (lastSlashIndex == -1) {
        throw Exception('잘못된 경로 형식: $path');
      }

      // 부모 디렉토리 경로 추출
      final parentPath = lastSlashIndex > 0 ? path.substring(0, lastSlashIndex) : '/';

      // 새 폴더 이름 추출
      final folderName = path.substring(lastSlashIndex + 1);

      print('디렉토리 생성: 상위 경로=$parentPath, 폴더 이름=$folderName');

      // API에 맞게 파라미터 설정 (name 파라미터는 대괄호로 감싸야 함)
      final encodedParentPath = Uri.encodeComponent(parentPath);
      final encodedFolderName = Uri.encodeComponent('[$folderName]');

      // 세션 ID를 따옴표로 감싸기
      final quotedSid = '"${sid!}"';

      // URL 구성
      final url = '$baseUrl/webapi/entry.cgi?api=SYNO.FileStation.CreateFolder&version=2&method=create&folder_path=$encodedParentPath&name=$encodedFolderName&_sid=$quotedSid';
      print('요청 URL: $url');

      final response = await http.get(Uri.parse(url));
      print('응답 상태 코드: ${response.statusCode}');
      print('응답 내용: ${response.body}');

      final data = json.decode(response.body);
      if (data['success'] == true) {
        print('디렉토리 생성 성공: $path');
        return true;
      } else {
        if (data.containsKey('error') && data['error'].containsKey('code')) {
          final errorCode = data['error']['code'];
          print('디렉토리 생성 실패 (에러 코드: $errorCode): ${_getErrorMessage(errorCode)}');
        } else {
          print('디렉토리 생성 실패: $data');
        }
        return false;
      }
    } catch (e) {
      print('디렉토리 생성 오류: $e');
      return false;
    }
  }

  // 6. 파일 저장 메서드 (Synology 공식 문서 예제와 일치하도록 구현)
  Future<bool> saveFile(String path, String content) async {
    if (baseUrl == null) await resolveQuickConnectUrl();
    if (sid == null) throw Exception('로그인 필요');

    // 로컬 임시 파일 변수
    File? tempFile;

    try {
      // 1. 로컬 임시 디렉토리에 파일 생성
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFileName = 'temp_file_$timestamp.json';

      tempFile = File('${tempDir.path}/$tempFileName');

      // 임시 파일에 내용 쓰기
      await tempFile.writeAsString(content);

      // 2. 대상 디렉토리 확인 및 생성
      final targetDir = path.substring(0, path.lastIndexOf('/'));
      if (!await fileExists(targetDir)) {
        print('대상 디렉토리 생성 시도: $targetDir');
        final created = await createDirectory(targetDir);
        if (!created) {
          print('대상 디렉토리 생성 실패: $targetDir');
          return false;
        }
        print('대상 디렉토리 생성 성공');
      }

      // 3. 파일 업로드 - 공식 문서 예제와 정확히 일치
      print('파일 업로드 시도: 로컬(${tempFile.path}) -> NAS($path)');

      // 기본 URI 구성
      final uploadUri = Uri.parse('$baseUrl/webapi/entry.cgi');

      final fileName = path.split('/').last;

      // MultipartRequest 생성
      final request = http.MultipartRequest('POST', uploadUri);

      // 필드 추가 (공식 문서 예제와 동일한 순서)
      request.fields['api'] = 'SYNO.FileStation.Upload';
      request.fields['version'] = '2';
      request.fields['method'] = 'upload';
      request.fields['path'] = targetDir;
      request.fields['create_parents'] = 'true';

      // 옵션: 기존 파일 덮어쓰기
      request.fields['overwrite'] = 'true';
      // 인증 세션 ID 추가 (공식 예제에는 없지만 실제로는 필요)
      request.fields['_sid'] = sid!;

      print('필드 구성 완료: ${request.fields}');

      // 파일 파트 추가 (마지막에 위치해야 함)
      final multipartFile = await http.MultipartFile.fromPath('file', tempFile.path, filename: fileName);

      request.files.add(multipartFile);
      print('파일 추가됨: ${multipartFile.filename}, ${multipartFile.length} 바이트');

      // 요청 전송
      print('요청 전송 중...');
      final streamedResponse = await request.send();
      print('응답 상태 코드: ${streamedResponse.statusCode}');

      // 응답 본문 수신 및 디버깅
      final bytes = await streamedResponse.stream.toBytes();
      final responseBody = utf8.decode(bytes);
      print('응답 본문: $responseBody');

      // 업로드 결과 확인
      if (streamedResponse.statusCode != 200) {
        print('파일 업로드 실패 (HTTP 상태: ${streamedResponse.statusCode})');
        print('응답 내용: $responseBody');
        return false;
      }

      // JSON 응답 파싱
      try {
        final data = json.decode(responseBody);
        if (data['success'] == true) {
          print('파일 업로드 성공: $path');
          return true;
        } else {
          if (data.containsKey('error') && data['error'].containsKey('code')) {
            final errorCode = data['error']['code'];
            print('파일 업로드 실패 (에러 코드: $errorCode): ${_getErrorMessage(errorCode)}');
            print('전체 오류 응답: $data');
          } else {
            print('파일 업로드 실패: $data');
          }
          return false;
        }
      } catch (e) {
        print('응답 파싱 오류: $e');
        print('원본 응답: $responseBody');
        return false;
      }
    } catch (e) {
      print('파일 저장 예외 발생: $e');
      return false;
    } finally {
      // 임시 파일 정리 (성공 여부와 관계없이 실행)
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
          print('로컬 임시 파일 삭제됨: ${tempFile.path}');
        } catch (e) {
          print('임시 파일 삭제 중 오류: $e');
        }
      }
    }
  }

  // 파일 이동 메서드
  Future<bool> moveFile(String sourcePath, String destPath, {bool overwrite = false}) async {
    if (baseUrl == null) await resolveQuickConnectUrl();
    if (sid == null) throw Exception('로그인 필요');

    try {
      final encodedSourcePath = Uri.encodeComponent(sourcePath);
      final encodedDestPath = Uri.encodeComponent(destPath);
      final response = await http.get(
        Uri.parse(
            '$baseUrl/webapi/entry.cgi?api=SYNO.FileStation.CopyMove&version=3&method=start&path=$encodedSourcePath&dest_folder_path=${Uri.encodeComponent(destPath.substring(0, destPath.lastIndexOf("/")))}&overwrite=${overwrite ? "true" : "false"}&remove_src=true&_sid=$sid'),
      );

      final data = json.decode(response.body);
      if (data['success'] == true) {
        final taskId = data['data']['taskid'];
        print('파일 이동 작업 시작됨, 태스크 ID: $taskId');

        // 이동 작업 완료 대기
        return await waitForTaskCompletion(taskId);
      } else {
        final errorCode = data['error']['code'];
        print('파일 이동 시작 실패 (에러 코드: $errorCode): ${_getErrorMessage(errorCode)}');
        return false;
      }
    } catch (e) {
      print('파일 이동 오류: $e');
      return false;
    }
  }

  // 작업 완료 대기 메서드
  Future<bool> waitForTaskCompletion(String taskId) async {
    const maxAttempts = 30; // 최대 30번 시도 (약 30초)
    int attempts = 0;

    while (attempts < maxAttempts) {
      attempts++;
      await Future.delayed(const Duration(milliseconds: 1000)); // 1초 대기

      try {
        final response = await http.get(
          Uri.parse('$baseUrl/webapi/entry.cgi?api=SYNO.FileStation.CopyMove&version=3&method=status&taskid=$taskId&_sid=$sid'),
        );

        final data = json.decode(response.body);
        if (data['success'] != true) {
          print('작업 상태 확인 실패');
          continue;
        }

        final status = data['data']['status'];
        final progress = data['data']['progress'];

        print('작업 진행 상태: $status, 진행률: $progress');

        if (status == 'finished') {
          return true; // 작업 완료
        } else if (status == 'error') {
          print('작업 오류 발생');
          return false;
        }
      } catch (e) {
        print('작업 상태 확인 중 오류: $e');
      }
    }

    print('작업 시간 초과');
    return false;
  }

  // Synology 에러 코드 메시지 반환
  String _getErrorMessage(int code) {
    switch (code) {
      case 119:
        return '파일 작업 실패: 해당 경로에 대한 권한이 없거나 경로가 올바르지 않습니다';
      case 120:
        return '대상 파일이 이미 존재합니다';
      case 401:
        return '파라미터 부족';
      case 402:
        return '잘못된 사용자 계정';
      case 403:
        return '접근 권한 없음';
      case 404:
        return '파일이나 폴더가 존재하지 않음';
      case 408:
        return '요청 시간 초과';
      case 414:
        return '경로가 너무 깁니다';
      case 500:
        return '구문 오류';
      case 1000:
        return '알 수 없는 오류';
      case 1001:
        return '파라미터 오류';
      case 1002:
        return 'API 버전이 지원되지 않음';
      case 1003:
        return '메소드가 지원되지 않음';
      case 1004:
        return '시간 초과';
      case 1100:
        return '알 수 없는 오류';
      case 1101:
        return '파일/폴더 이름 유효하지 않음';
      default:
        return '알 수 없는 오류 (코드: $code)';
    }
  }

  // 7. 폴더 내 파일 목록 가져오기 (문자열 리스트로 반환)
  Future<List<String>> listFileNames(String folderPath) async {
    final files = await listFiles(folderPath);
    return files
        .where((file) => file['isdir'] == false) // 파일만 필터링
        .map<String>((file) => file['name'] as String)
        .toList();
  }
}
