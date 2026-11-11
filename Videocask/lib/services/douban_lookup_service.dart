import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 豆瓣联想接口（无需 API Key），用于中文片名 → 英文副标题 / 年份。
class DoubanLookupService {
  DoubanLookupService._();
  static final DoubanLookupService instance = DoubanLookupService._();

  static final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');
  static final RegExp _fourDigitYear = RegExp(r'^(?:19|20)\d{2}$');

  /// 是否为可比较的 4 位年份（1900~2099）；空串 / 区间年份（如 `2021-2022`）
  /// 都不参与「年份否决」。
  static bool _isFourDigitYear(String s) => _fourDigitYear.hasMatch(s);

  /// 候选年份与年份提示是否**明确冲突**（双方都是 4 位年份，且相差超过 1 年）。
  ///
  /// 留 1 年容差：豆瓣的 `year` 是上映年，release 名里的年份常是制作年，
  /// 电影节首映 / 不同地区上映会差 1 年；一刀切会误杀正确条目。
  /// 任一方缺失或不可解析时返回 false —— 豆瓣剧集常缺 `year`，不能因此误杀。
  static bool _yearConflict(DoubanSuggestMatch item, String? yearHint) {
    final hint = yearHint?.trim() ?? '';
    final itemYear = item.year.trim();
    if (!_isFourDigitYear(hint) || !_isFourDigitYear(itemYear)) return false;
    final diff = int.parse(hint) - int.parse(itemYear);
    return diff.abs() > 1;
  }

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
      var rejectedByYear = 0;
      final yearHint = year?.trim();
      final hintText = (yearHint == null || yearHint.isEmpty)
          ? ''
          : ' [年份提示=$yearHint]';

      for (final raw in data) {
        if (raw is! Map) continue;
        final parsed = parseSuggestItem(raw);
        if (parsed == null) continue;
        if (_yearConflict(parsed, yearHint)) {
          rejectedByYear++;
          continue;
        }
        final score = _scoreMatch(parsed, q, yearHint);
        if (score > bestScore) {
          bestScore = score;
          best = parsed;
        }
      }

      if (best != null && bestScore >= 80) {
        // 把年份提示一并打出来：否则「年份否决到底有没有生效」在真机上无法核对
        // （2026-11-11 就是靠这条日志才发现 `Hi Mom` 撞了 1970 的同名片）。
        debugPrint(
          '豆瓣解析: $q$hintText'
          ' -> ${best.englishTitle.isNotEmpty ? best.englishTitle : best.title} (${best.year})',
        );
        return best;
      }
      if (rejectedByYear > 0) {
        debugPrint(
          '豆瓣解析: $q$hintText 候选年份全部不一致，已否决 $rejectedByYear 条'
          '（宁可无补全，也不贴错片）',
        );
      } else if (best != null) {
        debugPrint(
          '豆瓣解析未达门槛: $q$hintText'
          ' 最高分=${bestScore.toStringAsFixed(0)} (${best.title}/${best.year})',
        );
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
    // 年份硬约束（2026-11-11 实机根因）：旧实现只给「年份命中 +110」，
    // 但对「年份明确不一致」没有任何惩罚 —— `Hi Mom`（2021）撞上 1970 年的
    // 同名短片 `Hi, Mom!` 时，靠分词各命中一个词就能拿到 145 分过门槛，
    // 于是豆瓣把 1970 的条目当成匹配项塞进补全链路（`豆瓣解析: Hi Mom ->
    // Hi, Mom! (1970)`）。与 IMDb 侧同一口径：双方都是 4 位年份且不等时
    // 直接判为「不是同一部片」，避免把错片海报/主创贴到详情页。
    if (_yearConflict(item, yearHint)) return 0;

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
    // 走到这里说明年份要么一致、要么有一方缺失；一致时给硬证据加分。
    final hintYear = yearHint?.trim() ?? '';
    if (hintYear.isNotEmpty && item.year.trim() == hintYear) {
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
