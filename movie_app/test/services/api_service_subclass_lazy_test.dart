import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/play_source.dart';
import 'package:movie_app/services/api_service.dart';

/// 分类 Tab「最小代价取数」回归测试（2026-10-21）。
///
/// 背景：切 Tab 旧实现把分类展开为**全部子类**（电影 = 12 个）× 每源各 1 页，
/// 实测一次切 Tab ≈ 60 个 `ac=detail` 请求、每页 961KB ≈ 57MB，首屏 10s+。
/// 现在首屏只拉前 [ApiService.defaultSubClassCount] 个子类，点「小分类」chip
/// 才按需传 `t=` 拉单个子类。
///
/// 本测试用本地假采集站（loopback HttpServer + 苹果CMS 格式）驱动真实
/// ApiService，断言请求的 `t=` 集合，防止「悄悄回到全展开」。
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

  /// 电影（1）下挂 6 个子类（6..11），剧集（2）下挂 1 个子类（3）。
  /// 子类 id 连续，便于断言「前 N 个」。
  const movieSubClassIds = [6, 7, 8, 9, 10, 11];

  group('分类 Tab 子类懒加载', () {
    late HttpServer server;
    late ApiService api;
    late PlaySource source;
    final requestLog = <String>[];

    setUp(() async {
      requestLog.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final q = req.uri.queryParameters;
        requestLog.add(req.uri.query);
        dynamic body;
        if (q['ac'] == 'list') {
          body = {
            'code': 1,
            'msg': 'ok',
            'class': <Map<String, String>>[
              {'type_id': '1', 'type_name': '电影', 'type_pid': '0'},
              for (var i = 0; i < movieSubClassIds.length; i++)
                {
                  'type_id': '${movieSubClassIds[i]}',
                  'type_name': '子类${movieSubClassIds[i]}',
                  'type_pid': '1',
                },
              {'type_id': '2', 'type_name': '剧集', 'type_pid': '0'},
              {'type_id': '3', 'type_name': '国产剧', 'type_pid': '2'},
            ],
          };
        } else {
          // ac=detail&t=X&pg=N：每个子类一页一部影片。
          final t = q['t'] ?? '0';
          final pg = int.tryParse(q['pg'] ?? '1') ?? 1;
          body = {
            'code': 1,
            'msg': 'ok',
            'page': pg,
            'pagecount': 3,
            'total': 60,
            'list': [
              {
                'vod_id': '${t}_$pg',
                'vod_name': '子类$t 影片',
                'type_id': t,
                'type_name': '子类$t',
              },
            ],
          };
        }
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(body));
        await req.response.close();
      });
      api = ApiService();
      await api.init();
      source = PlaySource(
        id: 'fake',
        name: '假源',
        url: 'http://127.0.0.1:${server.port}/provide.php',
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    /// 本次请求里出现过的 `t=` 值（去重、**按数值升序**）。
    ///
    /// 不要返回「到达顺序」：多个子类请求是并发发出的，本地 server 收到
    /// 谁先谁后不确定，断言顺序会随机红（实测同一份代码连跑 3 次红 2 次）。
    /// 子类 id 本身是有序的，排序后比较既稳定又能抓「全量请求」回归。
    List<String> requestedTypeIds() {
      final out = <String>{};
      for (final q in requestLog) {
        final m = RegExp(r'(?:^|&)t=(\d+)').firstMatch(q);
        if (m != null) out.add(m.group(1)!);
      }
      final ids = out.toList()..sort((a, b) => int.parse(a) - int.parse(b));
      return ids;
    }

    test('首屏默认只拉前 N 个子类（不是全部）', () async {
      final page = await api.fetchCategoryPageForSource(source, '电影');

      // 契约：远小于全部子类数（6）；当前实现为 3。
      // ⚠️ 这里必须钉字面量 3：若写成 take(ApiService.defaultSubClassCount)，
      // 常量一改断言跟着变形同虚设（负向验证实测抓不到回归）。
      expect(
        requestedTypeIds(),
        <String>['6', '7', '8'],
        reason: '首屏应只请求前 3 个子类；全展开会让一次切 Tab 打出 ~60 个请求',
      );
      expect(
        requestedTypeIds().length,
        lessThan(movieSubClassIds.length),
        reason: '默认量必须显著小于子类总数',
      );
      expect(page.movies, isNotEmpty);
    });

    test('点小分类 chip：只请求选中的那一个子类', () async {
      final page = await api.fetchCategoryPageForSource(
        source,
        '电影',
        subClassId: 10,
      );

      expect(requestedTypeIds(), <String>['10']);
      expect(page.movies.single.name, '子类10 影片');
    });

    test('「全部」chip：显式展开全部子类', () async {
      await api.fetchCategoryPageForSource(source, '电影', allSubClasses: true);

      expect(
        requestedTypeIds(),
        movieSubClassIds.map((e) => '$e').toList(),
        reason: '用户显式选择「全部」时才付出全量请求代价',
      );
    });

    test('续页与首屏同一批子类（翻页不换子类取数）', () async {
      await api.fetchCategoryPageForSource(source, '电影', page: 1);
      final firstPageIds = requestedTypeIds();
      requestLog.clear();
      await api.fetchCategoryPageForSource(source, '电影', page: 2);

      final secondPageIds = requestLog
          .where((q) => q.contains('pg=2'))
          .map((q) => RegExp(r'(?:^|&)t=(\d+)').firstMatch(q)?.group(1))
          .toSet();
      expect(
        secondPageIds,
        firstPageIds.toSet(),
        reason: '续页若换成另一批子类，列表内容会前后对不上',
      );
    });

    test('subClassesFor 返回子类节点供 chip 行使用', () async {
      api.setCurrentSource(source);
      // 树未缓存时应为空（UI 据此隐藏 chip 行）。
      expect(api.subClassesFor('电影'), isEmpty);

      await api.fetchCategoryPageForSource(source, '电影');
      final subs = api.subClassesFor('电影');
      expect(subs.map((n) => n.id).toList(), movieSubClassIds);
      expect(subs.map((n) => n.name).toList(), [
        '子类6',
        '子类7',
        '子类8',
        '子类9',
        '子类10',
        '子类11',
      ]);
    });

    test('多源首屏合并也遵守默认限量', () async {
      await api.aggregateCategoryFirstPage(
        sources: [source],
        category: '电影',
      );

      expect(
        requestedTypeIds().length,
        lessThan(movieSubClassIds.length),
        reason: '多源合并同样只应拉前 N 个子类',
      );
    });

    test('另一个分类（剧集）互不串台：只拉自己的子类', () async {
      await api.fetchCategoryPageForSource(source, '剧集');

      expect(requestedTypeIds(), <String>['3']);
    });
  });
}
