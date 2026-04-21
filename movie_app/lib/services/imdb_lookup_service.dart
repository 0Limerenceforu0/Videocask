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
    if (c.isNotEmpty) queries.add(c);
    final a = cleanTitleForLookup(alias ?? '');
    if (a.isNotEmpty && a != c) queries.add(a);

    String? bestId;
    double bestScore = 0;

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
        }
      } catch (e) {
        debugPrint('IMDb 联想失败 ($q): $e');
      }
    }

    if (bestId != null && bestScore >= 72) {
      debugPrint('IMDb 解析: $primaryTitle -> $bestId (score=$bestScore)');
      return bestId;
    }
    return null;
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
    if (c.isNotEmpty) queries.add(c);
    final a = cleanTitleForLookup(alias ?? '');
    if (a.isNotEmpty && a != c) queries.add(a);

    Map<String, dynamic>? bestItem;
    double bestScore = 0;

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
        }
      } catch (e) {
        debugPrint('IMDb 补全失败 ($q): $e');
      }
    }

    if (bestItem == null || bestScore < 65) return null;

    final id = bestItem['id']!.toString().toLowerCase();
    final label = bestItem['l']?.toString() ?? '';
    if (label.isEmpty) return null;

    String? poster;
    final img = bestItem['i'];
    if (img is Map) {
      poster = img['imageUrl']?.toString();
    }

    final iy = bestItem['y'];
    final yearStr = iy is int ? '$iy' : (iy?.toString() ?? '');
    final starring = bestItem['s']?.toString();

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
