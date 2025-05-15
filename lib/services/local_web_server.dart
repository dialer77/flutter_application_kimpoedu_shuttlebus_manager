// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class LocalWebServer {
  static final LocalWebServer _instance = LocalWebServer._internal();
  factory LocalWebServer() => _instance;
  LocalWebServer._internal();

  HttpServer? _server;
  // 고정 포트 설정 (9876 - 일반적으로 사용되지 않는 포트)
  static const int fixedPort = 9876;
  int? _port;
  String? _htmlDirectory;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  int? get port => _port;
  String? get serverUrl => _port != null ? 'http://localhost:$_port' : null;

  // 로컬 웹 서버 시작
  Future<String?> startServer(String appKey) async {
    if (_isRunning) {
      print('서버가 이미 실행 중입니다: http://localhost:$_port');
      return serverUrl;
    }

    try {
      // 임시 디렉토리에 HTML 파일 복사
      _htmlDirectory = await _prepareHtmlFiles(appKey);

      // 정적 파일 핸들러 생성
      final staticHandler = createStaticHandler(
        _htmlDirectory!,
        defaultDocument: 't_map.html',
      );

      // CORS 및 로깅 미들웨어 적용
      final handler = const shelf.Pipeline().addMiddleware(_corsHeaders).addMiddleware(_logRequests).addHandler(staticHandler);

      // 서버 시작 (고정 포트 사용)
      try {
        _server = await io.serve(
          handler,
          'localhost',
          fixedPort, // 고정 포트 사용
        );
        _port = fixedPort;
      } catch (e) {
        print('고정 포트($fixedPort)를 사용할 수 없습니다: $e');
        print('대체 포트로 다시 시도합니다...');

        // 고정 포트 사용 실패 시 자동 할당 사용
        _server = await io.serve(
          handler,
          'localhost',
          0, // 0은 사용 가능한 포트를 자동 할당
        );
        _port = _server!.port;
      }

      _isRunning = true;

      print('로컬 웹 서버 시작됨: http://localhost:$_port');
      return serverUrl;
    } catch (e) {
      print('로컬 웹 서버 시작 오류: $e');
      return null;
    }
  }

  // 서버 중지
  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _port = null;
      _isRunning = false;

      // 임시 HTML 파일 정리
      if (_htmlDirectory != null) {
        try {
          final htmlDir = Directory(_htmlDirectory!);
          if (await htmlDir.exists()) {
            await htmlDir.delete(recursive: true);
            print('임시 HTML 파일이 삭제되었습니다: $_htmlDirectory');
          }
        } catch (e) {
          print('임시 HTML 파일 삭제 중 오류 발생: $e');
        }
        _htmlDirectory = null;
      }

      print('로컬 웹 서버가 중지되었습니다.');
    }
  }

  // CORS 헤더 미들웨어
  shelf.Middleware get _corsHeaders {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        final response = await innerHandler(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, X-Auth-Token',
        });
      };
    };
  }

  // 로깅 미들웨어
  shelf.Middleware get _logRequests {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        print('${request.method} ${request.url}');
        final response = await innerHandler(request);
        print('${response.statusCode} ${request.url}');
        return response;
      };
    };
  }

  // HTML 파일을 임시 디렉토리에 복사하고 APP_KEY를 대체
  Future<String> _prepareHtmlFiles(String appKey) async {
    final tempDir = await getTemporaryDirectory();
    final htmlDir = Directory(path.join(tempDir.path, 'html_server'));

    // 디렉토리가 없으면 생성
    if (!await htmlDir.exists()) {
      await htmlDir.create(recursive: true);
    }

    try {
      // assets/html 디렉토리의 파일 목록
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = Map.from(json.decode(manifestContent));

      final htmlAssets = manifestMap.keys.where((String key) => key.startsWith('assets/html/')).toList();

      // 각 HTML 파일 복사
      for (final assetPath in htmlAssets) {
        final fileName = path.basename(assetPath);
        var content = await rootBundle.loadString(assetPath);

        // 모든 APP_KEY 문자열을 실제 API 키로 대체
        content = content.replaceAll('APP_KEY', appKey);
        print('$fileName 파일에서 모든 API 키 대체 완료');

        final file = File(path.join(htmlDir.path, fileName));
        await file.writeAsString(content);
        print('파일 복사됨: $fileName');
      }

      print('HTML 파일이 다음 위치에 준비되었습니다: ${htmlDir.path}');
      return htmlDir.path;
    } catch (e) {
      print('HTML 파일 준비 오류: $e');
      rethrow;
    }
  }
}
