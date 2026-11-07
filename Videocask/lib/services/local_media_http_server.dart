import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/lan_address.dart';
import 'hls_ad_filter.dart';
import 'hls_segment_crypto.dart';
import 'media_fetch_headers.dart';
import 'm3u8_playlist_resolver.dart';
import 'proxy_eviction.dart';
import 'debug_log.dart';

/// Parses `#EXTINF` durations from an m3u8 media playlist.
List<double> parseM3u8ExtinfDurations(String content) {
  final durations = <double>[];
  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('#EXTINF:')) continue;
    final payload = trimmed.substring('#EXTINF:'.length);
    final value = payload.split(',').first.trim();
    durations.add(double.tryParse(value) ?? 10.0);
  }
  return durations;
}

List<double> normalizeM3u8SegmentDurations(
  List<double> raw,
  int segmentCount,
) {
  if (segmentCount <= 0) return const [];
  if (raw.length >= segmentCount) {
    return raw.take(segmentCount).toList(growable: false);
  }
  return [
    ...raw,
    ...List<double>.filled(segmentCount - raw.length, 10.0),
  ];
}

/// 将本地文件或远程 HLS/媒体流，暴露为局域网 HTTP URL（DLNA 电视可拉取）。
class LocalMediaHttpServer {
  LocalMediaHttpServer._();
  static final LocalMediaHttpServer instance = LocalMediaHttpServer._();

  HttpServer? _server;
  int? _port;
  String? _cachedLanIp;
  final Map<String, _ServedFile> _files = {};
  final Map<String, _RemoteMediaProxy> _remoteProxies = {};
  final Map<String, _HlsProxySession> _hlsSessions = {};
  final Map<String, _AdFreePlaylist> _adFreePlaylists = {};
  int _tokenSeq = 0;

  // ===== FD 泄漏定位用诊断计数器（只加日志，不改业务行为）=====
  // 背景：真机曾出现 fd 以 ~23 个/秒单调增长至 3 万+ 直至 SIGABRT，而播放器回收
  // 兜底未能回收，怀疑泄漏点不在 Player 而在本代理的连接。这里用「在途请求数」
  // 来证明或否证：若请求都正常收尾，在途应维持在个位数。
  int _reqTotal = 0;
  int _reqInFlight = 0;
  static const int _reqLogEvery = 50;

  /// 打印本代理的连接/会话快照，与 [Play] 心跳里的 fd 数对照即可定位泄漏归属。
  void _logConnectionSnapshot() {
    DebugLog.log(
      'Proxy',
      '快照: 请求累计=$_reqTotal 在途=$_reqInFlight '
          'hls会话=${_hlsSessions.length} 去广告列表=${_adFreePlaylists.length} '
          '远程代理=${_remoteProxies.length} 本地文件=${_files.length} '
          'fd=${_fdCountForDiag()}',
      flush: true,
    );
  }

  /// 仅供诊断：读取本进程 fd 数（web 不支持，返回 -1）。
  int _fdCountForDiag() {
    if (kIsWeb) return -1;
    try {
      return Directory('/proc/self/fd').listSync().length - 2;
    } catch (_) {
      return -1;
    }
  }

  /// 幂等守卫：dispose 可能被应用退出路径与测试析构多次调用。
  bool _released = false;

  final M3u8PlaylistResolver _playlistResolver = M3u8PlaylistResolver();

  /// 把本地文件暴露为 HTTP URL。
  ///
  /// [useLanIp] = true（默认）返回局域网地址，供电视等**外部设备**访问；
  /// false 时返回回环地址 127.0.0.1，供**本机**访问（局域网 IP 在安卓 Wi-Fi
  /// 客户端隔离下访问本机不稳定，会导致间歇失败）。
  Future<String?> serveFilePath(String filePath, {bool useLanIp = true}) async {
    if (kIsWeb) return null;
    final file = File(filePath);
    if (!await file.exists()) return null;
    await _ensureStarted();
    final port = _port;
    if (port == null) return null;
    final host = useLanIp ? await _lanIp() : '127.0.0.1';
    if (host == null) return null;

    final token = 'f${++_tokenSeq}';
    _files[token] = _ServedFile(
      file: file,
      contentType: _mimeForPath(filePath),
    );
    _evictServedFiles();
    return 'http://$host:$port/media/$token';
  }

  /// 远程 MP4 等直链：由手机代拉（带 Referer），电视访问局域网地址。
  ///
  /// [useLanIp] = true（默认）返回局域网地址供外部设备访问；false 时返回回环
  /// 地址 127.0.0.1，供**本机**播放使用（部分源有防盗链，直连会被 403，
  /// 经本机代理带上 Referer 才能正常拉取）。
  Future<String?> serveRemoteMedia(
    String mediaUrl, {
    bool useLanIp = true,
  }) async {
    if (kIsWeb) return null;
    final trimmed = mediaUrl.trim();
    if (trimmed.isEmpty) return null;
    await _ensureStarted();
    final port = _port;
    if (port == null) return null;
    final host = useLanIp ? await _lanIp() : '127.0.0.1';
    if (host == null) return null;

    final token = 'r${++_tokenSeq}';
    _remoteProxies[token] = _RemoteMediaProxy(
      url: trimmed,
      headers: MediaFetchHeaders.forUrl(trimmed),
      contentType: _mimeForPath(trimmed),
    );
    _evictRemoteProxies();
    return 'http://$host:$port/proxy/$token';
  }

  /// HLS：手机代理 m3u8 + 分片（解决电视无法访问 CDN / 不支持 HLS 直链）。
  ///
  /// 分片列表已由 [M3u8PlaylistResolver] 剔除广告分片。
  Future<String?> serveHlsPlaylist(String playlistUrl) async {
    if (kIsWeb) return null;
    final trimmed = playlistUrl.trim();
    if (trimmed.isEmpty) return null;
    try {
      final playlist = await _playlistResolver.resolve(trimmed);
      // 投屏到电视等外部设备：必须用局域网地址供电视访问本机代理。
      return _serveHlsProxyForPlaylist(playlist, useLanIp: true);
    } catch (e) {
      debugPrint('serveHlsPlaylist failed: $e');
      return null;
    }
  }

  /// 本机播放用的 HLS 代理入口（回环地址 127.0.0.1）。
  ///
  /// 与 [serveHlsPlaylist] 的区别是**主机地址**：
  /// - [serveHlsPlaylist] 固定用局域网 IP，供电视等**外部设备**访问本机代理；
  /// - 本方法用回环地址，供**本机**播放器访问。局域网 IP（192.168.x.x）在安卓
  ///   Wi-Fi 客户端隔离/路由下访问本机不稳定，会导致分片拉取间歇失败、
  ///   libmpv 原生崩溃（表现为随机闪退），因此本机播放必须走回环。
  ///
  /// 同样返回 `http://127.0.0.1:<port>/hls/<token>/index.m3u8`。
  Future<String?> serveHlsPlaylistOnLoopback(String playlistUrl) async {
    if (kIsWeb) return null;
    final trimmed = playlistUrl.trim();
    if (trimmed.isEmpty) return null;
    try {
      final playlist = await _playlistResolver.resolve(trimmed);
      return _serveHlsProxyForPlaylist(playlist);
    } catch (e) {
      debugPrint('serveHlsPlaylistOnLoopback failed: $e');
      return null;
    }
  }

  /// 诊断：当前 HLS 代理会话数量（上限 [_maxHlsSessions]，超出即淘汰最旧）。
  /// 供自动化测试断言 LRU 上限生效，也便于排查长时间会话的资源增长。
  int get hlsSessionCount => _hlsSessions.length;

  /// 诊断：当前远程代理数量（上限 [_maxRemoteProxies]，超出即淘汰最旧）。
  int get remoteProxyCount => _remoteProxies.length;

  /// 诊断：当前静态去广告播放列表数量（上限 [_maxAdFreePlaylists]）。
  int get adFreePlaylistCount => _adFreePlaylists.length;

  /// 诊断：当前**在途**请求数（已进入 `_handleRequest` 但尚未收尾）。
  ///
  /// fd 泄漏归属判定用：请求正常收尾时该值应回落到 0；若持续爬升，说明有请求
  /// 没走完（远端响应未 drain / 本地响应未 close / 客户端断开未被感知），
  /// 那么 fd 泄漏就在本代理；若始终为个位数，则本代理清白、泄漏在别处。
  int get inFlightRequestCount => _reqInFlight;

  /// 诊断：累计处理过的请求总数（与 [inFlightRequestCount] 对照看收尾率）。
  int get totalRequestCount => _reqTotal;

  /// 诊断：本进程当前打开的 fd 数（web 或无 /proc 时返回 -1）。
  int get debugFdCount => _fdCountForDiag();

  /// 在线播放去广告：把远端 m3u8 换成本地地址。
  ///
  /// - 未发现广告分片 → 返回 null（调用方直接使用原始地址，零开销）；
  /// - 发现广告且未加密 → 本地仅代理一份过滤后的播放列表，分片仍由
  ///   播放器直连 CDN（与原行为一致，不增加转发开销）；
  /// - 发现广告且 AES-128 加密 → 走全量本地代理（分片需按原始序号解密）。
  Future<String?> serveAdFreeHls(String playlistUrl) async {
    if (kIsWeb) return null;
    final trimmed = playlistUrl.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return null;
    }
    try {
      final playlist = await _playlistResolver.resolve(trimmed);
      if (playlist.segmentUrls.isEmpty || !playlist.hasAdRemoved) {
        DebugLog.log('Proxy', '去广告: 无广告或列表为空，直连原始地址');
        return null;
      }
      if (playlist.isEncrypted) {
        final proxied = await _serveHlsProxyForPlaylist(playlist);
        if (proxied != null && proxied.isNotEmpty) {
          debugPrint(
            'HLS 去广告(加密流全量代理): $trimmed -> $proxied '
            '(剔除 ${playlist.removedAdSegments} 片/'
            '${playlist.removedAdSeconds.toStringAsFixed(1)}s)',
          );
          DebugLog.log(
            'Proxy',
            '去广告(全量加密代理) url=$trimmed -> $proxied '
                '剔除 ${playlist.removedAdSegments}片/'
                '${playlist.removedAdSeconds.toStringAsFixed(1)}s',
          );
          return proxied;
        }
        return null;
      }

      final adFilter = playlist.adFilter;
      final rewritten =
          adFilter == null ? null : buildAdFreePlaylistContent(adFilter);
      if (rewritten == null || rewritten.isEmpty) {
        return null;
      }

      await _ensureStarted();
      final port = _port;
      if (port == null) return null;

      final token = 'a${++_tokenSeq}';
      _adFreePlaylists[token] = _AdFreePlaylist(content: rewritten);
      _evictAdFreePlaylists();
      debugPrint(
        'HLS 去广告(列表代理): $trimmed -> http://127.0.0.1:$port/adfree/$token/index.m3u8 '
        '(剔除 ${playlist.removedAdSegments} 片/'
        '${playlist.removedAdSeconds.toStringAsFixed(1)}s)',
      );
      DebugLog.log(
        'Proxy',
        '去广告(列表代理) url=$trimmed -> token=a$token '
            '剔除 ${playlist.removedAdSegments}片/'
            '${playlist.removedAdSeconds.toStringAsFixed(1)}s',
      );
      return 'http://127.0.0.1:$port/adfree/$token/index.m3u8';
    } catch (e) {
      debugPrint('serveAdFreeHls failed: $e');
      return null;
    }
  }

  /// 静态去广告播放列表数量上限（超出淘汰最旧的，防长时间会话内存增长）。
  static const _maxAdFreePlaylists = 8;

  /// 本地文件服务条目数量上限。
  ///
  /// `_files` 的 key 单调递增（`f1`/`f2`…），条目持有 `File` 引用；不设上限
  /// 会随换片/换源无限增长，是典型的无界缓存。
  static const _maxServedFiles = 32;

  void _evictServedFiles() {
    // 只摘引用即可：`_ServedFile.file` 未持有独立 OS 句柄（读取走 openRead 流，
    // 由管道自己关闭）。在途请求持有本地引用，淘汰不影响其继续传输。
    evictOldest(_files, _maxServedFiles);
  }

  void _evictAdFreePlaylists() {
    while (_adFreePlaylists.length > _maxAdFreePlaylists) {
      _adFreePlaylists.remove(_adFreePlaylists.keys.first);
    }
  }

  /// 代理会话/远程代理数量上限（超出淘汰最旧的，防长时间会话 fd/HttpClient 无限累积）。
  static const _maxHlsSessions = 8;
  static const _maxRemoteProxies = 8;

  void _evictHlsSessions() {
    for (final entry in evictOldest(_hlsSessions, _maxHlsSessions)) {
      unawaited(entry.value.close());
    }
  }

  void _evictRemoteProxies() {
    for (final entry in evictOldest(_remoteProxies, _maxRemoteProxies)) {
      entry.value.httpClient.close(force: true);
    }
  }

  /// [useLanIp] = true 时返回局域网地址（投屏到电视等外部设备访问本机代理）；
  /// 默认 false 用回环地址 127.0.0.1（本机播放）。
  ///
  /// 本机播放必须用回环地址：局域网 IP（192.168.x.x）在安卓 Wi-Fi 客户端隔离/
  /// 路由下对「本机网卡 IP」的访问不稳定，会导致分片拉取间歇失败、libmpv 原生
  /// 崩溃（表现为随机闪退）。投屏场景由外部设备访问，才需要局域网地址。
  Future<String?> _serveHlsProxyForPlaylist(
    M3u8MediaPlaylist playlist, {
    bool useLanIp = false,
  }) async {
    if (kIsWeb) return null;
    if (playlist.segmentUrls.isEmpty) return null;
    await _ensureStarted();
    final port = _port;
    if (port == null) return null;

    final String host;
    if (useLanIp) {
      final lan = await _lanIp();
      if (lan == null) return null;
      host = lan;
    } else {
      host = '127.0.0.1';
    }

    final token = 'h${++_tokenSeq}';
    final session = _HlsProxySession(
      playlistUrl: playlist.playlistUrl,
      segmentUrls: playlist.segmentUrls,
      segmentDurations: playlist.segmentDurations,
      segmentSourceIndices: playlist.segmentSourceIndices,
      headers: MediaFetchHeaders.forUrl(playlist.playlistUrl),
      aes128Key: playlist.aes128Key,
      aesKeyBytes: playlist.aes128Key == null
          ? null
          : await HlsSegmentCrypto.loadKeyBytes(
              playlist.aes128Key!,
              headers: MediaFetchHeaders.forUrl(playlist.aes128Key!.uri),
            ),
    );
    _hlsSessions[token] = session;
    session.prefetchAhead(-1);
    _evictHlsSessions();
    return 'http://$host:$port/hls/$token/index.m3u8';
  }

  Future<String?> _lanIp() async {
    _cachedLanIp ??= await LanAddress.preferredIPv4();
    return _cachedLanIp;
  }

  Future<void> _ensureStarted() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _port = _server!.port;
    unawaited(_server!.listen(_handleRequest).asFuture());
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _reqTotal++;
    _reqInFlight++;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      final segments = request.uri.pathSegments;
      if (segments.isEmpty) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      switch (segments.first) {
        case 'media':
          if (segments.length != 2) break;
          await _serveLocalFile(request, segments[1]);
          return;
        case 'proxy':
          if (segments.length != 2) break;
          await _serveRemoteProxy(request, segments[1]);
          return;
        case 'hls':
          if (segments.length == 3 && segments[2] == 'index.m3u8') {
            await _serveHlsIndex(request, segments[1]);
            return;
          }
          if (segments.length == 3) {
            final index = int.tryParse(segments[2]);
            if (index != null) {
              await _serveHlsSegment(request, segments[1], index);
              return;
            }
          }
        case 'adfree':
          if (segments.length == 3 && segments[2] == 'index.m3u8') {
            await _serveAdFreeIndex(request, segments[1]);
            return;
          }
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (e) {
      debugPrint('LocalMediaHttpServer request failed: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    } finally {
      _reqInFlight--;
      // 每 _reqLogEvery 个请求打一次快照：若在途请求持续爬升，说明有请求没走完
      // （响应未关闭 / 远端响应未 drain），即为 fd 泄漏来源；若始终为个位数，
      // 则本代理清白，泄漏在别处（播放器 / 引擎）。
      if (_reqTotal % _reqLogEvery == 0) {
        _logConnectionSnapshot();
      }
    }
  }

  Future<void> _serveLocalFile(HttpRequest request, String token) async {
    final entry = _files[token];
    if (entry == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    await _pipeFileWithRange(request, entry.file, entry.contentType);
  }

  Future<void> _serveRemoteProxy(HttpRequest request, String token) async {
    final entry = _remoteProxies[token];
    if (entry == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    await _pipeRemoteWithRange(
      request,
      entry.url,
      entry.headers,
      entry.contentType,
      entry.httpClient,
    );
  }

  Future<void> _serveHlsIndex(HttpRequest request, String token) async {
    final session = _hlsSessions[token];
    if (session == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final port = _port!;

    final targetDuration = session.segmentDurations.isEmpty
        ? 10
        : session.segmentDurations
            .reduce((a, b) => a > b ? a : b)
            .ceil()
            .clamp(1, 999);

    final buffer = StringBuffer(
      '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:$targetDuration\n'
      '#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n',
    );
    // 分片 URL 沿用请求到达时的 host（本机播放→127.0.0.1，投屏→局域网 IP），
    // 保证与索引同域，避免硬编码单一地址在任一种场景下拉不到分片。
    final authority = request.requestedUri.authority;
    final segmentHost = authority.isNotEmpty ? authority : '127.0.0.1:$port';
    for (var i = 0; i < session.segmentUrls.length; i++) {
      final duration = i < session.segmentDurations.length
          ? session.segmentDurations[i]
          : 10.0;
      buffer.writeln('#EXTINF:${duration.toStringAsFixed(3)},');
      buffer.writeln('http://$segmentHost/hls/$token/$i');
    }
    buffer.writeln('#EXT-X-ENDLIST');

    final body = utf8.encode(buffer.toString());
    request.response.headers
        .set('Content-Type', 'application/vnd.apple.mpegurl');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.contentLength = body.length;
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }
    request.response.add(body);
    await request.response.close();
  }

  /// 输出静态去广告播放列表（分片地址仍指向原 CDN，由播放器直连）。
  Future<void> _serveAdFreeIndex(HttpRequest request, String token) async {
    final entry = _adFreePlaylists[token];
    if (entry == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final body = utf8.encode(entry.content);
    request.response.headers.set(
      'Content-Type',
      'application/vnd.apple.mpegurl',
    );
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.contentLength = body.length;
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }
    request.response.add(body);
    await request.response.close();
  }

  Future<void> _serveHlsSegment(
    HttpRequest request,
    String token,
    int index,
  ) async {
    final session = _hlsSessions[token];
    if (session == null || index < 0 || index >= session.segmentUrls.length) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    session.prefetchAhead(index);

    final cached = session.cachedSegment(index);
    if (cached != null) {
      await _writeSegmentPayload(request, cached);
      return;
    }

    if (!session.isEncrypted) {
      final streamed = await _tryStreamHlsSegment(request, session, index);
      if (streamed) return;
    }

    try {
      final payload = await session.loadSegment(index);
      await _writeSegmentPayload(request, payload);
    } catch (e) {
      debugPrint('HLS segment $index failed: $e');
      DebugLog.log('Proxy', '分片加载失败 index=$index err=$e', flush: true);
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
    }
  }

  Future<bool> _tryStreamHlsSegment(
    HttpRequest request,
    _HlsProxySession session,
    int index,
  ) async {
    HttpClientResponse? res;
    try {
      final req = await session.httpClient.getUrl(
        Uri.parse(session.segmentUrls[index]),
      );
      _applyRequestHeaders(req, session.headers);
      final r = await req.close();
      res = r;
      if (r.statusCode != HttpStatus.ok) {
        request.response.statusCode = r.statusCode;
        // 远端响应必须 drain，否则底层 socket 不归还连接池 → fd 泄漏；
        // 长播中遇 CDN 限流/临时错误会反复累积，最终耗尽 → SIGABRT。
        try {
          await r.drain();
        } catch (_) {}
        await request.response.close();
        return true;
      }

      request.response.headers.set('Content-Type', 'video/mp2t');
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.headers.set('Accept-Ranges', 'none');
      final length = r.contentLength;
      if (length >= 0) {
        request.response.contentLength = length;
      }
      if (request.method == 'HEAD') {
        await request.response.close();
        return true;
      }
      await request.response.addStream(r);
      await request.response.close();
      return true;
    } catch (e) {
      // 客户端中途断开（快进/切集）时 addStream 可能抛异常，必须 drain 释放底层
      // socket，否则该 fd 长期残留，长时间播放后累积耗尽 → SIGABRT。
      try {
        await res?.drain();
      } catch (_) {}
      try {
        await request.response.close();
      } catch (_) {}
      debugPrint('HLS segment stream $index failed, fallback to cache: $e');
      return false;
    }
  }

  Future<void> _writeSegmentPayload(
    HttpRequest request,
    Uint8List payload,
  ) async {
    request.response.headers.set('Content-Type', 'video/mp2t');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.contentLength = payload.length;
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }
    request.response.add(payload);
    await request.response.close();
  }

  Future<void> _pipeFileWithRange(
    HttpRequest request,
    File file,
    String contentType,
  ) async {
    final total = await file.length();
    request.response.headers.set('Accept-Ranges', 'bytes');
    request.response.headers.set('Content-Type', contentType);
    request.response.headers.set('Access-Control-Allow-Origin', '*');

    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null && range.startsWith('bytes=')) {
      final part = range.substring(6);
      final dash = part.indexOf('-');
      if (dash >= 0) {
        final start = int.tryParse(part.substring(0, dash)) ?? 0;
        final endRaw = part.substring(dash + 1);
        final end =
            endRaw.isEmpty ? total - 1 : int.tryParse(endRaw) ?? (total - 1);
        final safeEnd = end.clamp(0, total - 1);
        final safeStart = start.clamp(0, safeEnd);
        final length = safeEnd - safeStart + 1;
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $safeStart-$safeEnd/$total',
        );
        request.response.contentLength = length;
        if (request.method == 'HEAD') {
          await request.response.close();
          return;
        }
        await request.response.addStream(
          file.openRead(safeStart, safeEnd + 1),
        );
        await request.response.close();
        return;
      }
    }

    request.response.contentLength = total;
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  Future<void> _pipeRemoteWithRange(
    HttpRequest request,
    String url,
    Map<String, String> headers,
    String contentType,
    HttpClient client,
  ) async {
    HttpClientResponse? res;
    try {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final req = await client.getUrl(Uri.parse(url));
      _applyRequestHeaders(req, headers);
      if (range != null) {
        req.headers.set(HttpHeaders.rangeHeader, range);
      }
      res = await req.close();
      request.response.statusCode = res.statusCode;
      var hasContentType = false;
      res.headers.forEach((name, values) {
        if (name.toLowerCase() == HttpHeaders.transferEncodingHeader) return;
        if (name.toLowerCase() == HttpHeaders.contentTypeHeader) {
          hasContentType = true;
        }
        for (final value in values) {
          request.response.headers.add(name, value);
        }
      });
      if (!hasContentType) {
        request.response.headers.set('Content-Type', contentType);
      }
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      if (request.method == 'HEAD') {
        await request.response.close();
        return;
      }
      await request.response.addStream(res);
      await request.response.close();
    } catch (e) {
      debugPrint('Remote proxy failed: $e');
      // 异常分支：远端响应（若有）必须 drain，否则底层 socket 残留 → fd 泄漏。
      try {
        await res?.drain();
      } catch (_) {}
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {}
    }
  }

  static void _applyRequestHeaders(
    HttpClientRequest req,
    Map<String, String> headers,
  ) {
    for (final entry in headers.entries) {
      req.headers.set(entry.key, entry.value);
    }
  }

  static String _mimeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('.m3u8')) return 'application/vnd.apple.mpegurl';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.ts')) return 'video/mp2t';
    return 'application/octet-stream';
  }

  Future<void> dispose() async {
    // 幂等：单例可能被应用退出路径与测试析构多次调用；
    // 二次 close 会话/服务端存在抛 StateError 的风险。
    if (_released) return;
    _released = true;
    _files.clear();
    for (final proxy in _remoteProxies.values) {
      proxy.httpClient.close(force: true);
    }
    _remoteProxies.clear();
    for (final session in _hlsSessions.values) {
      await session.close();
    }
    _hlsSessions.clear();
    _adFreePlaylists.clear();
    _cachedLanIp = null;
    await _server?.close(force: true);
    _server = null;
    _port = null;
  }
}

class _ServedFile {
  _ServedFile({required this.file, required this.contentType});

  final File file;
  final String contentType;
}

/// 静态去广告播放列表条目。
class _AdFreePlaylist {
  _AdFreePlaylist({required this.content});

  final String content;
}

class _RemoteMediaProxy {
  _RemoteMediaProxy({
    required this.url,
    required this.headers,
    required this.contentType,
  }) : httpClient = HttpClient()
          ..connectionTimeout = const Duration(seconds: 20)
          ..idleTimeout = const Duration(seconds: 60);

  final String url;
  final Map<String, String> headers;
  final String contentType;
  final HttpClient httpClient;
}

class _HlsProxySession {
  _HlsProxySession({
    required this.playlistUrl,
    required this.segmentUrls,
    required this.segmentDurations,
    required this.segmentSourceIndices,
    required this.headers,
    this.aes128Key,
    this.aesKeyBytes,
  }) : httpClient = HttpClient()
          ..connectionTimeout = const Duration(seconds: 20)
          ..idleTimeout = const Duration(seconds: 60);

  static const _maxCachedSegments = 16;
  static const _prefetchAheadCount = 4;

  final String playlistUrl;

  /// 已剔除广告分片后的分片地址（与 [segmentDurations] / [segmentSourceIndices] 对齐）。
  final List<String> segmentUrls;
  final List<double> segmentDurations;

  /// 与 [segmentUrls] 对齐的原始分片序号（AES-128 隐式 IV 依赖）。
  final List<int> segmentSourceIndices;

  final Map<String, String> headers;
  final M3u8Aes128Key? aes128Key;
  final Uint8List? aesKeyBytes;
  final HttpClient httpClient;

  final Map<int, Uint8List> _cache = {};
  final Map<int, Future<Uint8List>> _loading = {};

  bool get isEncrypted => aesKeyBytes != null;

  Uint8List? cachedSegment(int index) => _cache[index];

  /// 分片在原始列表中的序号（无过滤时即自身下标）。
  int sourceIndexFor(int index) {
    if (index >= 0 && index < segmentSourceIndices.length) {
      return segmentSourceIndices[index];
    }
    return index;
  }

  void prefetchAhead(int currentIndex) {
    for (var offset = 1; offset <= _prefetchAheadCount; offset++) {
      final index = currentIndex + offset;
      if (index < 0 || index >= segmentUrls.length) continue;
      if (_cache.containsKey(index) || _loading.containsKey(index)) continue;
      unawaited(loadSegment(index).catchError((_, __) => Uint8List(0)));
    }
  }

  Future<Uint8List> loadSegment(int index) async {
    final cached = _cache[index];
    if (cached != null) return cached;

    final inFlight = _loading[index];
    if (inFlight != null) return inFlight;

    final future = _downloadSegment(index);
    _loading[index] = future;
    try {
      final bytes = await future;
      _cache[index] = bytes;
      _trimCache(index);
      return bytes;
    } finally {
      _dropLoading(index);
    }
  }

  void _dropLoading(int index) {
    _loading.remove(index);
  }

  Future<Uint8List> _downloadSegment(int index) async {
    final req = await httpClient.getUrl(Uri.parse(segmentUrls[index]));
    LocalMediaHttpServer._applyRequestHeaders(req, headers);
    final res = await req.close();
    if (res.statusCode != HttpStatus.ok) {
      // 先 drain 释放底层 socket，否则该响应占用一个 fd 泄漏。
      try {
        await res.drain();
      } catch (_) {}
      DebugLog.log(
        'Proxy',
        '分片下载 HTTP 异常 index=$index '
        'sourceIndex=${sourceIndexFor(index)} code=${res.statusCode}',
        flush: true,
      );
      throw HttpException('Segment $index HTTP ${res.statusCode}');
    }
    final bytes = await consolidateHttpClientResponseBytes(res);
    if (aesKeyBytes == null) return bytes;
    // AES-128 隐式 IV 由分片在原始列表中的序号推导，必须用原始序号解密。
    return HlsSegmentCrypto.decryptSegment(
      encrypted: bytes,
      keyBytes: aesKeyBytes!,
      segmentIndex: sourceIndexFor(index),
      ivHex: aes128Key?.ivHex,
    );
  }

  void _trimCache(int keepNearIndex) {
    if (_cache.length <= _maxCachedSegments) return;
    final keys = _cache.keys.toList()..sort();
    for (final key in keys) {
      if ((key - keepNearIndex).abs() > _maxCachedSegments) {
        _cache.remove(key);
      }
      if (_cache.length <= _maxCachedSegments) break;
    }
  }

  Future<void> close() async {
    httpClient.close(force: true);
    _cache.clear();
    _loading.clear();
  }
}
