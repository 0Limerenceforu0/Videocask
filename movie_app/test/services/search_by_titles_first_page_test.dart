import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/play_source.dart';
import 'package:movie_app/services/api_service.dart';

/// 人名检索（「周星驰」）与片名批量的回归测试（2026-10-28）。
///
/// 真机实测缺陷：搜「周星驰」转圈两分钟以上、永远出不来结果。
/// 根因是 [ApiService.searchByTitles] 复用了「按源搜索」的两段式流程：
/// 每个源的阶段 2 会把第 2..10 页全部补完才让流关闭，而人名检索是
/// 「6~8 部代表作 × N 个源」，请求量放大到几百个，`await for` 一直在等。
///
/// 本测试用假采集站（`pagecount=5`，专门引诱补页）验证：按片名批量检索
/// **只请求第 1 页**，绝不触发补页。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 单测环境默认把所有 HttpClient mock 成 400，这里要真打 loopback。
  HttpOverrides.global = null;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => switch (call.method) {
      'getTemporaryDirectory' => Directory.systemTemp.path,
      'getApplicationSupportDirectory' => Directory.systemTemp.path,
      _ => null,
    },
  );

  late HttpServer server;
  late ApiService api;
  late List<String> requestedUrls;

  setUp(() async {
    requestedUrls = [];
    api = ApiService();
    await api.init();

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requestedUrls.add('${req.uri.path}?${req.uri.query}');
      final wd = req.uri.queryParameters['wd'] ?? '';
      final pg = int.tryParse(req.uri.queryParameters['pg'] ?? '1') ?? 1;
      final body = jsonEncode({
        'code': 1,
        'msg': 'ok',
        'page': pg,
        'pagecount': 5,
        'total': 100,
        'list': [
          {
            'vod_id': 'x_$pg',
            'vod_name': wd,
            'type_name': '剧情',
          },
        ],
      });
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType.json;
      req.response.write(body);
      await req.response.close();
    });

    api.setCurrentSource(
      PlaySource(
        id: 'default',
        name: '默认源',
        url: 'http://127.0.0.1:${server.port}/provide.php',
      ),
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('按片名批量检索只取第 1 页，不触发补页（否则人名搜索会转圈数分钟）', () async {
    final source = PlaySource(
      id: 'fake',
      name: '假源',
      url: 'http://127.0.0.1:${server.port}/provide.php',
    );
    final kw = '功夫${DateTime.now().microsecondsSinceEpoch}';
    final hits = await api
        .searchByTitles(
          [TitleQuery(kw)],
          sources: [source],
        )
        .timeout(const Duration(seconds: 5));

    expect(hits.map((m) => m.name), contains(kw));
    // 只应有第 1 页请求；出现 pg=2..5 说明补页被触发了。
    final pages = requestedUrls
        .map((u) => Uri.parse('http://x$u').queryParameters['pg'] ?? '1')
        .toSet();
    expect(
      pages,
      {'1'},
      reason: '按片名批量检索必须只取第 1 页，实际请求页：$pages',
    );
  });

  test('正常关键词搜索仍然会补页（不影响既有能力）', () async {
    final source = PlaySource(
      id: 'fake',
      name: '假源',
      url: 'http://127.0.0.1:${server.port}/provide.php',
    );
    final kw = '全量${DateTime.now().microsecondsSinceEpoch}';
    await for (final _ in api.searchFromAllSources(kw, sources: [source])) {
      // 消费到底
    }
    final pages = requestedUrls
        .map((u) => Uri.parse('http://x$u').queryParameters['pg'] ?? '1')
        .toSet();
    expect(pages.contains('2'), isTrue, reason: '首页搜索应继续后台补第 2 页');
  });
}
