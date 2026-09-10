import 'package:dio/dio.dart';

import 'hls_ad_filter.dart';
import 'media_fetch_headers.dart';

/// HLS AES-128 密钥信息（常见 CMS 片源）。
class M3u8Aes128Key {
  const M3u8Aes128Key({
    required this.uri,
    this.ivHex,
  });

  final String uri;
  final String? ivHex;
}

/// 已解析到可播放/可下载的媒体分片列表（已剔除广告分片）。
class M3u8MediaPlaylist {
  const M3u8MediaPlaylist({
    required this.playlistUrl,
    required this.content,
    required this.segmentUrls,
    this.aes128Key,
    this.segmentDurations = const [],
    this.segmentSourceIndices = const [],
    this.removedAdSegments = 0,
    this.removedAdSeconds = 0,
    this.adFilter,
  });

  final String playlistUrl;
  final String content;

  /// 剔除广告后的分片绝对地址。
  final List<String> segmentUrls;

  final M3u8Aes128Key? aes128Key;

  /// 与 [segmentUrls] 对齐的 EXTINF 时长（秒）。
  final List<double> segmentDurations;

  /// 与 [segmentUrls] 对齐的原始分片序号。
  ///
  /// AES-128 隐式 IV 由分片序号推导，剔除广告后序号会位移，
  /// 解密时必须使用这里的原始序号。
  final List<int> segmentSourceIndices;

  /// 被广告过滤器剔除的分片数 / 总时长（秒）。
  final int removedAdSegments;
  final double removedAdSeconds;

  /// 完整过滤结果（含分块结构等重建播放列表所需信息）。
  final HlsAdFilterResult? adFilter;

  bool get isEncrypted => aes128Key != null;

  /// 是否剔除了广告分片。
  bool get hasAdRemoved => removedAdSegments > 0;
}

/// 解析 master / media m3u8，得到最终分片 URL 列表。
class M3u8PlaylistResolver {
  M3u8PlaylistResolver({Dio? dio}) : _dio = dio;

  Dio? _dio;

  Future<Dio> _client() async {
    _dio ??= Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        responseType: ResponseType.plain,
      ),
    );
    return _dio!;
  }

  Future<M3u8MediaPlaylist> resolve(String url, {String? referer}) async {
    final playlistUrl = await _resolveToMediaPlaylistUrl(
      url,
      referer: referer,
    );
    final dio = await _client();
    final headers = MediaFetchHeaders.forUrl(
      playlistUrl,
      referer: referer ?? url,
    );
    final response = await dio.get<String>(
      playlistUrl,
      options: Options(headers: headers),
    );
    final content = response.data?.toString() ?? '';
    final aes = _parseAes128Key(content, playlistUrl);
    final adFilter = HlsAdFilter.filterContent(content, playlistUrl);
    return M3u8MediaPlaylist(
      playlistUrl: playlistUrl,
      content: content,
      segmentUrls: adFilter.keptUrls,
      aes128Key: aes,
      segmentDurations: adFilter.keptDurations,
      segmentSourceIndices: adFilter.keptIndices,
      removedAdSegments: adFilter.removedSegments,
      removedAdSeconds: adFilter.removedSeconds,
      adFilter: adFilter,
    );
  }

  Future<String> _resolveToMediaPlaylistUrl(
    String url, {
    String? referer,
  }) async {
    final dio = await _client();
    var current = url.trim();
    for (var depth = 0; depth < 4; depth++) {
      final headers = MediaFetchHeaders.forUrl(
        current,
        referer: referer ?? url,
      );
      final response = await dio.get<String>(
        current,
        options: Options(headers: headers),
      );
      final content = response.data?.toString() ?? '';
      if (!_isMasterPlaylist(content)) {
        return current;
      }
      final variant = _pickBestVariantUrl(content, current);
      if (variant == null || variant == current) {
        return current;
      }
      current = variant;
    }
    return current;
  }

  static bool _isMasterPlaylist(String content) {
    final upper = content.toUpperCase();
    return upper.contains('#EXT-X-STREAM-INF');
  }

  static String? _pickBestVariantUrl(String content, String baseUrl) {
    final lines = content.split('\n');
    String? bestUrl;
    var bestBandwidth = -1;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      final bandwidth =
          bwMatch != null ? int.tryParse(bwMatch.group(1)!) : null;
      var j = i + 1;
      while (j < lines.length) {
        final next = lines[j].trim();
        if (next.isEmpty || next.startsWith('#')) {
          j++;
          continue;
        }
        final resolved = _resolveUrl(baseUrl, next);
        final bw = bandwidth ?? 0;
        if (bw >= bestBandwidth) {
          bestBandwidth = bw;
          bestUrl = resolved;
        }
        break;
      }
    }
    return bestUrl;
  }

  static M3u8Aes128Key? _parseAes128Key(String content, String baseUrl) {
    final match = RegExp(
      r'#EXT-X-KEY:METHOD=AES-128,URI="([^"]+)"(?:,IV=0x([0-9A-Fa-f]+))?',
    ).firstMatch(content);
    if (match == null) return null;
    final uri = _resolveUrl(baseUrl, match.group(1)!);
    return M3u8Aes128Key(uri: uri, ivHex: match.group(2));
  }

  static String _resolveUrl(String baseUrl, String ref) {
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return ref;
    }
    return Uri.parse(baseUrl).resolve(ref).toString();
  }
}
