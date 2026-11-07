import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/local_media_http_server.dart';

/// 本地媒体代理服务器的**端到端**测试。
///
/// 与同目录的 `local_media_http_server_test.dart`（只测纯函数）互补：这里用
/// 真实的 `HttpServer` 假源站 + 真实的 `LocalMediaHttpServer`，走完整链路：
/// 源站 m3u8 → 解析器 → 代理会话 → 播放器拉分片。
///
/// 重点覆盖 **fd 泄漏回归**（SIGABRT 闪退的元凶）：
/// 源站返回非 200 时，代理必须 `drain()` 掉远端响应，否则底层 socket 不归还、
/// fd 持续累积，长播后耗尽 → `epoll_create1` 失败 → abort。
///
/// 判别手法：源站在错误响应里写**大 body**（远超 socket 缓冲），代理若不读，
/// 源站的写入会阻塞/报错 → 记为「未读完」。断言「每次错误请求的 body 都被
/// 完整写出」即等价于「代理每次都 drain 了远端响应」。
class _FakeOrigin {
  _FakeOrigin(this.server);

  final HttpServer server;

  /// 每次错误响应 body 的写出结果：true = 完整写出（客户端读走了），
  /// false = 写入被中断（客户端没读 → 未 drain，fd 泄漏回归）。
  final List<bool> errorWriteOutcomes = <bool>[];

  /// 源站收到的分片请求次数（按路径）。
  final Map<String, int> segmentHits = <String, int>{};

  /// 正常分片内容。
  List<int> okSegment = List<int>.filled(256, 0x42);

  /// 错误分片的状态码。
  int errorStatus = 403;

  /// 错误分片的 body 大小（大到超出 socket 缓冲，用于验证 drain）。
  int errorBodyBytes = 4 * 1024 * 1024;

  int get port => server.port;

  Future<void> close() => server.close(force: true);
}

/// 启动假源站：
/// - /playlist.m3u8 → 分片列表（前面若干正常分片，**最后一个**是错误分片）
/// - /seg_bad.ts    → 非 200 + 大 body
/// - /seg_ok.ts     → 200 + 正常内容
///
/// ⚠️ 错误分片刻意放在**末尾**（默认序号 5）：会话创建时 `prefetchAhead(-1)`
/// 会预取序号 0..3，若错误分片在窗口内，会被「下载路径」抢先取走——那条路径
/// 也做了 drain，会掩盖流式路径（`_tryStreamHlsSegment`）的 drain 缺失，
/// 导致负向验证失真。放在窗口外可保证**只有流式路径**会请求它。
Future<_FakeOrigin> startOrigin({int okSegmentCount = 5}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final origin = _FakeOrigin(server);

  server.listen((req) async {
    final path = req.uri.path;
    try {
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

      if (path.contains('seg_bad')) {
        origin.segmentHits[path] = (origin.segmentHits[path] ?? 0) + 1;
        req.response.statusCode = origin.errorStatus;
        // 大 body：客户端不读则写入阻塞，close() 不完成。
        req.response.add(List<int>.filled(origin.errorBodyBytes, 0x41));
        await req.response.close();
        origin.errorWriteOutcomes.add(true);
        return;
      }

      origin.segmentHits[path] = (origin.segmentHits[path] ?? 0) + 1;
      req.response.add(origin.okSegment);
      await req.response.close();
    } catch (e) {
      // 客户端提前断开（未 drain）→ 写入中断，即 fd 泄漏回归信号。
      origin.errorWriteOutcomes.add(false);
    }
  });

  return origin;
}

/// 把代理返回的 URL 换成回环地址（本机测试用）。
Uri toLoopback(String url) => Uri.parse(url).replace(host: '127.0.0.1');

/// 发起 GET 并返回响应。
Future<HttpClientResponse> get(HttpClient client, Uri uri) async {
  final req = await client.getUrl(uri);
  return req.close();
}

/// 发起 GET 并读取文本 body。
Future<String> getText(HttpClient client, Uri uri) async {
  final res = await get(client, uri);
  return res.transform(utf8.decoder).join();
}

/// 从代理索引里取出分片 URL 列表（按序号）。
List<String> segmentUrlsOf(String indexBody) => indexBody
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.startsWith('http://') && l.contains('/hls/'))
    .toList();

void main() {
  late _FakeOrigin origin;
  late HttpClient client;

  setUp(() async {
    origin = await startOrigin();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await LocalMediaHttpServer.instance.dispose();
    await origin.close();
  });

  group('HLS 代理端到端 - 正常路径', () {
    test('代理索引返回 200，且含分片地址与 EXTINF', () async {
      final proxyUrl = await LocalMediaHttpServer.instance
          .serveHlsPlaylistOnLoopback(
        'http://127.0.0.1:${origin.port}/playlist.m3u8',
      );
      expect(proxyUrl, isNotNull);
      expect(proxyUrl, contains('/hls/'));
      expect(proxyUrl, contains('index.m3u8'));

      final body = await getText(client, toLoopback(proxyUrl!));

      expect(body, contains('#EXTM3U'));
      expect(body, contains('#EXT-X-ENDLIST'));
      expect(body, contains('/hls/'));
      expect(body, contains('#EXTINF:'));
      expect(segmentUrlsOf(body).length, 6);
    });

    test('代理分片返回 200 且内容与源站一致', () async {
      final proxyUrl = await LocalMediaHttpServer.instance
          .serveHlsPlaylistOnLoopback(
        'http://127.0.0.1:${origin.port}/playlist.m3u8',
      );
      final indexBody = await getText(client, toLoopback(proxyUrl!));
      final urls = segmentUrlsOf(indexBody);
      expect(urls.length, 6);

      // 序号 4：正常分片，且在预取窗口(0..3)之外 → 必定走流式路径
      final res = await get(client, Uri.parse(urls[4]));
      final bytes = await res.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );

      expect(res.statusCode, 200);
      expect(bytes.length, origin.okSegment.length);
      expect(bytes.first, origin.okSegment.first);
    });

    test('代理地址使用回环 127.0.0.1（本机播放必须走回环）', () async {
      final proxyUrl = await LocalMediaHttpServer.instance
          .serveHlsPlaylistOnLoopback(
        'http://127.0.0.1:${origin.port}/playlist.m3u8',
      );
      expect(Uri.parse(proxyUrl!).host, '127.0.0.1');
    });
  });

  group('HLS 代理端到端 - fd 泄漏回归（源站非 200）', () {
    test('源站 403：代理透传 403', () async {
      final proxyUrl = await LocalMediaHttpServer.instance
          .serveHlsPlaylistOnLoopback(
        'http://127.0.0.1:${origin.port}/playlist.m3u8',
      );
      final indexBody = await getText(client, toLoopback(proxyUrl!));
      final badUrl = segmentUrlsOf(indexBody).last;

      final res = await get(client, Uri.parse(badUrl));
      await res.drain<void>();
      expect(res.statusCode, 403);
    });

    test('源站 403：远端响应体被完整读走（drain 生效，未泄漏 socket）', () async {
      final proxyUrl = await LocalMediaHttpServer.instance
          .serveHlsPlaylistOnLoopback(
        'http://127.0.0.1:${origin.port}/playlist.m3u8',
      );
      final indexBody = await getText(client, toLoopback(proxyUrl!));
      final badUrl = segmentUrlsOf(indexBody).last;

      final res = await get(client, Uri.parse(badUrl));
      await res.drain<void>();

      // 等源站把 4MB body 写完（写完 = 客户端确实读了它）
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (origin.errorWriteOutcomes.isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        origin.errorWriteOutcomes,
        isNotEmpty,
        reason: '源站未收到错误分片请求，测试前提不成立',
      );
      expect(
        origin.errorWriteOutcomes.every((ok) => ok),
        isTrue,
        reason: '远端错误响应体未被完整读走 → 代理漏了 drain '
            '(fd 泄漏回归，长播耗尽 fd 会 SIGABRT 闪退)',
      );
    });

    test('源站 404：代理透传 404', () async {
      origin.errorStatus = 404;
      final proxyUrl = await LocalMediaHttpServer.instance
          .serveHlsPlaylistOnLoopback(
        'http://127.0.0.1:${origin.port}/playlist.m3u8',
      );
      final indexBody = await getText(client, toLoopback(proxyUrl!));
      final badUrl = segmentUrlsOf(indexBody).last;

      final res = await get(client, Uri.parse(badUrl));
      await res.drain<void>();
      expect(res.statusCode, 404);
    });
  });

  group('HLS 代理端到端 - 健壮性', () {
    test('未知 token 返回 404', () async {
      final proxyUrl = await LocalMediaHttpServer.instance
          .serveHlsPlaylistOnLoopback(
        'http://127.0.0.1:${origin.port}/playlist.m3u8',
      );
      final port = Uri.parse(proxyUrl!).port;
      final res = await get(
        client,
        Uri.parse('http://127.0.0.1:$port/hls/nonexistent/index.m3u8'),
      );
      await res.drain<void>();
      expect(res.statusCode, 404);
    });

    test('分片序号越界返回 404', () async {
      final proxyUrl = await LocalMediaHttpServer.instance
          .serveHlsPlaylistOnLoopback(
        'http://127.0.0.1:${origin.port}/playlist.m3u8',
      );
      final parsed = Uri.parse(proxyUrl!);
      final token = parsed.pathSegments[1];
      final res = await get(
        client,
        Uri.parse('http://127.0.0.1:${parsed.port}/hls/$token/9999'),
      );
      await res.drain<void>();
      expect(res.statusCode, 404);
    });

    test('HEAD 请求索引返回 200 且无 body', () async {
      final proxyUrl = await LocalMediaHttpServer.instance
          .serveHlsPlaylistOnLoopback(
        'http://127.0.0.1:${origin.port}/playlist.m3u8',
      );
      final req = await client.headUrl(toLoopback(proxyUrl!));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      expect(res.statusCode, 200);
      expect(body, isEmpty);
    });
  });

  group('代理会话 LRU 上限（防长时间会话资源无限累积）', () {
    test('注册 12 个远程代理后数量被压到上限 8', () async {
      for (var i = 0; i < 12; i++) {
        await LocalMediaHttpServer.instance.serveRemoteMedia(
          'http://127.0.0.1:${origin.port}/file-$i.mp4',
          useLanIp: false,
        );
      }
      expect(
        LocalMediaHttpServer.instance.remoteProxyCount,
        lessThanOrEqualTo(8),
      );
    });

    test('注册 12 个 HLS 会话后数量被压到上限 8', () async {
      for (var i = 0; i < 12; i++) {
        await LocalMediaHttpServer.instance.serveHlsPlaylistOnLoopback(
          'http://127.0.0.1:${origin.port}/playlist.m3u8',
        );
      }
      expect(
        LocalMediaHttpServer.instance.hlsSessionCount,
        lessThanOrEqualTo(8),
      );
    });
  });

  group('远程媒体代理（投屏直链）', () {
    test('200 响应：状态与内容透传', () async {
      final proxyUrl = await LocalMediaHttpServer.instance
          .serveRemoteMedia(
            'http://127.0.0.1:${origin.port}/seg_ok.ts',
            useLanIp: false,
          );
      expect(proxyUrl, contains('/proxy/'));

      final res = await get(client, toLoopback(proxyUrl!));
      final bytes = await res.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      expect(res.statusCode, 200);
      expect(bytes.length, origin.okSegment.length);
    });

    test('源站错误：状态码透传给客户端，不挂死', () async {
      origin.errorStatus = 403;
      final proxyUrl = await LocalMediaHttpServer.instance
          .serveRemoteMedia(
            'http://127.0.0.1:${origin.port}/seg_bad.ts',
            useLanIp: false,
          );
      final res = await get(client, toLoopback(proxyUrl!));
      await res.drain<void>();
      expect(res.statusCode, 403);
    });

    test('未知 token 返回 404', () async {
      final proxyUrl = await LocalMediaHttpServer.instance
          .serveRemoteMedia(
            'http://127.0.0.1:${origin.port}/seg_ok.ts',
            useLanIp: false,
          );
      final port = Uri.parse(proxyUrl!).port;
      final res = await get(
        client,
        Uri.parse('http://127.0.0.1:$port/proxy/nonexistent'),
      );
      await res.drain<void>();
      expect(res.statusCode, 404);
    });
  });
}
