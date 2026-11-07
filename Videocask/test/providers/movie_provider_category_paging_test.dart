import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/play_source.dart';
import 'package:movie_app/providers/movie_provider.dart';

/// 类目 Tab 取数策略回归测试（2026-10-21 用户反馈后重构）。
///
/// 契约（用户明确要求）：
/// 1. **主源（设置里「使用中」的源）是翻页主轴**：首屏只等主源，其余源
///    只做补充、不参与翻页；源可以有几百个，不能全量并发 × 3 子类。
/// 2. 补充源**限量**（[MovieProvider.categorySupplementMaxSources]）且与
///    已渲染数据去重后追加，不在用户眼前插队。
/// 3. 首屏出内容后后台预取下一页，滚动续页命中预取、不再打网络。
///
/// 用本地假采集站（loopback HttpServer + 苹果CMS 格式）驱动真实
/// MovieProvider，断言请求日志，防止「悄悄回到全源并发」。
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

  /// 电影（1）下挂 6 个子类，子类 id 连续，便于断言请求集合。
  const movieSubClassIds = [6, 7, 8, 9, 10, 11];

  group('类目取数：主源主轴 + 补充源受限', () {
    late HttpServer server;
    late MovieProvider provider;
    late PlaySource primary;
    final requestLog = <String>[];

    /// 源标识（url path 首段）。
    ///
    /// ⚠️ 不能用 query 参数区分源：ApiService 发请求时会重写 query
    /// （日志实测 `?ac=detail&pg=1&t=6`，自定义参数被丢掉），且分类树缓存
    /// 按 url 键 —— query 相同会让所有源共用同一棵树。
    String sourceOf(String logLine) =>
        RegExp(r'/([^/?]+)/provide\.php').firstMatch(logLine)?.group(1) ?? '';

    /// 请求过的源集合，去重保持顺序。
    List<String> requestedSources() {
      final out = <String>[];
      for (final q in requestLog) {
        final src = sourceOf(q);
        if (src.isNotEmpty && !out.contains(src)) out.add(src);
      }
      return out;
    }

    /// 带 `pg=` 的取数请求里出现过的源。
    List<String> sourcesOfPageRequests(int pg) => requestLog
        .where((q) => q.contains('pg=$pg') && q.contains('ac=detail'))
        .map(sourceOf)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    setUp(() async {
      requestLog.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final q = req.uri.queryParameters;
        requestLog.add(req.uri.toString());
        final src = req.uri.pathSegments.isNotEmpty ? req.uri.pathSegments.first : '';
        dynamic body;
        if (q['ac'] == 'list') {
          body = {
            'code': 1,
            'msg': 'ok',
            'class': <Map<String, String>>[
              {'type_id': '1', 'type_name': '电影', 'type_pid': '0'},
              for (final id in movieSubClassIds)
                {
                  'type_id': '$id',
                  'type_name': '子类$id',
                  'type_pid': '1',
                },
              {'type_id': '2', 'type_name': '剧集', 'type_pid': '0'},
              {'type_id': '20', 'type_name': '国产剧', 'type_pid': '2'},
              {'type_id': '21', 'type_name': '日韩剧', 'type_pid': '2'},
            ],
          };
        } else {
          // 补充源故意慢：验证首屏不等它们。
          if (src != 'primary') {
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
          final t = q['t'] ?? '0';
          final pg = int.tryParse(q['pg'] ?? '1') ?? 1;
          body = {
            'code': 1,
            'msg': 'ok',
            'page': pg,
            'pagecount': 5,
            'total': 100,
            'list': [
              {
                'vod_id': '${src}_${t}_$pg',
                // 片名带源名与页码，便于断言条目来源。
                'vod_name': '$src-子类$t-第$pg页',
                'type_id': t,
                'type_name': '子类$t',
                'vod_year': '2024',
              },
            ],
          };
        }
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(body));
        await req.response.close();
      });

      provider = MovieProvider();
      await provider.apiService.init();
      primary = PlaySource(
        id: 'primary',
        name: '主源',
        url: 'http://127.0.0.1:${server.port}/primary/provide.php',
      );
      // 「使用中」的主源。
      provider.apiService.setCurrentSource(primary);
    });

    tearDown(() async {
      await server.close(force: true);
    });

    /// 造 [count] 个启用源（url 带不同 src= 区分）。
    List<PlaySource> buildSources(int count) => [
          primary,
          for (var i = 1; i <= count; i++)
            PlaySource(
              id: 's$i',
              name: '补充源$i',
              url: 'http://127.0.0.1:${server.port}/s$i/provide.php',
            ),
        ];

    test('首屏只等主源：主源返回即可用，不等补充源', () async {
      // 100 个源 —— 契约是「只等主源、补充限量」，不是全量并发。
      await provider.loadCategoryMovies(
        category: '电影',
        refresh: true,
        mergeSources: buildSources(100),
      );

      final names = provider.categoryMovies.map((m) => m.name).toList();
      expect(names, isNotEmpty);
      // 首屏内容只来自主源（补充源还在路上）。
      expect(names.every((n) => n.startsWith('primary-')), isTrue,
          reason: '首屏必须只由主源内容构成，才能做到「主源回来就渲染」');
      expect(names.any((n) => n.startsWith('s1-')), isFalse);
    });

    test('补充源限量：源再多也只补前 N 个', () async {
      await provider.loadCategoryMovies(
        category: '电影',
        refresh: true,
        mergeSources: buildSources(100),
      );
      // 等补充源回来（假站里每个补充源 300ms）。
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final supplement = requestedSources()
          .where((s) => s != 'primary')
          .toList(growable: false);
      expect(
        supplement.length,
        lessThanOrEqualTo(MovieProvider.categorySupplementMaxSources),
        reason: '源有几百个时全量并发会让请求数与流量失控',
      );
      expect(supplement.length, greaterThan(0), reason: '确实做了补充，不是干脆不补');
    });

    test('补充源去重后追加到末尾（不插队、不重复）', () async {
      await provider.loadCategoryMovies(
        category: '电影',
        refresh: true,
        mergeSources: buildSources(3),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final names = provider.categoryMovies.map((m) => m.name).toList();
      // 主源内容仍在最前（补充是追加，不插队导致列表跳动）。
      expect(names.first.startsWith('primary-'), isTrue);
      // 补充内容出现在后面。
      expect(names.any((n) => n.startsWith('s1-')), isTrue);
      // 无重复条目。
      expect(names.toSet().length, names.length);
    });

    test('续页只翻主源（源多不放大请求量）', () async {
      final sources = buildSources(50);
      await provider.loadCategoryMovies(
        category: '电影',
        refresh: true,
        mergeSources: sources,
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      requestLog.clear();

      await provider.loadCategoryMovies(
        category: '电影',
        refresh: false,
        mergeSources: sources,
      );

      // 续页命中后台预取时是零请求；未命中则只允许主源发请求。
      // 契约核心是「不带上其余 50 个源」——否则一次滚动打出上百个请求。
      final pagingSources = sourcesOfPageRequests(2);
      expect(pagingSources.where((s) => s != 'primary'), isEmpty,
          reason: '翻页主轴是主源；若带上 50 个源，一次滚动就打出上百个请求');
    });

    test('首屏后预取下一页：续页命中预取不再打网络', () async {
      final sources = buildSources(2);
      await provider.loadCategoryMovies(
        category: '电影',
        refresh: true,
        mergeSources: sources,
      );
      // 等补充 + 预取完成。
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final pg2Prefetch = sourcesOfPageRequests(2);
      expect(pg2Prefetch, <String>['primary'],
          reason: '首屏出内容后应后台预取主源第 2 页');

      requestLog.clear();
      await provider.loadCategoryMovies(
        category: '电影',
        refresh: false,
        mergeSources: sources,
      );

      expect(
        requestLog.where((q) => q.contains('ac=detail')),
        isEmpty,
        reason: '续页应直接消费预取页，不再打网络',
      );
      expect(provider.categoryMovies.any((m) => m.name.contains('第2页')), isTrue);
    });

    test('切回已看过的类目：缓存命中，同步就有内容（不转圈）', () async {
      await provider.loadCategoryMovies(
        category: '电影',
        refresh: true,
        mergeSources: buildSources(2),
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final before = provider.categoryMovies.length;

      // 切走再切回：不 await —— 缓存命中必须同步渲染。
      provider.loadCategoryMovies(
        category: '电影',
        refresh: true,
        mergeSources: buildSources(2),
      );

      expect(provider.isLoading, isFalse, reason: '缓存命中不该走转圈');
      expect(provider.categoryMovies.length, before,
          reason: '缓存命中应立刻恢复上一次的首屏内容');
    });

    test('切 Tab 作废上一个类目的预取页（不串类目）', () async {
      await provider.loadCategoryMovies(
        category: '电影',
        refresh: true,
        mergeSources: buildSources(2),
      );
      // 不等预取完成就切走：预取结果必须被代次守卫丢弃。
      await provider.loadCategoryMovies(
        category: '剧集',
        refresh: true,
        mergeSources: buildSources(2),
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));

      final names = provider.categoryMovies.map((m) => m.name).toList();
      // 「剧集」类目下不应混入电影子类（t=6..11）的内容。
      expect(
        names.any((n) => n.contains('子类6') || n.contains('子类7')),
        isFalse,
        reason: '过期的电影类目预取/补充不能污染剧集类目',
      );
    });
  });
}
