import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../models/movie.dart';
import 'api_service.dart';
import 'douban_lookup_service.dart';
import 'imdb_lookup_service.dart';
import 'storage_service.dart';
import 'tmdb_lookup_service.dart';

/// 中文 / 多语言片名 → 英文片名 + IMDb `tt`，供磁力搜索对齐。
class VideoTitleResolveService {
  VideoTitleResolveService._();
  static final VideoTitleResolveService instance = VideoTitleResolveService._();

  static final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');

  /// 解析顺序：直接 `tt` → CMS 别名 → 豆瓣 → TMDB（需 Key）→ IMDb 联想。
  Future<VideoTitleResolveResult?> resolve(
    String primaryTitle, {
    String? year,
    String? alias,
  }) async {
    final direct = ImdbLookupService.parseImdbIdFromText(primaryTitle);
    if (direct != null) {
      return VideoTitleResolveResult(
        imdbId: direct,
        englishTitle: null,
        localTitle: null,
        year: year,
        source: VideoTitleResolveSource.directImdb,
      );
    }

    final primary = ImdbLookupService.cleanTitleForLookup(primaryTitle);
    if (primary.isEmpty) return null;

    final aliasClean = ImdbLookupService.cleanTitleForLookup(alias ?? '');
    final yearHint = (year?.trim().isNotEmpty == true)
        ? year!.trim()
        : ImdbLookupService.yearFromUserQuery(primaryTitle);

    String? englishTitle;
    String? localTitle;
    String? resolvedDoubanId;
    var resolvedYear = yearHint;
    var source = VideoTitleResolveSource.none;

    if (aliasClean.isNotEmpty && !_cjkPattern.hasMatch(aliasClean)) {
      englishTitle = aliasClean;
      source = VideoTitleResolveSource.cmsAlias;
    }

    if (_cjkPattern.hasMatch(primary)) {
      localTitle = primary;
      final douban = await DoubanLookupService.instance.suggest(
        primary,
        year: resolvedYear,
      );
      if (douban != null) {
        localTitle = douban.title;
        resolvedDoubanId = douban.doubanId;
        if (douban.englishTitle.isNotEmpty) {
          englishTitle = douban.englishTitle;
        }
        if (resolvedYear == null || resolvedYear.isEmpty) {
          resolvedYear = douban.year;
        }
        source = VideoTitleResolveSource.douban;
      }
    }

    String? imdbId;
    final tmdbKey =
        StorageService().getSetting(AppConstants.keyTmdbApiKey)?.trim() ?? '';
    if (tmdbKey.isNotEmpty) {
      final tmdb = await TmdbLookupService.instance.resolve(
        primary,
        apiKey: tmdbKey,
        year: resolvedYear,
        englishHint: englishTitle,
      );
      if (tmdb != null) {
        imdbId = tmdb.imdbId;
        if (tmdb.englishTitle.isNotEmpty) englishTitle = tmdb.englishTitle;
        if (tmdb.year.isNotEmpty) resolvedYear = tmdb.year;
        source = VideoTitleResolveSource.tmdb;
      }
    }

    if (imdbId == null) {
      final imdbQuery = englishTitle ?? primary;
      imdbId = await ImdbLookupService.instance.resolveForVideoTitle(
        imdbQuery,
        year: resolvedYear,
        alias: _cjkPattern.hasMatch(primary) ? primary : aliasClean,
      );
      if (imdbId != null) {
        source = source == VideoTitleResolveSource.none
            ? VideoTitleResolveSource.imdbSuggest
            : VideoTitleResolveSource.merged;
      }
    }

    if (imdbId == null && (englishTitle == null || englishTitle.isEmpty)) {
      // 2026-10-24：最后一道兜底 —— 用 **CMS 采集站自己的搜索结果**取英文别名。
      //
      // 为什么需要：豆瓣 / TMDB / IMDb 三条路在部分网络环境下会**全不通**
      // （用户实测搜「教父」时磁力资源模块直接没了）。三条都不通时
      // resolve 返回 null → 回退查询是中文字幕 → 磁力源（英文索引）搜不到
      // → 结果为空 → 磁力模块消失。
      // 而 CMS 是 App 自己的数据源，必定可达；它的列表项带英文别名
      // （`Movie.alias`），正好就是磁力源需要的检索词。
      final cmsAlias = await _resolveEnglishAliasFromCms(primary);
      if (cmsAlias != null && cmsAlias.isNotEmpty) {
        englishTitle = cmsAlias;
        source = VideoTitleResolveSource.cmsAlias;
        debugPrint('CMS 别名兜底解析: $primaryTitle -> $cmsAlias');
      }
    }

    if (imdbId == null && (englishTitle == null || englishTitle.isEmpty)) {
      return null;
    }

    if (imdbId != null || englishTitle != null) {
      debugPrint(
        '片名解析 [$source]: $primaryTitle -> '
        'tt=${imdbId ?? "-"} en=${englishTitle ?? "-"}',
      );
    }

    return VideoTitleResolveResult(
      imdbId: imdbId,
      englishTitle: englishTitle,
      localTitle: localTitle,
      year: resolvedYear,
      source: source,
      doubanId: resolvedDoubanId,
    );
  }

  /// CMS 兜底：按片名搜一次采集站，取最佳匹配项的英文别名。
  ///
  /// 只在豆瓣 / TMDB / IMDb 全部失败后调用（此时没有别的英文名可用）。
  /// 失败、超时、采集站没配源、无匹配，一律返回 null（不抛）——
  /// 这条路只是兜底，绝不能反过来把整个解析搞崩。
  Future<String?> _resolveEnglishAliasFromCms(String title) async {
    final q = title.trim();
    if (q.isEmpty) return null;
    try {
      final movies = await ApiService()
          .searchMovies(q, page: 1, maxPages: 1)
          .timeout(const Duration(seconds: 6));
      if (movies.isEmpty) return null;
      // 优先取片名完全一致的那条，否则取第一条（源站搜索已按相关度排序）。
      Movie? best;
      for (final m in movies) {
        if (m.name.trim() == q) {
          best = m;
          break;
        }
        best ??= m;
      }
      final alias = best?.alias.trim() ?? '';
      // 别名必须是非中文的英文名，否则对磁力源没有检索价值。
      if (alias.isEmpty || _cjkPattern.hasMatch(alias)) return null;
      return alias;
    } catch (e) {
      debugPrint('CMS 别名兜底失败 ($q): $e');
      return null;
    }
  }
}

enum VideoTitleResolveSource {
  none,
  directImdb,
  cmsAlias,
  douban,
  tmdb,
  imdbSuggest,
  merged,
}

class VideoTitleResolveResult {
  final String? imdbId;
  final String? englishTitle;

  /// 中文显示名（豆瓣 / 用户输入）
  final String? localTitle;
  final String? year;
  final VideoTitleResolveSource source;

  /// 命中豆瓣时回传的豆瓣条目 id，供磁力详情页补中文简介 / 主创。
  final String? doubanId;

  const VideoTitleResolveResult({
    required this.imdbId,
    required this.englishTitle,
    this.localTitle,
    required this.year,
    required this.source,
    this.doubanId,
  });
}
