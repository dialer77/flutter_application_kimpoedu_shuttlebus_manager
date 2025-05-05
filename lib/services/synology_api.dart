import 'dart:convert';
import 'package:http/http.dart' as http;

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
        print('QuickConnect URL 해석 오류, 기본값 사용: $fallbackError');
      }
    }

    print('사용할 NAS URL: $baseUrl');
  }

  Future<void> login(String username, String password) async {
    if (baseUrl == null) {
      await resolveQuickConnectUrl();
    }

    final response = await http.get(
      Uri.parse('$baseUrl/webapi/auth.cgi?api=SYNO.API.Auth&version=3&method=login&account=$username&passwd=$password&format=json'),
    );

    final data = json.decode(response.body);
    if (data['success']) {
      sid = data['data']['sid'];
    } else {
      throw Exception('로그인 실패: ${data['error']['code']}');
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
}
