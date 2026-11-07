import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../pages/detail/playback/subtitle_format_policy.dart';
import '../pages/detail/playback/subtitle_simplified_policy.dart';
import 'debug_log.dart';

/// 一条在线字幕候选。
///
/// 2026-11-07 S5：删掉旧 `api.opensubtitles.com/api/v1` 需要 Api-Key 与
/// login 的链路后，`fileId` 不再存在 —— 免费源直接给可下载直链。
/// [providerId] 标明来源，便于多源时把下载路由回同一个 provider。
class SubtitleInfo {
  const SubtitleInfo({
    required this.fileName,
    required this.downloadUrl,
    required this.providerId,
    required this.language,
    this.downloadsCount = 0,
    this.releaseName = '',
    this.season = 0,
    this.episode = 0,
    this.score = 0,
  });

  final String fileName;
  final String downloadUrl;
  final String providerId;
  final String language;
  final int downloadsCount;
  final String releaseName;
  final int season;
  final int episode;

  /// 简体 100 > 中文未分 80 > 繁体 60。
  final int score;
}

/// 在线字幕搜索源接口（S5 provider 化）。
///
/// 换源 / 加源只需实现本接口并注册进 [SubtitleService.providers]，
/// 编排逻辑（聚合去重、简体优先、失败可见）不用改。
abstract class SubtitleSearchProvider {
  String get id;
  String get label;

  Future<List<SubtitleInfo>> searchChinese({
    required String imdbId,
    int? season,
    int? episode,
  });

  /// 返回字幕原始字节；编码探测与落盘由服务层统一处理。
  Future<List<int>?> downloadBytes(SubtitleInfo info);
}

/// 免费、无 Key、无账号的 OpenSubtitles v3 代理。
///
/// 2026-11-06 抽检实测：代理/直连双路 200、按 IMDb 查字幕、下载端点
/// 返回字幕内容且带 `access-control-allow-origin: *`。项目原用的
/// `api.opensubtitles.com/api/v1` 需 Api-Key 且 login 形态有误，不满足
/// 「零门槛」约束，已整体移除。
///
/// 单独用一个不带任何自定义头的 Dio：Web 端若被塞入 User-Agent / Referer
/// 等 forbidden headers，Dio Web adapter 会直接抛异常且常被 catch 吞掉。
class StremioFreeSubtitleProvider implements SubtitleSearchProvider {
  static const String providerKey = 'stremio-free-v3';
  static const String freeApiBase = 'https://opensubtitles-v3.strem.io';

  Dio? _dio;

  Dio _client() {
    final client = _dio;
    if (client != null) return client;
    final created = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
      ),
    );
    _dio = created;
    return created;
  }

  @override
  String get id => providerKey;

  @override
  String get label => '免费在线字幕（无需配置）';

  @override
  Future<List<SubtitleInfo>> searchChinese({
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    final id = imdbId.trim();
    if (id.isEmpty) return <SubtitleInfo>[];
    final isEpisode = (season ?? 0) > 0 && (episode ?? 0) > 0;
    final path = isEpisode
        ? '/subtitles/series/$id:$season:$episode.json'
        : '/subtitles/movie/$id.json';
    final resp = await _client().get<dynamic>('$freeApiBase$path');
    final root = resp.data;
    if (root is String) {
      // responseType=plain：自己解码，避免 Dio 在部分平台把 JSON 当 Map 处理。
      if (root.trim().isEmpty) return <SubtitleInfo>[];
      return _parseFreeSubtitleList(jsonDecode(root));
    }
    return _parseFreeSubtitleList(root);
  }

  List<SubtitleInfo> _parseFreeSubtitleList(dynamic root) {
    final out = <SubtitleInfo>[];
    if (root is! Map) return out;
    final list = root['subtitles'];
    if (list is! List) return out;
    for (final raw in list) {
      if (raw is! Map) continue;
      final lang = (raw['lang'] is String ? raw['lang'] as String : '').trim();
      final name = (raw['subtitleFileName'] is String
              ? raw['subtitleFileName'] as String
              : '')
          .trim();
      final url = (raw['url'] is String ? raw['url'] as String : '').trim();
      if (url.isEmpty) continue;
      final variant = classifyChineseVariant(lang: lang, fileName: name);
      if (variant == ChineseVariant.notChinese) continue;
      final score = variant == ChineseVariant.simplified
          ? 100
          : (variant == ChineseVariant.neutral ? 80 : 60);
      out.add(
        SubtitleInfo(
          fileName: name.isEmpty ? 'online-zh.srt' : name,
          downloadUrl: url,
          providerId: providerKey,
          language: lang.isEmpty ? 'zh' : lang,
          releaseName: (raw['movieReleaseName'] is String
                  ? raw['movieReleaseName'] as String
                  : '')
              .trim(),
          score: score,
        ),
      );
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  @override
  Future<List<int>?> downloadBytes(SubtitleInfo info) async {
    if (info.downloadUrl.trim().isEmpty) return null;
    final resp = await _client().get<List<int>>(
      info.downloadUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = resp.data;
    if (data == null || data.isEmpty) return null;
    return data;
  }
}

/// 在线字幕编排：多源聚合去重、简体优先、失败可见但不弹窗。
class SubtitleService {
  SubtitleService._();
  static final SubtitleService _instance = SubtitleService._();
  factory SubtitleService() => _instance;

  /// 注册的全部在线源。当前只有一个免费无 Key 源。
  final List<SubtitleSearchProvider> providers = <SubtitleSearchProvider>[
    StremioFreeSubtitleProvider(),
  ];

  String _lastError = '';

  /// 最近一次失败原因（供字幕面板 / 设置页显示，不弹窗打扰）。
  String get lastError => _lastError;

  String get providerLabel => providers.map((p) => p.label).join(' / ');

  void _recordError(String msg) {
    _lastError = msg;
    DebugLog.log('Subtitle', msg);
  }

  /// 按 IMDb 查在线中文字幕，简体优先。
  ///
  /// 剧集传 [season]/[episode] 时走 `/series/tt:S:E.json`；失败一律返回
  /// 空列表并记 [lastError]，不抛异常、不阻塞播放。
  Future<List<SubtitleInfo>> searchFreeChinese({
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    final id = imdbId.trim();
    if (id.isEmpty) return <SubtitleInfo>[];
    final merged = <String, SubtitleInfo>{};
    var failures = 0;
    for (final provider in providers) {
      try {
        final list = await provider.searchChinese(
          imdbId: id,
          season: season,
          episode: episode,
        );
        for (final item in list) {
          merged.putIfAbsent(item.downloadUrl, () => item);
        }
      } catch (e) {
        failures++;
        _recordError('在线字幕查询失败（${provider.label}）：$e');
      }
    }
    final out = merged.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (out.isNotEmpty) {
      _lastError = '';
    } else if (failures == 0) {
      _lastError = '在线字幕源暂无中文字幕';
      DebugLog.log('Subtitle', _lastError);
    }
    return out;
  }

  /// 下载字幕并按真实格式落盘，返回文件路径。
  ///
  /// S5 三处修正：① 按 `.srt/.ass/.ssa/.vtt/.sub` 真实扩展名保存（原先恒存
  /// `.srt`，会丢 ASS 特效）；② BOM / UTF-8 / UTF-16 探测，非 UTF-8 原样
  /// 写字节不做假转码；③ 失败写 DebugLog + [lastError]，面板可见但不弹窗。
  /// Web 无文件系统，返回 null 由调用方降级。
  Future<String?> downloadFreeSubtitle(SubtitleInfo info) async {
    if (kIsWeb || info.downloadUrl.trim().isEmpty) return null;
    try {
      var provider = providers.first;
      for (final p in providers) {
        if (p.id == info.providerId) {
          provider = p;
          break;
        }
      }
      final bytes = await provider.downloadBytes(info);
      if (bytes == null || bytes.isEmpty) {
        _recordError('在线字幕下载失败：返回内容为空');
        return null;
      }
      final decoded = decodeSubtitleBytes(bytes);
      final ext = subtitleExtensionFor(
        fileName: info.fileName,
        url: info.downloadUrl,
      );
      final dir = await getSubtitleCacheDir();
      if (dir.isEmpty) return null;
      final path = '$dir/free_${info.downloadUrl.hashCode.abs()}$ext';

      if (decoded.isText) {
        var text = decoded.text!;
        final variant = classifyChineseVariant(
          lang: info.language,
          fileName: info.fileName,
        );
        if (variant == ChineseVariant.traditional) {
          text = traditionalToSimplified(text);
        }
        // 统一写成无 BOM 的 UTF-8，避免 mpv 把 BOM 当可见字符。
        await File(path).writeAsString(text, encoding: utf8);
      } else {
        // 疑似 GBK/BIG5：项目无对应解码包，原样保留字节。
        await File(path).writeAsBytes(decoded.rawBytes);
        DebugLog.log(
          'Subtitle',
          '字幕编码=${decoded.label}，原样保留字节，未做繁→简转换；'
          '若显示乱码请在 mpv 设置 sub-codepage',
        );
      }
      DebugLog.log(
        'Subtitle',
        '在线字幕已保存 ${info.fileName} → $ext / ${decoded.label}',
      );
      // 下载成功后清掉上一次的失败原因，避免面板里一直挂着旧错误。
      _lastError = '';
      return path;
    } catch (e) {
      _recordError('在线字幕下载失败：$e');
      return null;
    }
  }

  /// 读取已落盘字幕的文本（S4 时轴体检用）。
  ///
  /// 用 `allowMalformed` 解码：GBK / BIG5 字幕的汉字字节会被替换，但时间轴
  /// 全是 ASCII 数字，仍能正确解析。Web 无本地文件系统，返回 null。
  Future<String?> readCachedSubtitleText(String path) async {
    if (kIsWeb || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      // 超大字幕（>16MB）不读，避免首帧后的链路被 I/O 拖住。
      if (bytes.length > 16 * 1024 * 1024) return null;
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      debugPrint('读取字幕文本失败: $e');
      return null;
    }
  }

  Future<String> getSubtitleCacheDir() async {
    // Web 端无本地文件系统，返回空路径
    if (kIsWeb) return '';
    final tempDir = await getTemporaryDirectory();
    final dir = '${tempDir.path}/movie_app/subtitles';
    await Directory(dir).create(recursive: true);
    return dir;
  }
}
