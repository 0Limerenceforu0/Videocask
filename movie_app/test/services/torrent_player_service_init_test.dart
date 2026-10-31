import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/torrent_player_service.dart';

/// 磁力 P2P 引擎 init 的契约回归。
///
/// 背景（2026-10-24 真机实测 run2，日志实证）：
/// 启动期预热与播放流程的 `init()` 只有一道非原子 `_isInitialized` 守卫，
/// 两个调用同时穿过守卫 → 双双进入 `LibtorrentFlutter.init()`，其中一个必在
/// `cacert.pem.pending → cacert.pem` 的重命名上撞
/// `PathNotFoundException`（失败方还顺手把状态置成 error，污染 UI）。
///
/// 契约：
/// 1. 并发 `init()` 共享同一次初始化（Future 去重）——摘掉去重即红；
/// 2. 初始化结束后不缓存 Future，允许后续（用户真播放时）重试；
/// 3. libtorrent 的 -1（「未知」哨兵）不得泄漏到展示层；
/// 4. dispose 不焊死 init（测试装配-卸载周期可重新初始化）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TorrentPlayerService.init 契约', () {
    test('并发 init 共享同一次初始化（Future 去重）', () async {
      final service = TorrentPlayerService();
      final f1 = service.init();
      final f2 = service.init();
      // 摘掉 Future 去重（退回「每调用一个独立 Future」的旧实现）后，
      // 两个调用会各拿到一个独立 Future → 本断言红。
      expect(identical(f1, f2), isTrue);
      await f1;
    });

    test('初始化结束后不缓存 Future，允许后续重试', () async {
      final service = TorrentPlayerService();
      final f1 = service.init();
      await f1;
      final f2 = service.init();
      // 预热失败（如飞行模式）不得把「以后都失败」焊死：完成即清标记，
      // 用户真播放时的 init() 必须能重新走一遍。
      expect(identical(f1, f2), isFalse);
      await f2;
    });

    test('libtorrent -1 哨兵归一为「未知」，不泄漏到展示', () {
      // 真机实测：整个磁力加载期 num_peers/num_seeds 都是 -1（status 查询
      // 未带 peer 统计位时的「未知」哨兵）。直接显示「做种 -1」或拿它参与
      // `_seeds == 0` 判定（永假 → 死种早停失效）都会误导用户。
      expect(formatSwarmCount(-1), '未知');
      expect(formatSwarmCount(-999), '未知');
      expect(formatSwarmCount(0), '0');
      expect(formatSwarmCount(7), '7');
    });

    test('dispose 不焊死 init：释放后仍可重新初始化', () async {
      final service = TorrentPlayerService();
      await service.init();
      await service.dispose();
      // dispose 把去重标记一并清掉；若残留悬空 Future，此处的 init()
      // 会拿到一个永远不会重新执行的旧 Future。
      final after = service.init();
      expect(after, isNotNull);
      await after;
      expect(service.isInitialized, isFalse); // 测试环境跳过原生初始化
    });
  });

  group('buildEnhancedMagnet 契约（peer 发现速度）', () {
    const preferred = <String>[
      'http://fast.example:1337/announce',
      'udp://second.example:6969/announce',
    ];

    List<String> trackersOf(String uri) => RegExp(r'[?&]tr=([^&]+)')
        .allMatches(uri)
        .map((m) => Uri.decodeComponent(m.group(1)!))
        .toList();

    test('精选 tracker 排在最前，站点自带 tracker 保留并挪到队尾', () {
      final out = buildEnhancedMagnet(
        'magnet:?xt=urn:btih:ABC&dn=Foo&tr=http%3A%2F%2Fdead.example%2Fannounce',
        preferred,
      );
      final trs = trackersOf(out);

      // 核心契约：第一条被 announce 的必须是精选（死链不能占住队首，
      // 否则每条要烧 ~10s 超时，真能返回 peer 的 tracker 要等到 40s 后）。
      expect(trs.first, preferred.first);
      expect(trs[1], preferred[1]);
      // 站点自带的仍然保留（可能存活），但已不在队首。
      expect(trs.last, 'http://dead.example/announce');
      expect(trs.length, 3);
    });

    test('xt / dn 原样保留且不改变顺序', () {
      final out = buildEnhancedMagnet(
        'magnet:?xt=urn:btih:ABC&dn=Foo&xl=123',
        preferred,
      );
      expect(out.startsWith('magnet:?xt=urn:btih:ABC&dn=Foo&xl=123'), isTrue);
      expect(trackersOf(out), preferred);
    });

    test('已存在的精选 tracker 不重复追加', () {
      final out = buildEnhancedMagnet(
        'magnet:?xt=urn:btih:ABC&tr=${Uri.encodeComponent(preferred.first)}',
        preferred,
      );
      final trs = trackersOf(out);
      expect(trs.where((t) => t == preferred.first).length, 1);
      expect(trs.length, 2);
    });

    test('非磁力 / 无 xt 原样返回，不拼非法 URI', () {
      expect(buildEnhancedMagnet('http://x/y', preferred), 'http://x/y');
      expect(buildEnhancedMagnet('magnet:?dn=Foo', preferred), 'magnet:?dn=Foo');
    });
  });
}
