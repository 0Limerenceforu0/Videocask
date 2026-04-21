import 'dart:convert';
import 'dart:io';
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

  const SubtitleInfo({
    required this.fileName,
    required this.downloadUrl,
    this.fileId,
    required this.language,
    required this.downloadsCount,
    required this.releaseName,
  });
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
        out.add(
          SubtitleInfo(
            fileName: fn,
            downloadUrl: '',
            fileId: id,
            language: lang,
            downloadsCount: downloads,
            releaseName: releaseName,
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

      await dio.download(downloadUrl, filePath);
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
