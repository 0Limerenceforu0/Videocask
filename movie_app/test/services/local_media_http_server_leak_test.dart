import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/local_media_http_server.dart';

/// fd 泄漏**归属**测试：证明或否证「HLS 本地代理」是不是真机 fd 暴涨的泄漏源。
///
/// 背景：真机日志（2026-10-20）显示播放期间 fd 以 ~23 个/秒单调增长到 3 万+，
/// 直至 `Looper::rebuildEpollLocked` 触发 SIGABRT 闪退；而播放器回收兜底触发
/// 197 次、一次都没成功。要根治，必须先确定泄漏**在哪一侧**：
///
/// - 若本代理请求都能正常收尾（在途归零、连接复用、fd 不涨）→ 代理清白，
///   泄漏在播放器/引擎侧，方向完全不同；
/// - 若有请求悬挂（在途爬升 / 客户端断开后不收尾）→ 代理就是真凶。
///
/// 与 `local_media_http_server_e2e_test.dart` 的分工：那边验证**单次**错误响应
/// 有没有 drain；这边验证**长跑/异常中断**下的收尾率与连接增长。
class FakeOrigin {
  FakeOrigin(this.server);

  final HttpServer server;

  /// 收到的分片请求次数。
  int hits = 0;

  /// 正常分片内容。
  List<int> okSegment = List<int>.filled(256, 0x42);

  /// 错误分片的状态码（默认 403，用于触发 drain 路径）。
  int errorStatus = 403;

  int get port => server.port;

  /// 源站累计接受的连接数（用于判定代理是否复用连接）。
  int get totalConnections => server.connectionsInfo().total;

  /// 源站当前活跃连接数。
  int get activeConnections => server.connectionsInfo().active;

  Future<void> close() => server.close(force: true);
}

Future<FakeOrigin> startOrigin({int okSegmentCount = 5}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final origin = FakeOrigin(server);

  server.listen((req) async {
    final path = req.uri.path;
    if (path.endsWith('.m3u8')) {
      final buffer = StringBuffer('#EXTM3U\n#EXT-X-VERSION:3\n');
      buffer.writeln('#EXT-X-TARGETDURATION:10');
      buffer.writeln('#EXT-X-MEDIA-SEQUENCE:0');
      buffer.writeln('#EXT-X-PLAYLIST-TYPE:VOD');
      // 全部同域、等长、无 DISCONTINUITY → 广告过滤器不误删，序号确定。
      for (var i = 0; i < okSegmentCount; i++) {
        buffer.writeln('#EXTINF:10.000,');
        buffer.writeln('http://127.0.0.1:${origin.port}/seg_ok.ts');
      }
      buffer.writeln('#EXTINF:10.000,');
      buffer.writeln('http://127.0.0.1:${origin.port}/seg_bad.ts');
      buffer.writeln('#EXT-X-ENDLIST');
      req.response.headers.contentType =
          ContentType('application', 'vnd.apple.mpegurl');
      req.response.add(utf8.encode(buffer.toString()));
      await req.response.close();
      return;
    }

    origin.hits++;
    if (path.contains('seg_bad')) {
      req.response.statusCode = origin.errorStatus;
      // 错误响应也带 body，逼代理走 drain 路径。
      req.response.add(List<int>.filled(64 * 1024, 0x41));
      await req.response.close();
      return;
    }

    req.response.add(origin.okSegment);
    await req.response.close();
  });

  return origin;
}

Future<String> getText(HttpClient client, Uri uri) async {
  final req = await client.getUrl(uri);
  final res = await req.close();
  return res.transform(utf8.decoder).join();
}

Future<void> drainGet(HttpClient client, Uri uri) async {
  final req = await client.getUrl(uri);
  final res = await req.close();
  await res.drain<void>();
}

List<String> segmentUrlsOf(String indexBody) => indexBody
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.startsWith('http://') && l.contains('/hls/'))
    .toList();

/// 轮询等待条件成立（用于等待异步收尾，避免固定 sleep 造成的假通过）。
Future<void> waitFor(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// 本进程 fd（Linux/Android）或句柄（Windows）数；平台不支持时返回 -1。
///
/// Windows 没有 `/proc`，改用 `Get-Process.HandleCount` 拿句柄数——泄漏 socket
/// 同样会体现在句柄数上，因此这个替代判据在真机上与 fd 等价。
Future<int> currentFd() async {
  if (Platform.isLinux || Platform.isAndroid) {
    try {
      return Directory('/proc/self/fd').listSync().length - 2;
    } catch (_) {
      return -1;
    }
  }
  if (Platform.isWindows) {
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'(Get-Process -Id $pid).HandleCount',
      ]);
      return int.tryParse(r.stdout.toString().trim()) ?? -1;
    } catch (_) {
      return -1;
    }
  }
  return -1;
}

void main() {
  late FakeOrigin origin;
  late HttpClient client;
  late String proxyIndexUrl;
  late List<String> segUrls;

  setUp(() async {
    origin = await startOrigin();
    client = HttpClient();
    final proxyUrl = await LocalMediaHttpServer.instance
        .serveHlsPlaylistOnLoopback(
      'http://127.0.0.1:${origin.port}/playlist.m3u8',
    );
    proxyIndexUrl = proxyUrl!;
    final body = await getText(client, Uri.parse(proxyIndexUrl));
    segUrls = segmentUrlsOf(body);
  });

  tearDown(() async {
    client.close(force: true);
    await LocalMediaHttpServer.instance.dispose();
    await origin.close();
  });

  group('请求收尾率（在途请求必须归零）', () {
    test('混合流量（正常+错误+404）跑完后在途请求归零', () async {
      expect(segUrls.length, 6, reason: '测试前提：索引含 6 个分片');

      final goodUri = Uri.parse(segUrls[4]);
      final badUri = Uri.parse(segUrls.last);
      final port = Uri.parse(proxyIndexUrl).port;
      final missingUri = Uri.parse(
        'http://127.0.0.1:$port/hls/does-not-exist/index.m3u8',
      );

      // 错误分片刻意放末尾（预取窗口外），确保走流式路径而非下载路径。
      //
      // 刻意**并发**而非串行：串行时只要有一个请求悬挂，后续请求全部排队等它，
      // 整个用例会以「超时」失败，掩盖真正的断言结果；并发下悬挂请求无法阻塞
      // 其他请求，断言能如实报出「在途 != 0」。
      for (var batch = 0; batch < 6; batch++) {
        await Future.wait(
          List<Future<void>>.generate(20, (_) async {
            await drainGet(client, goodUri);
            await drainGet(client, badUri);
            await drainGet(client, missingUri);
          }),
        );
      }

      await waitFor(
        () => LocalMediaHttpServer.instance.inFlightRequestCount == 0,
        timeout: const Duration(seconds: 10),
      );
      final settled = LocalMediaHttpServer.instance.inFlightRequestCount;

      expect(
        LocalMediaHttpServer.instance.totalRequestCount,
        greaterThan(100),
        reason: '测试前提：确实产生了足够多的请求',
      );
      expect(
        settled,
        0,
        reason: '有请求未收尾 → 响应未关闭或远端未 drain → 即为 fd 泄漏源',
      );
    }, timeout: const Timeout(Duration(minutes: 2)),);

    test('客户端中途放弃（模拟播放器 seek 断开）后在途请求仍归零', () async {
      // mpv 在 seek/换源时会直接断开分片连接。代理若感知不到断开，会一直卡在
      // 写响应上，请求永不收尾 → 每次 seek 泄漏一个 fd。真机长时间观看频繁
      // seek，与本例同构。
      final goodUri = Uri.parse(segUrls[4]);

      for (var i = 0; i < 30; i++) {
        final req = await client.getUrl(goodUri);
        final res = await req.close();
        // 只读一小段就放弃，不 drain 完。
        final sub = res.listen((_) {}, cancelOnError: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await sub.cancel();
      }

      await waitFor(() => LocalMediaHttpServer.instance.inFlightRequestCount == 0);

      expect(
        LocalMediaHttpServer.instance.inFlightRequestCount,
        0,
        reason: '客户端断开后请求未收尾 → 每次断开泄漏一个 fd',
      );
    }, timeout: const Timeout(Duration(minutes: 2)),);
  });

  group('连接复用（代理到源站不按请求无限建连）', () {
    test('150 次分片请求后源站累计连接数远小于请求数', () async {
      final goodUri = Uri.parse(segUrls[4]);

      // 预热：让会话 HttpClient 先建好连接。
      for (var i = 0; i < 10; i++) {
        await drainGet(client, goodUri);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final before = origin.totalConnections;

      for (var i = 0; i < 150; i++) {
        await drainGet(client, goodUri);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final grown = origin.totalConnections - before;

      expect(
        grown,
        lessThan(150),
        reason: '代理每请求新建一条到源站的连接（$grown/150）→ 连接未复用，'
            '长时间播放会持续累积 socket/fd',
      );
    }, timeout: const Timeout(Duration(minutes: 3)),);

    test('大量请求期间源站活跃连接数保持有界', () async {
      final goodUri = Uri.parse(segUrls[4]);
      for (var i = 0; i < 60; i++) {
        await drainGet(client, goodUri);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(
        origin.activeConnections,
        lessThan(20),
        reason: '源站侧活跃连接数随请求无界增长 → 代理侧连接未归还',
      );
    }, timeout: const Timeout(Duration(minutes: 2)),);
  });

  group('fd / 句柄增长（泄漏的直接证据）', () {
    test('200 次代理请求后本进程 fd（句柄）数不显著增长', () async {
      // 显式 skip 而非静默 return：拿不到证据的平台必须标成 skipped，
      // 不能伪装成通过。
      final fdBefore = await currentFd();
      if (fdBefore < 0) {
        markTestSkipped('本平台无法读取 fd/句柄数（需 Linux/Android 或 Windows）');
        return;
      }

      final goodUri = Uri.parse(segUrls[4]);
      final badUri = Uri.parse(segUrls.last);
      for (var i = 0; i < 100; i++) {
        await drainGet(client, goodUri);
        await drainGet(client, badUri);
      }
      await waitFor(() => LocalMediaHttpServer.instance.inFlightRequestCount == 0);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final fdAfter = await currentFd();
      final grown = fdAfter - fdBefore;
      // ignore: avoid_print
      print('[leak-test] fd/句柄: before=$fdBefore after=$fdAfter '
          'grown=$grown (200 次代理请求)');

      expect(
        grown,
        lessThan(30),
        reason: '200 次请求后 fd 增长 $grown 个（$fdBefore → $fdAfter）→ '
            '本代理就是 fd 泄漏源（真机实测 ~23 个/秒，长播耗尽 fd 会 SIGABRT 闪退）',
      );
    }, timeout: const Timeout(Duration(minutes: 3)),);
  });

  group('注册条目上限（无界缓存回归）', () {
    test('连续注册 30 个 HLS 会话后数量被压到上限', () async {
      for (var i = 0; i < 30; i++) {
        await LocalMediaHttpServer.instance.serveHlsPlaylistOnLoopback(
          'http://127.0.0.1:${origin.port}/playlist.m3u8',
        );
      }
      expect(
        LocalMediaHttpServer.instance.hlsSessionCount,
        lessThanOrEqualTo(8),
        reason: '会话数无上限 → 每个会话一个 HttpClient，fd 随换片无限累积',
      );
    }, timeout: const Timeout(Duration(minutes: 2)),);

    test('连续注册 30 个远程代理后数量被压到上限', () async {
      for (var i = 0; i < 30; i++) {
        await LocalMediaHttpServer.instance.serveRemoteMedia(
          'http://127.0.0.1:${origin.port}/file-$i.mp4',
          useLanIp: false,
        );
      }
      expect(
        LocalMediaHttpServer.instance.remoteProxyCount,
        lessThanOrEqualTo(8),
      );
    }, timeout: const Timeout(Duration(minutes: 2)),);
  });
}
