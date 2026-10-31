import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/play_source.dart';
import 'package:movie_app/services/api_service.dart';

/// 多源并发搜索的流式合并回归测试（2026-10-20）。
///
/// 背景：`_searchSourcesConcurrently` 旧实现给每个源建一个
/// StreamController，再由 `_mergeStreams` 在**装配时**一次性 listen。
/// 滑动窗口（并发上限 4）后续补入的 controller 永远拿不到 listener：
/// - 启用源超过 4 个时，第 5 个以后源的结果被静默丢弃；
/// - `total` 取的是装配时快照，前 4 个源返回后流就提前宣布完成。
/// 另外那 N 个 listen 订阅没有取消路径，消费者提前取消即泄漏。
///
/// 本测试用 6 个本地假采集站（loopback HttpServer + AppleCMS 响应格式）
/// 驱动真实 ApiService，断言：全部源都被搜索到、流不提前收摊、
/// 消费者取消不炸、且搜索后 `currentSource` 不被并发切换污染
/// （旧实现在 `_searchSingleSource` 里保存/切换/恢复 `_currentSource`，
/// 4 路并发交错恢复会把当前源留错）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test 的 binding 会把所有 HttpClient 请求 mock 成 400
  // （_MockHttpOverrides，防测试意外打网络）。本用例要驱动**真实**
  // loopback 假源站，必须显式关掉该 mock。
  HttpOverrides.global = null;

  // path_provider 走方法通道，单测里没有平台实现：mock 掉，
  // 否则 ApiService.init() → DioFactory.plainText() → getTemporaryDirectory() 会抛。
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => switch (call.method) {
      'getTemporaryDirectory' => Directory.systemTemp.path,
      'getApplicationSupportDirectory' => Directory.systemTemp.path,
      _ => null,
    },
  );

  group('多源并发搜索流式合并', () {
    late List<HttpServer> servers;
    late ApiService api;
    final requestLog = <String>[];

    setUp(() async {
      requestLog.clear();
      servers = [];
      api = ApiService();
      await api.init();
      api.setCurrentSource(
        PlaySource(
          id: 'default',
          name: '默认源',
          url: 'http://127.0.0.1:1/',
        ),
      );
    });

    tearDown(() async {
      for (final s in servers) {
        await s.close(force: true);
      }
    });

    /// 起一个假采集站：任意搜索请求都返回一部以 [tag] 命名的影片。
    Future<PlaySource> startFakeSource(String tag) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(server);
      server.listen((req) async {
        requestLog.add('$tag ${req.uri.query}');
        // 2026-10-28：片名必须**包含搜索关键词**——`searchFromAllSources`
        // 现在会过滤与关键词无关的结果（isSearchResultRelevant），
        // 假源固定返回 '$tag 影片' 会被整批丢光，导致流式/并发断言失真。
        final wd = req.uri.queryParameters['wd'] ?? '';
        final body = jsonEncode({
          'code': 1,
          'msg': 'ok',
          'page': 1,
          'pagecount': 1,
          'total': 1,
          'list': [
            {
              'vod_id': '${tag}_1',
              'vod_name': '$tag 影片 $wd',
              'type_name': '剧情',
            },
          ],
        });
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(body);
        await req.response.close();
      });
      return PlaySource(
        id: tag,
        name: '源 $tag',
        url: 'http://127.0.0.1:${server.port}/provide.php',
      );
    }

    /// 关键词带运行期唯一后缀：避开 dio_cache 磁盘缓存，
    /// 否则二次运行会命中缓存不打服务器，requestLog 断言失真。
    String uniqueKeyword(String base) =>
        '$base${DateTime.now().microsecondsSinceEpoch}';

    test('超过并发上限（6 源）时全部源都被搜索到，流不提前收摊', () async {
      final sources = <PlaySource>[
        for (final tag in ['a', 'b', 'c', 'd', 'e', 'f'])
          await startFakeSource(tag),
      ];

      final events = <MultiSourceSearchProgress>[];
      await for (final event
          in api.searchFromAllSources(uniqueKeyword('全量'), sources: sources)) {
        expect(event, isA<MultiSourceSearchProgress>());
        events.add(event as MultiSourceSearchProgress);
      }

      // 初始进度 0/6 + 每个源各一次 = 7 次。
      // 旧实现只合并装配时的前 4 个 controller：事件数为 5，
      // 且最终 completed 停在 4，第 5/6 个源的结果被丢弃。
      expect(
        events.length,
        7,
        reason: '旧实现提前收摊：只有初始 + 前 4 个源的事件',
      );
      expect(events.first.completed, 0);
      expect(events.last.completed, 6, reason: '全部 6 个源都应搜索完成');
      expect(events.last.total, 6);

      // 每个源的影片都出现在最终结果里
      // （片名形如 '$tag 影片 <关键词>'，故用前缀匹配而非全等）
      final names = events.last.results.map((m) => m.name).toSet();
      for (final tag in ['a', 'b', 'c', 'd', 'e', 'f']) {
        expect(
          names.any((n) => n.startsWith('$tag 影片')),
          isTrue,
          reason: '源 $tag 的结果不应被丢弃',
        );
      }

      // completed 单调递增到 total，无跳变（首个事件是 0/N 初始进度）
      var prev = -1;
      for (final e in events) {
        expect(e.completed, prev + 1);
        prev = e.completed;
      }
    });

    test('每个源只被请求一次（无重复/无遗漏）', () async {
      final sources = <PlaySource>[
        for (final tag in ['a', 'b', 'c', 'd', 'e', 'f'])
          await startFakeSource(tag),
      ];

      await for (final _ in api.searchFromAllSources(
        uniqueKeyword('去重'),
        sources: sources,
      )) {
        // 消费到底
      }

      final perSource = <String, int>{};
      for (final line in requestLog) {
        final tag = line.split(' ').first;
        perSource[tag] = (perSource[tag] ?? 0) + 1;
      }
      expect(perSource.length, 6, reason: '6 个源都应被请求');
      for (final entry in perSource.entries) {
        expect(entry.value, 1, reason: '源 ${entry.key} 被重复请求');
      }
    });

    test('消费者取消后：不抛未捕获异常，在飞任务安静收尾', () async {
      final sources = <PlaySource>[
        for (final tag in ['a', 'b', 'c', 'd', 'e', 'f'])
          await startFakeSource(tag),
      ];

      // 收到**第二个**事件（首个源结果）后取消：此刻内层搜索已启动、
      // 其余请求在飞。旧实现在此路径泄漏 N 个订阅 + broadcast eventQueue
      // 不关闭。若在首个事件（初始进度）就取消，内层尚未启动，测不到在飞任务。
      late final StreamSubscription<MultiSourceSearchEvent> sub;
      var eventCount = 0;
      sub = api
          .searchFromAllSources(uniqueKeyword('取消'), sources: sources)
          .listen((_) {
        eventCount++;
        if (eventCount >= 2) unawaited(sub.cancel());
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(eventCount, greaterThanOrEqualTo(2), reason: '应至少收到两个事件');

      // 等所有在飞请求自然结束（本地 server，远小于 Dio 30s 超时）
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (requestLog.length >= 6) break;
      }
      // 已启动的请求无法取消，但其结果被丢弃；关键是取消路径不抛
      // 未捕获异常、不挂起（本测试体本身就是异常收集器）。
      expect(requestLog.length, 6);
    });

    test('搜索后 currentSource 不被并发切换污染', () async {
      final sources = <PlaySource>[
        for (final tag in ['a', 'b', 'c', 'd', 'e', 'f'])
          await startFakeSource(tag),
      ];
      final before = PlaySource(
        id: 'default',
        name: '默认源',
        url: 'http://127.0.0.1:1/',
      );
      api.setCurrentSource(before);

      await for (final _ in api.searchFromAllSources(
        uniqueKeyword('污染'),
        sources: sources,
      )) {
        // 消费到底
      }

      expect(
        api.currentSource?.id,
        'default',
        reason: '多源搜索不应污染当前源（旧实现交错恢复会留错）',
      );
    });
  });

  group('SourceSearchResult 数据契约', () {
    test('错误源的错误事件带 error 且 movies 为空', () {
      final source = PlaySource(id: 's', name: 'S', url: 'http://x/');
      final r = SourceSearchResult(
        source: source,
        movies: const [],
        error: 'boom',
      );
      expect(r.error, 'boom');
      expect(r.movies, isEmpty);
      final ok = SourceSearchResult(
        source: source,
        movies: [Movie(id: '1', name: '甲')],
      );
      expect(ok.error, isNull);
      expect(ok.movies.single.name, '甲');
    });

    test('默认即最终段（isFinal 缺省为 true）', () {
      final source = PlaySource(id: 's', name: 'S', url: 'http://x/');
      // 不显式传 isFinal 时必须是"最终段"：单页源的一次性投递依赖这个缺省值。
      final r = SourceSearchResult(source: source, movies: const []);
      expect(r.isFinal, isTrue);
    });
  });

  // 2026-10-22：多源搜索改为**两段式投递**。
  //
  // 旧实现里每个源必须把最多 10 页**全部**拉完才交付结果，首屏因此被放大约
  // 10 倍（用户反馈「以前秒出，现在很慢」）。现在：第 1 页先交付（首屏秒回），
  // 补齐页在后台补上。
  group('多源搜索两段式投递（首屏不等补齐页）', () {
    late List<HttpServer> servers;
    late ApiService api;

    setUp(() async {
      servers = [];
      api = ApiService();
      await api.init();
    });

    tearDown(() async {
      for (final s in servers) {
        await s.close(force: true);
      }
    });

    /// 起一个「多页」假采集站：pagecount=3，每页返回 1 部影片。
    ///
    /// [gate] 非空时，第 2 页及以后要等 gate 放行才响应 —— 用来确定性地证明
    /// 「首屏事件在补齐页回来之前就到达了」。
    Future<PlaySource> startPagedSource(
      String tag, {
      Completer<void>? gate,
      void Function(int page)? onServed,
    }) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(server);
      server.listen((req) async {
        final pg = int.tryParse(req.uri.queryParameters['pg'] ?? '1') ?? 1;
        // 片名带上关键词，避免被相关性过滤（isSearchResultRelevant）丢弃。
        final wd = req.uri.queryParameters['wd'] ?? '';
        if (pg > 1 && gate != null) {
          await gate.future;
        }
        onServed?.call(pg);
        final body = jsonEncode({
          'code': 1,
          'msg': 'ok',
          'page': pg,
          'pagecount': 3,
          'total': 3,
          'list': [
            {
              'vod_id': '${tag}_p$pg',
              'vod_name': '$tag 第$pg页 $wd',
              'type_name': '剧情',
            },
          ],
        });
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(body);
        await req.response.close();
      });
      return PlaySource(
        id: tag,
        name: '源 $tag',
        url: 'http://127.0.0.1:${server.port}/provide.php',
      );
    }

    String uniqueKeyword(String base) =>
        '$base${DateTime.now().microsecondsSinceEpoch}';

    test('多页源产生两段事件：先第 1 页，后补齐页', () async {
      final source = await startPagedSource('paged');
      final events = <MultiSourceSearchProgress>[];
      await for (final e in api.searchFromAllSources(
        uniqueKeyword('两段'),
        sources: [source],
      )) {
        events.add(e as MultiSourceSearchProgress);
      }

      // 初始进度 + 阶段1（第 1 页）+ 阶段2（补齐页）= 3 次投递。
      expect(events.length, 3, reason: '多页源应拆成两段投递');
      expect(events[0].results, isEmpty, reason: '初始进度不带结果');

      // 阶段 1 就已经带出第 1 页 —— 这是"秒出"的关键。
      expect(events[1].results.length, 1, reason: '阶段1 应已带出第 1 页');
      expect(events[1].readySources, 1, reason: '已有 1 个源出结果');
      expect(events[1].completed, 0, reason: '该源还在补页，不算彻底搜完');
      expect(events[1].allSourcesDone, isFalse);

      // 阶段 2 补齐后，3 页的影片都在。
      expect(events[2].results.length, 3, reason: '补齐页后应有 3 部');
      expect(events[2].completed, 1, reason: '该源已彻底搜完');
      expect(events[2].allSourcesDone, isTrue, reason: '全部源已搜完');
    });

    test('首屏事件在补齐页响应之前就到达（旧实现要等所有页拉完）', () async {
      // 补齐页（第 2/3 页）被 gate 卡住，直到测试放行。
      final gate = Completer<void>();
      var slowPagesServed = 0;
      final source = await startPagedSource(
        'gated',
        gate: gate,
        onServed: (pg) {
          if (pg > 1) slowPagesServed++;
        },
      );

      var slowServedWhenFirstResultArrived = -1;
      await for (final e in api.searchFromAllSources(
        uniqueKeyword('秒出'),
        sources: [source],
      )) {
        final ev = e as MultiSourceSearchProgress;
        if (ev.results.isNotEmpty) {
          slowServedWhenFirstResultArrived = slowPagesServed;
          break;
        }
      }

      // 断言点：带结果的第一个事件到达时，补齐页**一个都还没回来**。
      expect(
        slowServedWhenFirstResultArrived,
        0,
        reason: '首屏必须先于补齐页到达；旧实现会等所有页拉完才交付',
      );

      gate.complete();
    });

    test('单页源仍只投递一次（不破坏既有"一源一事件"契约）', () async {
      // 复用上方 group 里 pagecount=1 的假源形态。
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(server);
      server.listen((req) async {
        final wd = req.uri.queryParameters['wd'] ?? '';
        final body = jsonEncode({
          'code': 1,
          'msg': 'ok',
          'page': 1,
          'pagecount': 1,
          'total': 1,
          'list': [
            // 片名带关键词，避免被相关性过滤丢弃（见 isSearchResultRelevant）。
            {'vod_id': 'single_1', 'vod_name': '单页影片 $wd', 'type_name': '剧情'},
          ],
        });
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(body);
        await req.response.close();
      });
      final source = PlaySource(
        id: 'single',
        name: '单页源',
        url: 'http://127.0.0.1:${server.port}/provide.php',
      );

      final events = <MultiSourceSearchProgress>[];
      await for (final e in api.searchFromAllSources(
        uniqueKeyword('单页'),
        sources: [source],
      )) {
        events.add(e as MultiSourceSearchProgress);
      }

      // 初始进度 + 单页源的一次性投递 = 2 次。
      expect(events.length, 2, reason: '单页源不应被拆成两段');
      expect(events.last.completed, 1);
      expect(events.last.readySources, 1);
      expect(events.last.allSourcesDone, isTrue);
    });

    // 2026-10-24：多页源的**补齐页不得占用并发槽位**。
    //
    // 旧实现里阶段 2（补齐第 2..N 页，最多 10 页）跑在
    // `_searchSingleSourceStaged` 内部，槽位要等补齐页全部结束才释放
    // → 一个慢源就能占死 4 个槽位中的一个，排队的第 5~N 个源**连启动
    // 都被推迟**。用户观感正是「第一个主源出来的时间还可以，其他源很慢」：
    // 首个源的第 1 页 ~2s 就到（屏幕有东西了），但后面的源要等前面几个源
    // 补完页才开跑。
    //
    // 现在：阶段 1 交付后立刻释放槽位，阶段 2 变成脱离槽位的后台任务。
    test('补齐页不占并发槽位：后面的源不必等前面的源补齐页', () async {
      // 6 个源：前 4 个是多页源（第 2 页起被 gate 卡住），后 2 个是单页源。
      // 并发上限 4 → 旧实现里 a~d 的补齐页不结束，x/y 永远排不上队。
      final gate = Completer<void>();
      final sources = <PlaySource>[
        for (final tag in ['a', 'b', 'c', 'd'])
          await startPagedSource(tag, gate: gate),
      ];
      for (final tag in ['x', 'y']) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        servers.add(server);
        server.listen((req) async {
          // 片名带关键词，避免被相关性过滤丢弃（见 isSearchResultRelevant）。
          final wd = req.uri.queryParameters['wd'] ?? '';
          final body = jsonEncode({
            'code': 1,
            'msg': 'ok',
            'page': 1,
            'pagecount': 1,
            'total': 1,
            'list': [
              {
                'vod_id': '${tag}_1',
                'vod_name': '$tag 单页影片 $wd',
                'type_name': '剧情',
              },
            ],
          });
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(body);
          await req.response.close();
        });
        sources.add(
          PlaySource(
            id: tag,
            name: '源 $tag',
            url: 'http://127.0.0.1:${server.port}/provide.php',
          ),
        );
      }

      final seenNames = <String>{};
      final lateSourced = Completer<void>();
      final sub = api
          .searchFromAllSources(uniqueKeyword('槽位'), sources: sources)
          .listen((e) {
        final ev = e as MultiSourceSearchProgress;
        for (final m in ev.results) {
          seenNames.add(m.name);
        }
        if (seenNames.any((n) => n.startsWith('x 单页影片')) &&
            seenNames.any((n) => n.startsWith('y 单页影片')) &&
            !lateSourced.isCompleted) {
          lateSourced.complete();
        }
      });

      try {
        // 关键断言：在补齐页被放行**之前**，排队的 x/y 就该搜到并出结果。
        // 旧实现会在这里一直等（x/y 连启动都没被排上），15s 超时 → 测试变红。
        await lateSourced.future.timeout(const Duration(seconds: 15));
        expect(
          seenNames.any((n) => n.startsWith('x 单页影片')),
          isTrue,
          reason: '排队的源不该被前面源的补齐页挡住',
        );
        expect(
          seenNames.any((n) => n.startsWith('y 单页影片')),
          isTrue,
          reason: '排队的源不该被前面源的补齐页挡住',
        );
      } finally {
        // 放行补齐页，让流能正常收尾（失败路径也要收口，否则测试挂住）。
        gate.complete();
      }

      await sub.asFuture<void>().timeout(const Duration(seconds: 20));
      // 补齐页最终仍要送达（后台任务没被丢掉）。
      expect(seenNames.any((n) => n.startsWith('a 第2页')), isTrue);
      expect(seenNames.any((n) => n.startsWith('d 第3页')), isTrue);
    });
  });
}
