import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/app_env.dart';
import 'debug_log.dart';
import 'hls_ad_filter.dart';
import 'hls_variant_selector.dart';
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

  /// HLS 去广告总开关（设置 → 播放设置，默认开）。
  ///
  /// 个别片源被误判删片时，用户可整个关掉过滤回退直连。
  /// 静态变量：本地代理（LocalMediaHttpServer）与缓存下载（CacheService）
  /// 共用同一个解析器链路，开关必须对两者同时生效。
  static bool adFilterEnabled = true;

  /// 用户可维护广告规则（assets/ad_block_rules.json），懒加载并缓存。
  static AdBlockRules? _cachedRules;

  /// 用户设置的默认清晰度（'自动' / '标清' / '高清' / '1080P' / '4K'）。
  ///
  /// 只作用于 **HLS master playlist 的多档变体**：设成固定档位时，先解析出
  /// 目标码率的 media playlist 再播放，而不是把选择权交给 mpv（mpv 默认挑
  /// 码率最高的一档，低端机/流量场景会明显吃亏）。'自动' 保持原行为。
  ///
  /// 静态变量：播放器直连、本地代理（[LocalMediaHttpServer]）、缓存下载
  /// （[CacheService]）走的是不同实例，设置必须对三者同时生效。
  static String preferredQuality = '自动';

  /// 读取广告规则；文件缺失 / 解析失败一律回退 [AdBlockRules.empty]，不影响播放。
  static Future<AdBlockRules> get rules async {
    if (_cachedRules != null) return _cachedRules!;
    try {
      final raw = await rootBundle.loadString('assets/ad_block_rules.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _cachedRules = AdBlockRules.fromJson(json);
    } catch (e) {
      debugPrint('读取广告规则失败，使用空规则: $e');
      _cachedRules = AdBlockRules.empty;
    }
    return _cachedRules!;
  }

  /// 测试 / 特殊场景可强制注入规则（绕过 assets）。
  static void setRulesForTest(AdBlockRules rules) => _cachedRules = rules;

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
    final aes = parseAes128Key(content, playlistUrl);
    // 总开关关闭时不应用规则清单、也不跑启发式（用户主动放弃过滤）。
    final filterRules = adFilterEnabled ? await rules : AdBlockRules.empty;
    final adFilter = HlsAdFilter.filterContent(
      content,
      playlistUrl,
      rules: filterRules,
      heuristicsEnabled: adFilterEnabled,
    );
    if (!AppEnv.isTestMode) {
      DebugLog.log(
        'AdFilter',
        'resolve: filterEnabled=$adFilterEnabled enc=${aes != null} '
            'kept=${adFilter.keptUrls.length} '
            'removed=${adFilter.removedSegments}片/'
            '${adFilter.removedSeconds.toStringAsFixed(1)}s '
            'url=$playlistUrl',
      );
    }
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
      final variant = _pickVariantUrl(content, current);
      if (variant == null || variant == current) {
        return current;
      }
      current = variant;
    }
    return current;
  }

  /// 按用户设置挑出 master playlist 的变体地址。
  ///
  /// 返回 null 表示不用改地址：设置为「自动」、URL 不是 master playlist、
  /// 或请求失败 —— 调用方应保持原地址不变（失败即回退直连）。
  Future<String?> resolvePreferredVariant(
    String url, {
    String? referer,
  }) async {
    if (HlsVariantSelector.targetHeightOf(preferredQuality) == null) {
      return null;
    }
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return null;
    }
    try {
      final dio = await _client();
      // Web 端 User-Agent / Referer / Origin 是浏览器禁止 JS 自定义的
      // forbidden headers，Dio 的浏览器 adapter 设置它们会直接抛异常，
      // 导致选档静默失败并回退原始地址。原生端仍需要这些头防盗链。
      final headers = kIsWeb
          ? const <String, String>{}
          : MediaFetchHeaders.forUrl(
              trimmed,
              referer: referer ?? trimmed,
            );
      final response = await dio.get<String>(
        trimmed,
        options: Options(headers: headers),
      );
      final content = response.data?.toString() ?? '';
      if (!_isMasterPlaylist(content)) return null;
      final picked = _pickVariantUrl(content, trimmed);
      if (!AppEnv.isTestMode && picked != null) {
        DebugLog.log(
          'Quality',
          '按「$preferredQuality」选中变体 $picked（master=$trimmed）',
        );
      }
      return picked;
    } catch (e) {
      // 失败必须可见：否则用户在 Web 上改了默认清晰度却毫无提示地回退。
      if (!AppEnv.isTestMode) {
        DebugLog.log('Quality', '选档失败，回退原始地址: $e');
      }
      debugPrint('清晰度选档失败，回退原始地址: $e');
      return null;
    }
  }

  static bool _isMasterPlaylist(String content) {
    final upper = content.toUpperCase();
    return upper.contains('#EXT-X-STREAM-INF');
  }

  /// 选变体：交给 [HlsVariantSelector]（纯函数，便于单测）。
  static String? _pickVariantUrl(String content, String baseUrl) =>
      HlsVariantSelector.pick(
        content: content,
        baseUrl: baseUrl,
        quality: preferredQuality,
      );

  /// 解析 `#EXT-X-KEY`（AES-128）。纯函数，供单测。
  ///
  /// 属性顺序不敏感：规范允许 `URI=` 出现在 `METHOD=` 前后，旧的固定顺序
  /// 正则会把 `URI="...",METHOD=AES-128` 漏判成明文 → 重建播放列表时丢掉
  /// KEY 行 → 播放器拿到未解密的乱码分片（花屏/解码错误/闪退）。
  /// `METHOD=NONE` 视为未加密。
  static M3u8Aes128Key? parseAes128Key(String content, String baseUrl) {
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (!line.startsWith('#EXT-X-KEY:')) continue;
      final attrs = line.substring('#EXT-X-KEY:'.length);
      final method = _keyAttr(attrs, 'METHOD')?.toUpperCase();
      if (method == null || method != 'AES-128') continue;
      final uriValue = _keyAttr(attrs, 'URI');
      if (uriValue == null || uriValue.isEmpty) continue;
      var ivHex = _keyAttr(attrs, 'IV');
      // 规范里 IV 形如 0x 开头的十六进制；统一去掉前缀，方便下游解析。
      if (ivHex != null && (ivHex.startsWith('0x') || ivHex.startsWith('0X'))) {
        ivHex = ivHex.substring(2);
      }
      return M3u8Aes128Key(
        uri: _resolveUrl(baseUrl, uriValue),
        ivHex: (ivHex != null && ivHex.isNotEmpty) ? ivHex : null,
      );
    }
    return null;
  }

  /// 取 `#EXT-X-KEY` 属性值（逗号分隔，值可带引号）。
  static String? _keyAttr(String attrs, String name) {
    final match = RegExp('(?:^|,)\\s*$name\\s*=\\s*(?:"([^"]*)"|([^,]*))')
        .firstMatch(attrs);
    final quoted = match?.group(1);
    if (quoted != null) return quoted;
    final bare = match?.group(2)?.trim();
    return (bare == null || bare.isEmpty) ? null : bare;
  }

  static String _resolveUrl(String baseUrl, String ref) {
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return ref;
    }
    return Uri.parse(baseUrl).resolve(ref).toString();
  }
}
