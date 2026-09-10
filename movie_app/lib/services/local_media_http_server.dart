import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/lan_address.dart';
import 'hls_ad_filter.dart';
import 'hls_segment_crypto.dart';
import 'media_fetch_headers.dart';
import 'm3u8_playlist_resolver.dart';

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

  final M3u8PlaylistResolver _playlistResolver = M3u8PlaylistResolver();

  Future<String?> serveFilePath(String filePath) async {
    if (kIsWeb) return null;
    final file = File(filePath);
    if (!await file.exists()) return null;
    await _ensureStarted();
    final port = _port;
    final lanIp = await _lanIp();
    if (port == null || lanIp == null) return null;

    final token = 'f${++_tokenSeq}';
    _files[token] = _ServedFile(
      file: file,
      contentType: _mimeForPath(filePath),
    );
    return 'http://$lanIp:$port/media/$token';
  }

  /// 远程 MP4 等直链：由手机代拉（带 Referer），电视访问局域网地址。
  Future<String?> serveRemoteMedia(String mediaUrl) async {
    if (kIsWeb) return null;
    final trimmed = mediaUrl.trim();
    if (trimmed.isEmpty) return null;
    await _ensureStarted();
    final port = _port;
    final lanIp = await _lanIp();
    if (port == null || lanIp == null) return null;

    final token = 'r${++_tokenSeq}';
    _remoteProxies[token] = _RemoteMediaProxy(
      url: trimmed,
      headers: MediaFetchHeaders.forUrl(trimmed),
      contentType: _mimeForPath(trimmed),
    );
    return 'http://$lanIp:$port/proxy/$token';
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
      return _serveHlsProxyForPlaylist(playlist);
    } catch (e) {
      debugPrint('serveHlsPlaylist failed: $e');
      return null;
    }
  }

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
      return 'http://127.0.0.1:$port/adfree/$token/index.m3u8';
    } catch (e) {
      debugPrint('serveAdFreeHls failed: $e');
      return null;
    }
  }

  /// 静态去广告播放列表数量上限（超出淘汰最旧的，防长时间会话内存增长）。
  static const _maxAdFreePlaylists = 8;

  void _evictAdFreePlaylists() {
    while (_adFreePlaylists.length > _maxAdFreePlaylists) {
      _adFreePlaylists.remove(_adFreePlaylists.keys.first);
    }
  }

  Future<String?> _serveHlsProxyForPlaylist(M3u8MediaPlaylist playlist) async {
    if (kIsWeb) return null;
    if (playlist.segmentUrls.isEmpty) return null;
    await _ensureStarted();
    final port = _port;
    final lanIp = await _lanIp();
    if (port == null || lanIp == null) return null;

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
    return 'http://$lanIp:$port/hls/$token/index.m3u8';
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
    final lanIp = await _lanIp();
    if (lanIp == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

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
    for (var i = 0; i < session.segmentUrls.length; i++) {
      final duration = i < session.segmentDurations.length
          ? session.segmentDurations[i]
          : 10.0;
      buffer.writeln('#EXTINF:${duration.toStringAsFixed(3)},');
      buffer.writeln('http://$lanIp:$port/hls/$token/$i');
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
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
    }
  }

  Future<bool> _tryStreamHlsSegment(
    HttpRequest request,
    _HlsProxySession session,
    int index,
  ) async {
    try {
      final req = await session.httpClient.getUrl(
        Uri.parse(session.segmentUrls[index]),
      );
      _applyRequestHeaders(req, session.headers);
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) {
        request.response.statusCode = res.statusCode;
        await request.response.close();
        return true;
      }

      request.response.headers.set('Content-Type', 'video/mp2t');
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.headers.set('Accept-Ranges', 'none');
      final length = res.contentLength;
      if (length >= 0) {
        request.response.contentLength = length;
      }
      if (request.method == 'HEAD') {
        await request.response.close();
        return true;
      }
      await request.response.addStream(res);
      await request.response.close();
      return true;
    } catch (e) {
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
    try {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final req = await client.getUrl(Uri.parse(url));
      _applyRequestHeaders(req, headers);
      if (range != null) {
        req.headers.set(HttpHeaders.rangeHeader, range);
      }
      final res = await req.close();
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
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
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
      unawaited(loadSegment(index));
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
