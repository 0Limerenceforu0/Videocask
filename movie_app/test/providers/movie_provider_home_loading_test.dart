import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/play_source.dart';
import 'package:movie_app/providers/movie_provider.dart';

/// 首页首屏加载态回归测试（2026-10-22 用户反馈「主页一直加载，下滑才出」）。
///
/// 根因：`loadHomeData()` 的 finally 只写了 `if (!_isLoading) notifyListeners();`
/// ——既不把 `_isLoading` 清零（永真），守卫还写反了（加载中反而发不出通知）。
/// 数据早已落到 provider，UI 收不到重建信号，骨架屏卡死；直到滚动/下拉触发
/// 别的 notify 才「突然出现」。
///
/// 契约（摘修复即红）：
/// 1. `loadHomeData()` 成功完成 → `isLoading` 必须回到 false；
/// 2. 完成瞬间必须发出通知（否则 UI 不重建，数据到了也看不到）；
/// 3. 失败路径同样退出加载态（不能永久骨架屏，至少要让错误 UI 有机会出来）；
/// 4. 并发防踩：分类首屏（refresh）还在跑时，首页 finally 不许清 `_isLoading`，
///    否则分类的转圈被提前灭掉（第 4 条是修复自身的守卫，非摘修复即红）。
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

  group('首页首屏加载态：完成必须退加载态 + 发通知', () {
    late HttpServer server;
    late MovieProvider provider;
    late PlaySource primary;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final q = req.uri.queryParameters;
        dynamic body;
        if (q['ac'] == 'list') {
          body = {
            'code': 1,
            'msg': 'ok',
            'class': <Map<String, String>>[
              {'type_id': '1', 'type_name': '电影', 'type_pid': '0'},
              for (final id in [6, 7, 8, 9, 10, 11])
                {'type_id': '$id', 'type_name': '子类$id', 'type_pid': '1'},
              {'type_id': '2', 'type_name': '剧集', 'type_pid': '0'},
              {'type_id': '20', 'type_name': '国产剧', 'type_pid': '2'},
              {'type_id': '21', 'type_name': '日韩剧', 'type_pid': '2'},
            ],
          };
        } else {
          // 分类请求带 t=（子类 id）—— 故意放慢，供「并发防踩」用例
          // 制造「分类还在跑、首页已完成」的时序窗口；首页请求不带 t，秒回。
          if (q.containsKey('t')) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
          }
          final pg = int.tryParse(q['pg'] ?? '1') ?? 1;
          body = {
            'code': 1,
            'msg': 'ok',
            'page': pg,
            'pagecount': 5,
            'total': 100,
            'list': [
              {
                'vod_id': 'home_$pg',
                'vod_name': '首页影片-第$pg页',
                'type_id': q['t'] ?? '0',
                'type_name': '子类',
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
      provider.apiService.setCurrentSource(primary);
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('loadHomeData 成功完成：退出加载态 + 完成瞬间发通知', () async {
      final notifications = <int>[];
      provider.addListener(() => notifications.add(1));

      // 启动但不 await：同步前缀会发一次「进入加载态」通知，先记数。
      final future = provider.loadHomeData();
      final countAtStart = notifications.length;
      await future;

      expect(
        provider.isLoading,
        isFalse,
        reason: '加载完成后 isLoading 必须回 false —— 旧代码永不清零，'
            '骨架屏条件 isLoading && !hasAnyData 永真，主页一直转圈',
      );
      expect(
        notifications.length,
        greaterThan(countAtStart),
        reason: '完成时必须发通知 —— 旧代码 if (!_isLoading) 守卫写反，'
            '数据落到 provider 但 UI 不重建，直到滚动/下拉触发别的 notify',
      );
      // 数据确实落位（否则上面两条会被「空数据也通知」蒙混过关）。
      expect(provider.latestMovies, isNotEmpty);
      expect(provider.hotMovies, isNotEmpty);
    });

    test('loadHomeData 失败：同样退出加载态（不留永久转圈）', () async {
      // 指向一个没人监听的端口 → 连接被拒。注意 getHomeData 内部吞错后走
      // HomeData.empty() 兜底——该"empty"实际返回模拟影片（无源时展示用），
      // 所以分区不会报错、而是显示兜底内容；本用例只锁「不卡转圈」契约。
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = dead.port;
      await dead.close(force: true);
      provider.apiService.setCurrentSource(
        PlaySource(
          id: 'dead',
          name: '死源',
          url: 'http://127.0.0.1:$deadPort/dead/provide.php',
        ),
      );

      await provider.loadHomeData();

      expect(
        provider.isLoading,
        isFalse,
        reason: '取数失败也不能把 isLoading 留真 —— 旧代码永不清零，'
            '骨架屏条件 isLoading && !hasAnyData 永真，主页一直转圈',
      );
    });

    test('并发防踩：分类首屏在跑时，首页完成不清 isLoading', () async {
      // 分类首屏（带 t= 请求，假站延迟 400ms）。
      final catFuture = provider.loadCategoryMovies(
        category: '电影',
        refresh: true,
        mergeSources: [primary],
      );
      expect(provider.isLoading, isTrue, reason: '分类首屏应进入转圈');

      // 首页并发完成（不带 t=，秒回）。
      final homeFuture = provider.loadHomeData();
      await homeFuture;

      expect(
        provider.isLoading,
        isTrue,
        reason: '分类首屏仍在跑，首页 finally 不许踩掉 _isLoading —— '
            '否则分类转圈被提前灭掉，首屏内容还没出来就停转',
      );

      await catFuture;
      expect(provider.isLoading, isFalse, reason: '分类首屏完成后应停转');
    });
  });
}
