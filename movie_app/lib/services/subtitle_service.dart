import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../config/constants.dart';
import 'network/dio_factory.dart';
import 'storage_service.dart';

/// 字幕信息（OpenSubtitles REST：每条对应 [files] 里的一条，含 [fileId] 用于下载）
class SubtitleInfo {
  final String fileName;

  /// 若 API 直接返回可下载 URL（少见），否则为空，使用 [fileId]。
  final String downloadUrl;
  final int? fileId;
  final String language;
  final int downloadsCount;
  final String releaseName;

  /// 从文件名/release 名解析出的季号（0 表示未识别）。
  final int season;

  /// 从文件名/release 名解析出的集号（0 表示未识别）。
  final int episode;

  /// 与当前资源的匹配得分（越高越可信，仅 [SubtitleService.searchBest] 会填）。
  final int score;

  const SubtitleInfo({
    required this.fileName,
    required this.downloadUrl,
    this.fileId,
    required this.language,
    required this.downloadsCount,
    required this.releaseName,
    this.season = 0,
    this.episode = 0,
    this.score = 0,
  });

  SubtitleInfo copyWith({int? season, int? episode, int? score}) {
    return SubtitleInfo(
      fileName: fileName,
      downloadUrl: downloadUrl,
      fileId: fileId,
      language: language,
      downloadsCount: downloadsCount,
      releaseName: releaseName,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      score: score ?? this.score,
    );
  }
}

/// 从字幕文件名 / release 名中解析季集号。
///
/// 支持 `S01E02`、`s1e2`、`1x02`、`第2集` 等常见写法；识别不到返回 (0, 0)。
({int season, int episode}) parseSeasonEpisode(String source) {
  final s = source.toLowerCase();
  final m1 = RegExp(r's(\d{1,2})[ ._-]*e(\d{1,3})').firstMatch(s);
  if (m1 != null) {
    return (
      season: int.tryParse(m1.group(1) ?? '') ?? 0,
      episode: int.tryParse(m1.group(2) ?? '') ?? 0,
    );
  }
  final m2 =
      RegExp(r'(?:^|[^0-9])(\d{1,2})x(\d{2,3})(?:[^0-9]|$)').firstMatch(s);
  if (m2 != null) {
    return (
      season: int.tryParse(m2.group(1) ?? '') ?? 0,
      episode: int.tryParse(m2.group(2) ?? '') ?? 0,
    );
  }
  final cnEp = RegExp(r'第\s*(\d{1,3})\s*集').firstMatch(source);
  if (cnEp != null) {
    final cnSeason = RegExp(r'第\s*(\d{1,2})\s*季').firstMatch(source);
    return (
      season: int.tryParse(cnSeason?.group(1) ?? '') ?? 0,
      episode: int.tryParse(cnEp.group(1) ?? '') ?? 0,
    );
  }
  return (season: 0, episode: 0);
}

/// 归一化名称：小写、分隔符统一为空格，便于做 token 重合比较。
String normalizeName(String source) {
  return source
      .toLowerCase()
      .replaceAll(RegExp(r'[._\[\](){}]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// 计算名称 token 集合（去掉分辨率/编码/压制组等噪声词）。
Set<String> nameTokens(String source) {
  const noise = <String>{
    '1080p',
    '720p',
    '480p',
    '2160p',
    '4k',
    '8k',
    'web',
    'webrip',
    'webdl',
    'web-dl',
    'bluray',
    'blueray',
    'bdrip',
    'brrip',
    'dvdrip',
    'hdrip',
    'remux',
    'hdtv',
    'x264',
    'x265',
    'h264',
    'h265',
    'hevc',
    'avc',
    '10bit',
    '8bit',
    'hdr',
    'hdr10',
    'dv',
    'dolby',
    'atmos',
    'aac',
    'ac3',
    'eac3',
    'dts',
    'truehd',
    'mp3',
    'flac',
    'mp4',
    'mkv',
    'avi',
    'mov',
    'ts',
    'srt',
    'ass',
    'ssa',
    'sub',
    'idx',
    'eng',
    'chs',
    'cht',
    'chi',
    'zho',
    'gb',
    'big5',
    '简',
    '繁',
    '中字',
    '双语',
    'subbed',
    'proper',
    'repack',
    'internal',
    'limited',
    'complete',
    'season',
    'episode',
    'the',
    'a',
    'an',
    'amzn',
    'nf',
    'dsnp',
    'hmax',
    'atvp',
    'hulu',
    'pcok',
    'stan',
    'itunes',
    'ntb',
    'flux',
    'rarbg',
    'yify',
    'yts',
    'eztv',
    'rartv',
  };
  return normalizeName(source)
      .split(' ')
      .where((t) => t.length >= 2 && !noise.contains(t))
      .toSet();
}

/// 两个名称的 token 重合度（0~1）。
double tokenOverlap(String a, String b) {
  final ta = nameTokens(a);
  final tb = nameTokens(b);
  if (ta.isEmpty || tb.isEmpty) return 0;
  final inter = ta.intersection(tb).length;
  return inter / (ta.length < tb.length ? ta.length : tb.length);
}

/// 字幕服务（OpenSubtitles.com API v1）
class SubtitleService {
  SubtitleService._();
  static final SubtitleService _instance = SubtitleService._();
  factory SubtitleService() => _instance;

  Dio? _dio;

  /// 初始化Dio实例
  Future<Dio> _getDio() async {
    _dio ??= await DioFactory.json();
    return _dio!;
  }

  /// OpenSubtitles API 配置 — 免费注册: https://www.opensubtitles.com
  static const String _baseUrl = 'https://api.opensubtitles.com/api/v1';

  /// 从 [StorageService] 读取；在「设置」中配置 [AppConstants.keyOpensubtitlesApiKey]。
  String _apiKey = '';

  String? _userToken;

  /// Key 变更后清除登录态，下次 [init] 会重新 login。
  void invalidateAuth() {
    _userToken = null;
  }

  void _reloadApiKeyFromStorage() {
    _apiKey = StorageService()
            .getSetting(AppConstants.keyOpensubtitlesApiKey)
            ?.trim() ??
        '';
  }

  /// 中文字幕常用语言码（逗号分隔，与 API 文档一致）
  static const String chineseLanguages = 'zh-cn,zh-tw,zh,zho';

  Future<bool> init() async {
    _reloadApiKeyFromStorage();
    if (_apiKey.isEmpty) {
      debugPrint('字幕服务: 未配置 API Key，请在「设置 → OpenSubtitles API Key」填写');
      return false;
    }
    try {
      final dio = await _getDio();
      final resp = await dio.post(
        '$_baseUrl/login',
        data: jsonEncode({'apikey': _apiKey}),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final respData = resp.data as Map<String, dynamic>?;
      _userToken = respData?['token'] as String?;
      return _userToken != null;
    } catch (e) {
      debugPrint('字幕服务登录失败: $e');
      return false;
    }
  }

  /// 解析 GET /subtitles 的 JSON:API 结构，展开 [attributes.files]。
  List<SubtitleInfo> _parseSubtitlesSearchResponse(dynamic body) {
    final out = <SubtitleInfo>[];
    if (body is! Map) return out;
    final data = body['data'];
    if (data is! List) return out;

    for (final raw in data) {
      if (raw is! Map) continue;
      final attrs = raw['attributes'];
      if (attrs is! Map) continue;

      final files = attrs['files'];
      if (files is! List || files.isEmpty) continue;

      final lang = attrs['language']?.toString() ?? '';
      final downloads =
          int.tryParse(attrs['download_count']?.toString() ?? '') ??
              int.tryParse(attrs['downloads_count']?.toString() ?? '') ??
              0;
      var releaseName = attrs['release']?.toString() ?? '';
      final feature = attrs['feature_details'];
      if (feature is Map) {
        final mn = feature['movie_name']?.toString() ?? '';
        final y = feature['year']?.toString() ?? '';
        if (mn.isNotEmpty) {
          releaseName = releaseName.isEmpty
              ? (y.isNotEmpty ? '$mn ($y)' : mn)
              : releaseName;
        }
      }

      for (final f in files) {
        if (f is! Map) continue;
        final fidRaw = f['file_id'];
        final id =
            fidRaw is int ? fidRaw : int.tryParse(fidRaw?.toString() ?? '');
        if (id == null || id <= 0) continue;
        final fn = f['file_name']?.toString() ?? 'subtitle.srt';
        // 季集号优先从字幕文件名取，取不到再看 release 名（整季包常只在 release 上有）。
        var se = parseSeasonEpisode(fn);
        if (se.episode == 0 && releaseName.isNotEmpty) {
          se = parseSeasonEpisode(releaseName);
        }
        out.add(
          SubtitleInfo(
            fileName: fn,
            downloadUrl: '',
            fileId: id,
            language: lang,
            downloadsCount: downloads,
            releaseName: releaseName,
            season: se.season,
            episode: se.episode,
          ),
        );
      }
    }
    return out;
  }

  String? _extractDownloadLink(dynamic root) {
    if (root is! Map) return null;
    final m = Map<String, dynamic>.from(root);
    final direct = m['link'] ?? m['url'];
    if (direct is String && direct.startsWith('http')) return direct;
    final inner = m['data'];
    if (inner is Map) {
      final l = inner['link'] ?? inner['url'];
      if (l is String && l.startsWith('http')) return l;
    }
    return null;
  }

  /// 搜索字幕（按影片名）。[languages] 默认包含简体/繁体/中文通用码。
  Future<List<SubtitleInfo>> searchByName(
    String query, {
    String languages = chineseLanguages,
  }) async {
    if (_userToken == null && !await init()) return [];
    final q = query.trim();
    if (q.isEmpty) return [];

    try {
      final dio = await _getDio();
      final resp = await dio.get(
        '$_baseUrl/subtitles',
        queryParameters: {
          'query': q,
          'languages': languages,
        },
        options: Options(
          headers: {
            'Api-Key': _apiKey,
            'Authorization': 'Bearer $_userToken',
          },
        ),
      );
      return _parseSubtitlesSearchResponse(resp.data);
    } catch (e) {
      debugPrint('字幕搜索失败: $e');
      return [];
    }
  }

  /// 磁力/无内嵌资源的多级字幕匹配（结果按得分降序，已按 fileId 去重）。
  ///
  /// 查询优先级（命中即按 [goodEnoughScore] 提前返回，避免浪费免费下载额度）：
  /// 1. IMDb ID（最准，配合季集号）
  /// 2. 种子内视频文件名（release 名，如 `Show.S01E02.1080p.WEB-DL`）
  /// 3. 片名 + 季集号
  /// 4. 片名 + 年份
  /// 5. 片名（兜底）
  Future<List<SubtitleInfo>> searchBest({
    required String title,
    String? releaseName,
    String? imdbId,
    int? year,
  }) async {
    if (_userToken == null && !await init()) return [];
    final t = title.trim();
    if (t.isEmpty && (releaseName?.trim().isEmpty ?? true)) return [];

    final se = parseSeasonEpisode(releaseName ?? '');
    final targetSeason = se.season;
    final targetEpisode = se.episode;

    final queries = <String>[];
    void addQuery(String? q) {
      final v = q?.trim() ?? '';
      if (v.isEmpty) return;
      if (queries.any((e) => e.toLowerCase() == v.toLowerCase())) return;
      queries.add(v);
    }

    final imdb = imdbId?.trim() ?? '';
    if (imdb.startsWith('tt')) {
      addQuery(imdb);
    }
    addQuery(releaseName == null ? null : _cleanReleaseName(releaseName));
    if (targetEpisode > 0) {
      addQuery('$t S${_pad2(targetSeason)}E${_pad2(targetEpisode)}');
    }
    if (year != null && year > 1900) addQuery('$t $year');
    addQuery(t);

    final merged = <int, SubtitleInfo>{};
    for (final q in queries) {
      List<SubtitleInfo> list;
      if (q.startsWith('tt')) {
        list = await _searchRaw({'imdb_id': q, 'languages': chineseLanguages});
        // IMDb 查询不带季集号时结果可能跨季，补一次带季集号的。
        if (targetEpisode > 0) {
          final withEp = await _searchRaw({
            'imdb_id': q,
            'languages': chineseLanguages,
            'season_number': '$targetSeason',
            'episode_number': '$targetEpisode',
          });
          list = [...withEp, ...list];
        }
      } else {
        list = await searchByName(q);
      }

      for (final s in list) {
        final score = _scoreFor(
          s,
          title: t,
          releaseName: releaseName,
          targetSeason: targetSeason,
          targetEpisode: targetEpisode,
          matchedByImdb: q.startsWith('tt'),
        );
        final id = s.fileId;
        if (id == null) continue;
        final old = merged[id];
        if (old == null || score > old.score) {
          merged[id] = s.copyWith(score: score);
        }
      }

      if (merged.values.any((s) => s.score >= goodEnoughScore)) break;
    }

    final out = merged.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  /// 得分达到该值视为「够准」，不再继续打后续查询（省额度）。
  static const int goodEnoughScore = 150;

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  /// 去掉扩展名与路径，把 `Show.S01E02.1080p` 变成 `Show S01E02 1080p`。
  static String _cleanReleaseName(String raw) {
    var s = raw.replaceAll('\\', '/');
    if (s.contains('/')) s = s.split('/').last;
    s = s.replaceAll(
      RegExp(
        r'\.(mp4|mkv|avi|mov|ts|m2ts|rmvb|wmv|flv)$',
        caseSensitive: false,
      ),
      '',
    );
    return s.replaceAll(RegExp(r'[._]'), ' ').trim();
  }

  Future<List<SubtitleInfo>> _searchRaw(Map<String, String> query) async {
    try {
      final dio = await _getDio();
      final resp = await dio.get(
        '$_baseUrl/subtitles',
        queryParameters: query,
        options: Options(
          headers: {
            'Api-Key': _apiKey,
            'Authorization': 'Bearer $_userToken',
          },
        ),
      );
      return _parseSubtitlesSearchResponse(resp.data);
    } catch (e) {
      debugPrint('字幕查询失败($query): $e');
      return [];
    }
  }

  /// 单条字幕与当前资源的匹配得分。
  int _scoreFor(
    SubtitleInfo s, {
    required String title,
    String? releaseName,
    required int targetSeason,
    required int targetEpisode,
    required bool matchedByImdb,
  }) {
    var score = 0;

    // 语言：简中优先，其次繁中/通用中文
    final lang = s.language.toLowerCase();
    if (lang.contains('zh-cn') || lang.contains('zho') || lang == 'zh') {
      score += 100;
    } else if (lang.contains('zh-tw')) {
      score += 80;
    } else if (lang.contains('zh')) {
      score += 65;
    }

    // release 名 / 字幕文件名 与种子文件名的 token 重合度
    if (releaseName != null && releaseName.trim().isNotEmpty) {
      final byRelease = tokenOverlap(s.releaseName, releaseName);
      final byFile = tokenOverlap(s.fileName, releaseName);
      final overlap = byRelease > byFile ? byRelease : byFile;
      score += (overlap * 60).round();
    }

    // 片名命中（兜底查询时尤其重要）
    final titleOverlap = tokenOverlap('${s.releaseName} ${s.fileName}', title);
    score += (titleOverlap * 25).round();

    // 季集号：对齐加分、错位重罚
    if (targetEpisode > 0) {
      if (s.episode == targetEpisode &&
          (targetSeason == 0 || s.season == 0 || s.season == targetSeason)) {
        score += 60;
      } else if (s.episode > 0 && s.episode != targetEpisode) {
        score -= 60;
      } else if (s.season > 0 && targetSeason > 0 && s.season != targetSeason) {
        score -= 30;
      }
    } else if (s.episode > 0) {
      // 目标是电影却拿到分集字幕，轻微扣分
      score -= 10;
    }

    if (matchedByImdb) score += 30;

    // 下载量（对数缩放，最多 +15）
    if (s.downloadsCount > 0) {
      score += (log(s.downloadsCount + 1) / ln10 * 7).round().clamp(0, 15);
    }
    return score;
  }

  /// 搜索字幕（按文件 Hash）
  Future<List<SubtitleInfo>> searchByHash(
    String fileHash, {
    String languages = chineseLanguages,
  }) async {
    if (_userToken == null && !await init()) return [];
    if (fileHash.trim().isEmpty) return [];

    try {
      final dio = await _getDio();
      final resp = await dio.get(
        '$_baseUrl/subtitles',
        queryParameters: {
          'moviehash': fileHash.trim(),
          'languages': languages,
        },
        options: Options(
          headers: {
            'Api-Key': _apiKey,
            'Authorization': 'Bearer $_userToken',
          },
        ),
      );
      return _parseSubtitlesSearchResponse(resp.data);
    } catch (e) {
      debugPrint('字幕Hash搜索失败: $e');
      return [];
    }
  }

  /// 下载字幕到本地，返回文件路径。
  Future<String?> downloadSubtitle(int fileId) async {
    if (_userToken == null && !await init()) return null;

    // Web 端无本地文件系统（path_provider 不支持），外挂字幕文件下载不可用；
    // 走 [downloadAndParse] 的直取文本分支仍可工作。
    if (kIsWeb) {
      debugPrint('Web 端暂不支持字幕文件下载到本地');
      return null;
    }

    try {
      final dio = await _getDio();
      final resp = await dio.post(
        '$_baseUrl/download',
        data: jsonEncode({'file_id': fileId}),
        options: Options(
          headers: {
            'Api-Key': _apiKey,
            'Authorization': 'Bearer $_userToken',
            'Content-Type': 'application/json',
          },
        ),
      );

      final downloadUrl = _extractDownloadLink(resp.data);
      if (downloadUrl == null) {
        debugPrint('字幕下载: 响应中无有效 link: ${resp.data}');
        return null;
      }

      // 使用临时目录来存储字幕文件，避免权限问题
      final tempDir = await getTemporaryDirectory();
      final subtitleDir = '${tempDir.path}/movie_app/subtitles';
      await Directory(subtitleDir).create(recursive: true);
      final filePath = '$subtitleDir/subtitle_$fileId.srt';

      // 同一 fileId 已下载过则直接复用，避免重复消耗免费额度。
      final cached = File(filePath);
      if (await cached.exists() && await cached.length() > 0) {
        return filePath;
      }

      await dio.download(downloadUrl, filePath);
      if (!await File(filePath).exists() ||
          await File(filePath).length() == 0) {
        debugPrint('字幕下载: 文件为空 $filePath');
        return null;
      }
      return filePath;
    } catch (e) {
      debugPrint('字幕下载失败: $e');
      return null;
    }
  }

  Future<List<SubtitleEntry>> parseSrtFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];
      final content = await file.readAsString(encoding: utf8);
      return _parseSrt(content);
    } catch (e) {
      debugPrint('解析字幕文件失败: $e');
      return [];
    }
  }

  List<SubtitleEntry> _parseSrt(String content) {
    final entries = <SubtitleEntry>[];
    final blocks = content.trim().split('\n\n');

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 3) continue;

      final timeMatch = RegExp(
        r'(\d{2}):(\d{2}):(\d{2}),(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2}),(\d{3})',
      ).firstMatch(lines[1]);

      if (timeMatch == null) continue;

      int? msFromMatch(RegExpMatch m, int startGroup) {
        final a = int.tryParse(m.group(startGroup) ?? '');
        final b = int.tryParse(m.group(startGroup + 1) ?? '');
        final c = int.tryParse(m.group(startGroup + 2) ?? '');
        final d = int.tryParse(m.group(startGroup + 3) ?? '');
        if (a == null || b == null || c == null || d == null) return null;
        return a * 3600000 + b * 60000 + c * 1000 + d;
      }

      final startMs = msFromMatch(timeMatch, 1);
      final endMs = msFromMatch(timeMatch, 5);
      if (startMs == null || endMs == null) continue;

      final text = lines.sublist(2).join('\n').trim();

      if (text.isNotEmpty) {
        entries.add(
          SubtitleEntry(
            startTimeMs: startMs,
            endTimeMs: endMs,
            text: text,
          ),
        );
      }
    }

    return entries;
  }

  Future<String> getSubtitleCacheDir() async {
    // Web 端无本地文件系统，返回空路径
    if (kIsWeb) return '';
    // 使用临时目录来存储字幕文件，避免权限问题
    final tempDir = await getTemporaryDirectory();
    final dir = '${tempDir.path}/movie_app/subtitles';
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// 下载并返回 SRT 文本（自动匹配 / 手动选用）。
  Future<String?> downloadAndParse(SubtitleInfo info) async {
    if (_userToken == null && !await init()) return null;

    try {
      if (info.fileId != null && info.fileId! > 0) {
        final path = await downloadSubtitle(info.fileId!);
        if (path == null) return null;
        final file = File(path);
        if (!await file.exists()) return null;
        final result = await file.readAsString(encoding: utf8);
        if (!result.contains('-->')) return null;
        return result;
      }

      if (info.downloadUrl.startsWith('http')) {
        final dio = await _getDio();
        final resp = await dio.get(
          info.downloadUrl,
          options: Options(responseType: ResponseType.plain),
        );
        final result = resp.data.toString();
        if (!result.contains('-->')) return null;
        return result;
      }
      return null;
    } catch (e) {
      debugPrint('字幕下载解析失败: $e');
      return null;
    }
  }
}

class SubtitleEntry {
  final int startTimeMs;
  final int endTimeMs;
  final String text;

  const SubtitleEntry({
    required this.startTimeMs,
    required this.endTimeMs,
    required this.text,
  });

  SubtitleEntry offset(int offsetMs) {
    return SubtitleEntry(
      startTimeMs: startTimeMs + offsetMs,
      endTimeMs: endTimeMs + offsetMs,
      text: text,
    );
  }
}
