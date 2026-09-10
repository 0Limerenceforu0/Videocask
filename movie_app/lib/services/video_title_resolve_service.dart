import 'package:flutter/foundation.dart';

import '../config/constants.dart';
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
    );
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

  const VideoTitleResolveResult({
    required this.imdbId,
    required this.englishTitle,
    this.localTitle,
    required this.year,
    required this.source,
  });
}
