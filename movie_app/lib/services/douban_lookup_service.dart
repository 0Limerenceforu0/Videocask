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
  Future<DoubanSuggestMatch?> suggest(
    String query, {
    String? year,
  }) async {
    final q = query.trim();
    if (q.isEmpty || !_cjkPattern.hasMatch(q)) return null;

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

  static double _scoreMatch(
    DoubanSuggestMatch item,
    String query,
    String? yearHint,
  ) {
    var s = 0.0;
    final qn = query.toLowerCase();
    final tn = item.title.toLowerCase();
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
    if (item.englishTitle.isNotEmpty) s += 25;
    if (item.type == 'movie' || item.type == 'tv') s += 15;
    return s;
  }
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
