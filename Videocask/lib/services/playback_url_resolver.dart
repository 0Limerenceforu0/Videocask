import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'cache_service.dart';
import 'local_media_http_server.dart';
import 'm3u8_playlist_resolver.dart';
import 'network/dio_factory.dart';
import 'playback_strategy.dart';
import 'video_parser.dart';
// Web 端需要把媒体地址包装成同源地址（hls.js 也受同源策略限制）
import '../utils/web_http_stub.dart'
    if (dart.library.html) '../utils/web_http.dart' as web_http;

/// 解析播放页、优先本地缓存、可选 Range 预拉流。
class PlaybackUrlResolver {
  PlaybackUrlResolver({
    VideoParser? parser,
    CacheService? cacheService,
  })  : _parser = parser ?? VideoParser(),
        _cacheService = cacheService ?? CacheService();

  final VideoParser _parser;
  final CacheService _cacheService;

  final Map<String, String> _parsedUrlCache = {};

  /// 是否像采集站网页播放页（需 [VideoParser]）。
  static bool needsWebParse(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.isEmpty) return false;
    if (lower.startsWith('magnet:')) return false;
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }
    if (lower.contains('.m3u8')) return false;
    if (lower.contains('.mp4') ||
        lower.contains('.mkv') ||
        lower.contains('.flv') ||
        lower.contains('.ts')) {
      return false;
    }
    return true;
  }

  /// 播放用：本地已完成缓存 > 解析 > 原始 URL。
  Future<String> resolveForPlayback({
    required String episodeUrl,
    required String movieId,
    required int episodeIndex,
    String sourceId = '',
  }) async {
    final local = await _cacheService.completedLocalPlayUri(
      movieId: movieId,
      episodeIndex: episodeIndex,
      sourceId: sourceId,
    );
    if (local != null) return local;

    if (needsWebParse(episodeUrl)) {
      final cached = _parsedUrlCache[episodeUrl];
      if (cached != null && cached.isNotEmpty) return cached;
      final parsed = await _parser.parseVideoUrl(episodeUrl);
      if (parsed != null && parsed.isNotEmpty) {
        _parsedUrlCache[episodeUrl] = parsed;
        return parsed;
      }
    }
    return episodeUrl;
  }

  /// 离线下载用：解析播放页得到直链，不读取本地已完成缓存。
  Future<String> resolveForDownload(String episodeUrl) async {
    return resolveForProbe(episodeUrl);
  }

  /// 线路探针用：尽量得到可直连的 m3u8 / 媒体地址。
  Future<String> resolveForProbe(String episodeUrl) async {
    if (needsWebParse(episodeUrl)) {
      final cached = _parsedUrlCache[episodeUrl];
      if (cached != null && cached.isNotEmpty) return cached;
      final parsed = await _parser.parseVideoUrl(episodeUrl);
      if (parsed != null && parsed.isNotEmpty) {
        _parsedUrlCache[episodeUrl] = parsed;
        return parsed;
      }
    }
    return episodeUrl;
  }

  /// 后台预解析下一集（不阻塞 UI）。
  ///
  /// [prefetchEnabled] 必须在解析之前判断：旧实现先 `resolveForPlayback`
  /// 才看开关，导致关掉「播放预缓冲」照样会解析下一集 URL、发一轮网络请求。
  Future<void> prefetchEpisodeUrl({
    required String episodeUrl,
    required String movieId,
    required int episodeIndex,
    String sourceId = '',
    required String strategy,
    bool prefetchEnabled = true,
  }) async {
    if (!prefetchEnabled) return;
    final resolved = await resolveForPlayback(
      episodeUrl: episodeUrl,
      movieId: movieId,
      episodeIndex: episodeIndex,
      sourceId: sourceId,
    );

    final config = PlaybackStrategyConfig.fromKey(strategy);
    if (config.prefetchBytes <= 0) return;
    if (kIsWeb) return;

    await warmNetworkHead(resolved, maxBytes: config.prefetchBytes);
  }

  /// Range 预拉前几 KB/MB，暖 TCP / CDN 连接。
  static Future<void> warmNetworkHead(
    String url, {
    int maxBytes = 1024 * 1024,
  }) async {
    if (maxBytes <= 0) return;
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return;
    }
    final end = maxBytes - 1;
    try {
      final dio = await DioFactory.plainText(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
      );
      await dio.get<String>(
        url,
        options: Options(
          headers: {'Range': 'bytes=0-$end'},
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
    } catch (e) {
      debugPrint('预拉流失败: $url → $e');
    }
  }

  void clearParsedCache() {
    _parsedUrlCache.clear();
  }

  /// 播放器直接打开用：尝试把远端 m3u8 换成本地去广告代理地址。
  ///
  /// 仅在 [resolveForPlayback] 解析出的远端 HLS 上生效：
  /// - 检测到广告分片 → 返回本地代理地址（mpv 仍直连 CDN 拉正片分片）；
  /// - 未检测到广告 / Web 端 / 代理失败 → 原样返回，行为与旧版一致。
  ///
  /// 注意：返回值只供播放器 open 使用；DLNA 投屏、统计等场景请继续使用
  /// [resolveForPlayback] 的远端地址，避免二次代理。
  Future<String> openUrlForPlayer(String resolvedUrl) async {
    if (kIsWeb) {
      // Web 端没有本地 HTTP 代理服务，统一交给同源 CORS 代理：
      // m3u8 走 /hls（重写播放列表+分片），其余走 /proxy（支持 Range）。
      final lower = resolvedUrl.trim().toLowerCase();
      if (lower.contains('.m3u8')) return web_http.webHlsUrl(resolvedUrl);
      return web_http.webProxiedMediaUrl(resolvedUrl);
    }
    final lower = resolvedUrl.trim().toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return resolvedUrl;
    }
    if (!lower.contains('.m3u8')) return resolvedUrl;
    if (lower.contains('/adfree/') || lower.contains('/hls/')) {
      // 已是本地代理地址，避免重复包装。
      return resolvedUrl;
    }
    // 用户设了固定清晰度：先把 master playlist 解析成目标码率的 media 列表。
    // 这一步与去广告互补——变体确定后再走 adfree，广告过滤仍作用于实际播放
    // 的那一档；设置「自动」时该方法直接返回 null，零额外请求。
    final preferred =
        await M3u8PlaylistResolver().resolvePreferredVariant(resolvedUrl);
    if (preferred != null && preferred.isNotEmpty) {
      resolvedUrl = preferred;
    }
    try {
      final adFree = await LocalMediaHttpServer.instance.serveAdFreeHls(
        resolvedUrl,
      );
      if (adFree != null && adFree.isNotEmpty) {
        return adFree;
      }
    } catch (e) {
      debugPrint('HLS 去广告代理失败，回退直连: $e');
    }
    return resolvedUrl;
  }
}
