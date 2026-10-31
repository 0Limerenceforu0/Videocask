import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 通过 IMDb 官方站点使用的联想接口，将片名解析为 `ttxxxxxxx`（无需 API Key）。
///
/// 仅用于「影视」磁力对齐；游戏、软件名在 IMDb 中通常无条目，解析会失败并交由调用方回退为片名搜索。
class ImdbLookupService {
  ImdbLookupService._();
  static final ImdbLookupService instance = ImdbLookupService._();

  static final RegExp _imdbIdPattern =
      RegExp(r'\b(tt\d{7,12})\b', caseSensitive: false);

  static final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 12),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json,*/*;q=0.8',
      },
    ),
  );

  /// 从用户输入里抽四位年份（如「黑客帝国 1999」），辅助 IMDb 打分。
  static String? yearFromUserQuery(String text) {
    final m = RegExp(r'\b(19|20)\d{2}\b').firstMatch(text.trim());
    return m?.group(0);
  }

  /// 从任意字符串中提取 IMDb ID（用户直接搜 `tt1234567` 时走短路）。
  static String? parseImdbIdFromText(String text) {
    final m = _imdbIdPattern.firstMatch(text.trim());
    return m?.group(1)?.toLowerCase();
  }

  /// 去掉版本号、乱码数字片段，便于联想（如游戏 `Stationeers v0.2.xxxx` → `Stationeers`）。
  static String cleanTitleForLookup(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    s = s.replaceAll(RegExp(r'\bv\d+[\w.]*\b', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'\b\d+\.\d+\.\d+[\w.]*\b'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static String _suggestionPathPrefix(String query) {
    if (query.isEmpty) return 'x';
    final c = query.substring(0, 1).toLowerCase().codeUnitAt(0);
    if (c >= 0x61 && c <= 0x7a) {
      return String.fromCharCode(c);
    }
    return 'x';
  }

  /// 将主标题 / 别名解析为最佳匹配的 IMDb ID；失败返回 null（应回退为片名搜磁力）。
  Future<String?> resolveForVideoTitle(
    String primaryTitle, {
    String? year,
    String? alias,
  }) async {
    final direct = parseImdbIdFromText(primaryTitle);
    if (direct != null) return direct;

    final y = year?.trim();
    final queries = <String>[];
    final c = cleanTitleForLookup(primaryTitle);
    final a = cleanTitleForLookup(alias ?? '');
    // 中文主标题在 IMDb 联想接口命中率低，优先用 CMS 英文别名检索
    if (_cjkPattern.hasMatch(c) && a.isNotEmpty && !_cjkPattern.hasMatch(a)) {
      queries.add(a);
      if (c.isNotEmpty && c != a) queries.add(c);
    } else {
      if (c.isNotEmpty) queries.add(c);
      if (a.isNotEmpty && a != c) queries.add(a);
    }

    String? bestId;
    double bestScore = 0;

    // 片名本身对上的候选（`战狼` vs `War Wolf` 这种跨语言不算）。
    //
    // 为什么单独记（2026-10-28 真实接口数据实测）：中文查询在 IMDb 联想里
    // 几乎没有同文字标题命中，`_scoreCandidate` 会给**每一条**拉丁标题候选
    // 加 130 分「跨语言」分，此时排序实际上只剩「全球热度」一个变量 ——
    // 搜「我不是药神」时 Little Fockers（2010，rank 3943）拿 290 分，
    // 正确结果 Dying to Survive（2018，rank 24278）只有 278 分，于是整个
    // 磁力列表变成《Little Fockers》且贴上「我不是药神」的中文名。
    // 所以中文查询在没有年份命中时，只接受「标题真的对上」的候选。
    String? bestIdLabelMatched;
    double bestScoreLabelMatched = 0;

    // 年份命中的候选单独记一份。
    //
    // 为什么必须分开记（2026-10-28 真机实测）：搜「战狼」时 IMDb 联想返回
    // `Logan(2017)` 和 `Wolf Warrior(2015)`，豆瓣已给出正确年份 2015，但
    // `Logan` 靠"全球热度"加分拿到 401 分，压过"年份命中"的 258 分 →
    // 整个磁力列表全变成《金刚狼》且还贴上「战狼」中文名。
    // 年份是"同一部片"最硬的证据，绝不能被热度盖过去，所以这里做**硬优先**：
    // 只要存在达到阈值的年份命中候选，就只用它，不再看热度最高者。
    String? bestIdOnYear;
    double bestScoreOnYear = 0;

    for (final q in queries) {
      try {
        final url = Uri.parse(
          'https://v2.sg.media-imdb.com/suggestion/'
          '${_suggestionPathPrefix(q)}/'
          '${Uri.encodeComponent(q)}.json',
        );
        final resp = await _dio.get<dynamic>(url.toString());
        final data = resp.data;
        if (data is! Map) continue;
        final list = data['d'];
        if (list is! List) continue;

        for (final item in list) {
          if (item is! Map) continue;
          final id = item['id']?.toString() ?? '';
          if (!_isTitleId(id)) continue;

          final label = item['l']?.toString() ?? '';
          final qid = item['qid']?.toString() ?? '';
          final itemYear = item['y'] is int
              ? item['y'] as int
              : int.tryParse(item['y']?.toString() ?? '');
          final rank = (item['rank'] is num)
              ? (item['rank'] as num).toDouble()
              : double.tryParse(item['rank']?.toString() ?? '') ?? 999999;

          final score = _scoreCandidate(
            query: q,
            label: label,
            yearHint: y,
            itemYear: itemYear,
            qid: qid,
            rank: rank,
          );
          if (score > bestScore) {
            bestScore = score;
            bestId = id.toLowerCase();
          }
          final qn = q.toLowerCase().trim();
          final ln = label.toLowerCase().trim();
          final labelMatched = ln.isNotEmpty &&
              qn.isNotEmpty &&
              (ln == qn || ln.contains(qn) || qn.contains(ln));
          if (labelMatched && score > bestScoreLabelMatched) {
            bestScoreLabelMatched = score;
            bestIdLabelMatched = id.toLowerCase();
          }
          if (_yearMatches(y, itemYear) && score > bestScoreOnYear) {
            bestScoreOnYear = score;
            bestIdOnYear = id.toLowerCase();
          }
        }
      } catch (e) {
        debugPrint('IMDb 联想失败 ($q): $e');
      }
    }

    // 硬优先：年份命中者优先，其次才是热度最高者。
    //
    // 中文查询且没有年份命中时，热度分不可信（见 bestIdLabelMatched 的注释），
    // 只接受标题真的对上的候选；对不上就返回 null，让调用方回退片名搜索 ——
    // 宁可「没有磁力资源」，也不能把别的电影贴到这部片头上。
    final cjkQuery = _cjkPattern.hasMatch(primaryTitle);
    final chosenId = chooseCandidate(
      cjkQuery: cjkQuery,
      bestId: bestId,
      bestScore: bestScore,
      labelMatchedId: bestIdLabelMatched,
      labelMatchedScore: bestScoreLabelMatched,
      yearId: bestIdOnYear,
      yearScore: bestScoreOnYear,
      threshold: 72,
    );

    if (chosenId != null) {
      debugPrint(
        'IMDb 解析: $primaryTitle -> $chosenId '
        '(score=${chosenId == bestIdOnYear ? bestScoreOnYear : bestScore})',
      );
      return chosenId;
    }
    return null;
  }

  /// 中文查询的最终裁决：年份命中 > 标题命中 > （仅非中文查询）热度最高。
  ///
  /// 中文查询在 IMDb 联想里几乎拿不到同文字标题，热门候选会靠「跨语言 +130」
  /// 与「全球排名分」堆到 290 分左右，正确条目反而可能只有 278 分。
  /// 因此中文查询在没有年份命中时**只**接受标题对上的候选。
  @visibleForTesting
  static String? chooseCandidate({
    required bool cjkQuery,
    required String? bestId,
    required double bestScore,
    required String? labelMatchedId,
    required double labelMatchedScore,
    required String? yearId,
    required double yearScore,
    double threshold = 72,
  }) {
    final hasYearHit = yearId != null && yearScore >= threshold;
    final trustLabelHint = cjkQuery && !hasYearHit;
    return chooseId(
      bestId: trustLabelHint ? labelMatchedId : bestId,
      bestScore: trustLabelHint ? labelMatchedScore : bestScore,
      yearId: yearId,
      yearScore: yearScore,
      threshold: threshold,
    );
  }

  /// 在「热度最高」与「年份命中」之间做最终裁决；供回归测试直接驱动。
  ///
  /// 年份命中**优先**：热度是全球指标，和"是不是同一部片"无关；年份是硬约束。
  /// 只有年份命中侧没有任何候选达到阈值时，才退回热度最高者。
  @visibleForTesting
  static String? chooseId({
    required String? bestId,
    required double bestScore,
    required String? yearId,
    required double yearScore,
    required double threshold,
  }) {
    final useYearHit = yearId != null && yearScore >= threshold;
    final id = useYearHit ? yearId : bestId;
    final score = useYearHit ? yearScore : bestScore;
    if (id == null || score < threshold) return null;
    return id;
  }

  /// 年份是否构成"同一部片"的硬证据（仅在双方都是 4 位年份时成立）。
  static bool _yearMatches(String? yearHint, int? itemYear) {
    final yh = yearHint ?? '';
    return yh.length == 4 &&
        RegExp(r'^\d{4}$').hasMatch(yh) &&
        itemYear != null &&
        yh == itemYear.toString();
  }

  static bool _isTitleId(String id) =>
      RegExp(r'^tt\d{7,12}$', caseSensitive: false).hasMatch(id.trim());

  static double _scoreCandidate({
    required String query,
    required String label,
    String? yearHint,
    int? itemYear,
    required String qid,
    required double rank,
  }) {
    var s = 0.0;
    final qn = query.toLowerCase().trim();
    final ln = label.toLowerCase().trim();
    var tokenJaccard = 0.0;
    if (ln == qn) {
      s += 220;
    } else if (ln.contains(qn) || qn.contains(ln)) {
      s += 140;
    } else {
      final qt =
          qn.split(RegExp(r'[\s\-_.·]+')).where((e) => e.length > 1).toSet();
      final lt =
          ln.split(RegExp(r'[\s\-_.·]+')).where((e) => e.length > 1).toSet();
      if (qt.isNotEmpty && lt.isNotEmpty) {
        final inter = qt.intersection(lt).length;
        final uni = qt.union(lt).length;
        if (uni > 0) {
          tokenJaccard = inter / uni;
          s += 95 * tokenJaccard;
        }
      }
    }

    // 纯拉丁片名若与 IMDb 条目标题几乎无重合，多半是联想噪声（如游戏名撞 TV 剧），压低分数以免误解析。
    if (!_cjkPattern.hasMatch(query) &&
        !_cjkPattern.hasMatch(label) &&
        !ln.contains(qn) &&
        !qn.contains(ln) &&
        tokenJaccard < 0.2 &&
        qn.length >= 5) {
      s = s.clamp(0, 64);
    }

    final yh = yearHint ?? '';
    if (yh.length == 4 && RegExp(r'^\d{4}$').hasMatch(yh) && itemYear != null) {
      if (yh == itemYear.toString()) {
        s += 110;
      }
    }

    if (_cjkPattern.hasMatch(query) &&
        !_cjkPattern.hasMatch(label) &&
        (qid == 'movie' ||
            qid == 'tvSeries' ||
            qid == 'tvMiniSeries' ||
            qid == 'tvMovie')) {
      s += 130;
    }

    switch (qid) {
      case 'movie':
        s += 18;
        break;
      case 'tvSeries':
      case 'tvMiniSeries':
        s += 15;
        break;
      case 'tvMovie':
        s += 12;
        break;
      case 'video':
        s -= 55;
        break;
      case 'short':
        s -= 40;
        break;
    }

    s += (300 - (rank / 25).clamp(0, 280)).clamp(0, 300);
    return s;
  }

  /// IMDb 联想条目中可用于磁力详情页补全海报、主名、年份、主演行（接口无长剧情文案）。
  Future<ImdbMagnetEnrichment?> lookupEnrichmentForMagnetDetail(
    String primaryTitle, {
    String? year,
    String? alias,
  }) async {
    final y = year?.trim();
    final queries = <String>[];
    final c = cleanTitleForLookup(primaryTitle);
    final a = cleanTitleForLookup(alias ?? '');
    if (_cjkPattern.hasMatch(c) && a.isNotEmpty && !_cjkPattern.hasMatch(a)) {
      queries.add(a);
      if (c.isNotEmpty && c != a) queries.add(c);
    } else {
      if (c.isNotEmpty) queries.add(c);
      if (a.isNotEmpty && a != c) queries.add(a);
    }

    Map<String, dynamic>? bestItem;
    double bestScore = 0;
    // 年份命中硬优先（同 resolveForVideoTitle 的理由）。
    Map<String, dynamic>? bestItemOnYear;
    double bestScoreOnYear = 0;

    for (final q in queries) {
      try {
        final url = Uri.parse(
          'https://v2.sg.media-imdb.com/suggestion/'
          '${_suggestionPathPrefix(q)}/'
          '${Uri.encodeComponent(q)}.json',
        );
        final resp = await _dio.get<dynamic>(url.toString());
        final data = resp.data;
        if (data is! Map) continue;
        final list = data['d'];
        if (list is! List) continue;

        for (final raw in list) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final id = item['id']?.toString() ?? '';
          if (!_isTitleId(id)) continue;

          final label = item['l']?.toString() ?? '';
          final qid = item['qid']?.toString() ?? '';
          final itemYear = item['y'] is int
              ? item['y'] as int
              : int.tryParse(item['y']?.toString() ?? '');
          final rank = (item['rank'] is num)
              ? (item['rank'] as num).toDouble()
              : double.tryParse(item['rank']?.toString() ?? '') ?? 999999;

          final score = _scoreCandidate(
            query: q,
            label: label,
            yearHint: y,
            itemYear: itemYear,
            qid: qid,
            rank: rank,
          );
          if (score > bestScore) {
            bestScore = score;
            bestItem = item;
          }
          if (_yearMatches(y, itemYear) && score > bestScoreOnYear) {
            bestScoreOnYear = score;
            bestItemOnYear = item;
          }
        }
      } catch (e) {
        debugPrint('IMDb 补全失败 ($q): $e');
      }
    }

    // 年份命中的候选优先（阈值同为 65）。
    final chosenId = chooseId(
      bestId: bestItem?['id']?.toString(),
      bestScore: bestScore,
      yearId: bestItemOnYear?['id']?.toString(),
      yearScore: bestScoreOnYear,
      threshold: 65,
    );
    if (chosenId == null) return null;

    final Map<String, dynamic> picked =
        (chosenId == bestItemOnYear?['id']?.toString() ? bestItemOnYear : bestItem)!;

    final id = picked['id']!.toString().toLowerCase();
    final label = picked['l']?.toString() ?? '';
    if (label.isEmpty) return null;

    String? poster;
    final img = picked['i'];
    if (img is Map) {
      poster = img['imageUrl']?.toString();
    }

    final iy = picked['y'];
    final yearStr = iy is int ? '$iy' : (iy?.toString() ?? '');
    final starring = picked['s']?.toString();

    return ImdbMagnetEnrichment(
      imdbId: id,
      title: label,
      year: yearStr.isNotEmpty ? yearStr : null,
      posterUrl: poster,
      starringLine: starring != null && starring.trim().isNotEmpty
          ? starring.trim()
          : null,
    );
  }
}

/// 磁力详情页用 IMDb 联想补海报/主创等（无 API Key）。
class ImdbMagnetEnrichment {
  final String imdbId;
  final String title;
  final String? year;
  final String? posterUrl;
  final String? starringLine;

  const ImdbMagnetEnrichment({
    required this.imdbId,
    required this.title,
    this.year,
    this.posterUrl,
    this.starringLine,
  });
}
