import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/play_source.dart';
import 'package:movie_app/providers/movie_provider.dart';

/// 详情页「换源」搜索回归测试（2026-10-23 用户反馈「点击换源半天不能出来结果」）。
///
/// 契约（用户明确要求）：
/// 1. **不能等所有源都回来才出结果**：任一源先搜完就先投递一次快照
///    （`onPartial`），UI 边收边显示。
/// 2. **单个慢源不能拖住整张表**：每个源有独立超时，超时即放弃该源。
/// 3. 仍要按匹配分降序（同名同年的排最前）。
///
/// 用本地假采集站（loopback HttpServer + 苹果CMS 格式）驱动真实
/// MovieProvider：fast 源立即返回，slow 源挂住不返回 —— 用来证明
/// 「不等全部」与「单源超时」确实生效。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test 的 binding 会把所有 HttpClient 请求 mock 成 400；
  // 本用例要驱动真实 loopback 假源站，必须显式关掉该 mock。
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

  group('换源搜索：增量投递 + 单源超时', () {
    late HttpServer server;
    late MovieProvider provider;
    late PlaySource fastSource;
    late PlaySource slowSource;
    late PlaySource otherSource;

    /// 假采集站：fast 立即返回同一部片；slow 挂住（不响应，测超时）；
    /// other 返回一部年份不同的片子（测排序）。
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      provider = MovieProvider();

      PlaySource makeSource(String name) => PlaySource(
            id: name,
            name: name,
            url: 'http://127.0.0.1:${server.port}/$name/provide.php',
            enabled: true,
          );

      fastSource = makeSource('fast');
      slowSource = makeSource('slow');
      otherSource = makeSource('other');

      server.listen((request) async {
        final path = request.uri.path;
        if (path.startsWith('/slow/')) {
          // 永不响应 → 触发单源超时。
          return;
        }
        final year = path.startsWith('/other/') ? '2015' : '2009';
        final body = jsonEncode({
          'code': 1,
          'pagecount': 1,
          'list': [
            {
              'vod_id': path.contains('/other/') ? 2 : 1,
              'vod_name': '爱情公寓1',
              'vod_year': year,
              'vod_score': '8.1',
            }
          ],
        });
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(body);
        await request.response.close();
      });
    });

    tearDown(() async {
      provider.dispose();
      await server.close(force: true);
    });

    test('第一个源返回就投递快照，不等其它源', () async {
      final snapshots = <int>[];

      final future = provider.searchMovieAcrossSources(
        keyword: '爱情公寓1',
        year: '2009',
        sources: [fastSource, slowSource],
        onPartial: (list) => snapshots.add(list.length),
      );

      // 等第一批（fast 源）完成：此时应已至少投递过一次非空快照。
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (snapshots.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(
        snapshots,
        isNotEmpty,
        reason: '第一个源返回后就应投递快照（增量投递）',
      );
      expect(
        snapshots.first,
        greaterThan(0),
        reason: '首次投递的快照应已含 fast 源匹配到的候选',
      );

      // 不等 slow 源：直接结束本次调用（slow 源仍在后台挂着）。
      unawaited(future);
    });

    test('慢源被超时放弃，其余候选仍能返回', () async {
      final result = await provider.searchMovieAcrossSources(
        keyword: '爱情公寓1',
        year: '2009',
        sources: [fastSource, slowSource],
      );

      expect(
        result,
        isNotEmpty,
        reason: '慢源超时不应影响快源的候选',
      );
      expect(
        result.any((c) => c.source.id == fastSource.id),
        isTrue,
        reason: '快源候选应在结果里',
      );
      expect(
        result.any((c) => c.source.id == slowSource.id),
        isFalse,
        reason: '慢源超时后应被放弃，不产生候选',
      );
    });

    test('结果按匹配分降序：同名同年排在同名不同年前面', () async {
      final result = await provider.searchMovieAcrossSources(
        keyword: '爱情公寓1',
        year: '2009',
        sources: [otherSource, fastSource],
      );

      expect(result.length, 2);
      expect(
        result.first.source.id,
        fastSource.id,
        reason: '同名同年的分更高，应排最前',
      );
      expect(result.last.source.id, otherSource.id);
    });
  });
}

/// 忽略未等待的 future（测试里用于让慢源请求继续挂着）。
void unawaited(Future<void> future) {}
