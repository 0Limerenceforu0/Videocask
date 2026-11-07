import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 豆瓣联想接口（无需 API Key），用于中文片名 → 英文副标题 / 年份。
class DoubanLookupService {
  DoubanLookupService._();
  static final DoubanLookupService instance = DoubanLookupService._();

  static final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 12),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://movie.douban.com/',
        'Accept': 'application/json,*/*;q=0.8',
      },
    ),
  );

  /// 按片名联想；返回最佳匹配的英文副标题（sub_title）与年份。
  ///
  /// **中英文查询都支持**（2026-10-25 实测）：豆瓣联想接口对英文片名
  /// 同样返回结果，且 `title` 字段是**中文片名**、`sub_title` 是英文名 ——
  /// `q=Shawshank` → `{title: 肖申克的救赎, sub_title: The Shawshank Redemption, year: 1994}`。
  /// 这条路径让「搜英文片名」也能拿到中文名（磁力资源全是英文发布名，
  /// 搜索页要显示中文名就靠它）。
  Future<DoubanSuggestMatch?> suggest(
    String query, {
    String? year,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return null;

    try {
      final url = Uri.parse(
        'https://movie.douban.com/j/subject_suggest?q=${Uri.encodeComponent(q)}',
      );
      final resp = await _dio.get<dynamic>(url.toString());
      final data = resp.data;
      if (data is! List || data.isEmpty) return null;

      DoubanSuggestMatch? best;
      var bestScore = 0.0;
      final yearHint = year?.trim();

      for (final raw in data) {
        if (raw is! Map) continue;
        final parsed = parseSuggestItem(raw);
        if (parsed == null) continue;
        final score = _scoreMatch(parsed, q, yearHint);
        if (score > bestScore) {
          bestScore = score;
          best = parsed;
        }
      }

      if (best != null && bestScore >= 80) {
        debugPrint(
          '豆瓣解析: $q -> ${best.englishTitle.isNotEmpty ? best.englishTitle : best.title} (${best.year})',
        );
        return best;
      }
    } catch (e) {
      debugPrint('豆瓣联想失败 ($q): $e');
    }
    return null;
  }

  /// 供单元测试使用的条目解析。
  @visibleForTesting
  static DoubanSuggestMatch? parseSuggestItem(Map<dynamic, dynamic> raw) {
    final title = raw['title']?.toString().trim() ?? '';
    if (title.isEmpty) return null;
    final sub = raw['sub_title']?.toString().trim() ?? '';
    final year = raw['year']?.toString().trim() ?? '';
    final id = raw['id']?.toString().trim() ?? '';
    final type = raw['type']?.toString().trim() ?? '';
    return DoubanSuggestMatch(
      title: title,
      englishTitle: sub,
      year: year,
      doubanId: id,
      type: type,
    );
  }

  /// 供单元测试使用的打分入口。
  @visibleForTesting
  static double scoreMatchForTest(
    DoubanSuggestMatch item,
    String query,
    String? yearHint,
  ) =>
      _scoreMatch(item, query, yearHint);

  static double _scoreMatch(
    DoubanSuggestMatch item,
    String query,
    String? yearHint,
  ) {
    var s = 0.0;
    final qn = query.toLowerCase();
    // 中文查询比中文名，英文查询比英文副标题（`sub_title`）。
    // 2026-10-25：原实现只比 `title`，英文查询会全部判不相关 → 恒返回 null。
    final isCjkQuery = _cjkPattern.hasMatch(query);
    final tn = (isCjkQuery ? item.title : item.englishTitle).toLowerCase();
    if (tn.isEmpty) return 0;
    if (tn == qn) {
      s += 220;
    } else if (tn.contains(qn) || qn.contains(tn)) {
      s += 130;
    } else {
      final qt = qn.split(RegExp(r'[\s·《》]+')).where((e) => e.length > 1);
      for (final t in qt) {
        if (tn.contains(t)) s += 40;
      }
    }
    final yh = yearHint ?? '';
    if (yh.length == 4 && item.year == yh) {
      s += 110;
    }
    // 英文查询命中英文副标题时，`title` 就是中文名 —— 额外加分。
    if (!isCjkQuery && item.title.isNotEmpty) s += 25;
    if (item.englishTitle.isNotEmpty) s += 25;
    if (item.type == 'movie' || item.type == 'tv') s += 15;
    return s;
  }

  /// 抓取豆瓣条目详情页，解析中文剧情简介 + 导演 / 主演 / 类型 / 地区 / 年份。
  ///
  /// 无需 API Key，作为 TMDB 缺失时的中文兜底（豆瓣在大陆可达）。
  /// 任何解析失败 / 反爬页 → 返回 null（绝不抛）。
  Future<DoubanSubjectDetail?> getSubject(String doubanId) async {
    final id = doubanId.trim();
    if (id.isEmpty) return null;
    try {
      final url = Uri.parse('https://movie.douban.com/subject/$id/');
      final resp = await _dio.get<dynamic>(url.toString());
      final html = resp.data is String ? resp.data as String : null;
      if (html == null || html.isEmpty) return null;
      return parseSubject(html);
    } catch (e) {
      debugPrint('豆瓣条目抓取失败 ($id): $e');
      return null;
    }
  }

  /// 解析豆瓣条目 HTML（运行期与单元测试共用）。
  @visibleForTesting
  static DoubanSubjectDetail? parseSubject(String html) {
    if (html.isEmpty) return null;

    // 剧情简介：优先完整版（class="all hidden"），否则取可见摘要段。
    final allHidden = _firstGroup(
      html,
      RegExp(r'<span class="all hidden">(.*?)</span>', dotAll: true),
    );
    final visible = _firstGroup(
      html,
      RegExp(r'<span property="v:summary"[^>]*>(.*?)</span>', dotAll: true),
    );
    final rawSummary =
        (allHidden != null && allHidden.trim().isNotEmpty) ? allHidden : (visible ?? '');
    final summary = _stripTags(rawSummary)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final cleanSummary = summary.isNotEmpty ? summary : null;

    final genres = <String>[];
    for (final m
        in RegExp(r'<span property="v:genre">(.*?)</span>', dotAll: true)
            .allMatches(html)) {
      final g = _stripTags(m.group(1) ?? '').trim();
      if (g.isNotEmpty && !genres.contains(g)) genres.add(g);
    }

    final director = _parseRelName(html, 'v:directedBy');
    final actors = _parseRelNames(html, 'v:starring', 8);

    String? region;
    final regionM =
        RegExp(r'制片国家/地区:</span>\s*([^<]+)').firstMatch(html);
    if (regionM != null) {
      region = regionM
          .group(1)!
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll('/', ' / ')
          .trim();
    }

    String? year;
    final yearM = RegExp(
      r'<span property="v:initialReleaseDate"[^>]*content="(\d{4})',
    ).firstMatch(html);
    if (yearM != null) {
      year = yearM.group(1);
    } else {
      final y2 = RegExp(r'<span class="year">\s*\(?(\d{4})').firstMatch(html);
      year = y2?.group(1);
    }

    if (cleanSummary == null &&
        genres.isEmpty &&
        director.isEmpty &&
        actors.isEmpty &&
        (region == null || region.isEmpty) &&
        (year == null || year.isEmpty)) {
      return null;
    }
    return DoubanSubjectDetail(
      summary: cleanSummary,
      genres: genres,
      director: director,
      actors: actors,
      region: region ?? '',
      year: year ?? '',
    );
  }

  static String? _firstGroup(String html, RegExp re) {
    final m = re.firstMatch(html);
    return m?.group(1);
  }

  static String _stripTags(String s) =>
      s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').trim();

  static String _parseRelName(String html, String rel) {
    final m = RegExp('<a[^>]*rel="$rel"[^>]*>(.*?)</a>', dotAll: true)
        .firstMatch(html);
    if (m == null) return '';
    return _stripTags(m.group(1) ?? '').trim();
  }

  static List<String> _parseRelNames(String html, String rel, int limit) {
    final out = <String>[];
    final re = RegExp('<a[^>]*rel="$rel"[^>]*>(.*?)</a>', dotAll: true);
    for (final m in re.allMatches(html)) {
      final n = _stripTags(m.group(1) ?? '').trim();
      if (n.isNotEmpty && !out.contains(n)) out.add(n);
      if (out.length >= limit) break;
    }
    return out;
  }
}

/// 豆瓣条目详情：中文剧情简介 + 主创 / 类型 / 地区 / 年份。
class DoubanSubjectDetail {
  final String? summary;
  final List<String> genres;
  final String director;
  final List<String> actors;
  final String region;
  final String year;

  const DoubanSubjectDetail({
    this.summary,
    this.genres = const [],
    this.director = '',
    this.actors = const [],
    this.region = '',
    this.year = '',
  });
}

class DoubanSuggestMatch {
  final String title;
  final String englishTitle;
  final String year;
  final String doubanId;
  final String type;

  const DoubanSuggestMatch({
    required this.title,
    required this.englishTitle,
    required this.year,
    required this.doubanId,
    required this.type,
  });
}
