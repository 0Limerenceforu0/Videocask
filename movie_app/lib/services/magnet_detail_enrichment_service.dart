import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../models/movie.dart';
import 'imdb_lookup_service.dart';
import 'storage_service.dart';
import 'tmdb_lookup_service.dart';
import 'video_title_resolve_service.dart';

/// 磁力详情页元数据补全：中文片名 → 海报 / 简介 / 演职员 / 相似推荐。
class MagnetDetailEnrichmentService {
  MagnetDetailEnrichmentService._();
  static final MagnetDetailEnrichmentService instance =
      MagnetDetailEnrichmentService._();

  static final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');

  /// 将占位 [base] 合并为可展示的完整 [Movie]；失败时返回 null。
  Future<Movie?> enrich(
    Movie base, {
    String? searchHint,
    String? torrentImdbId,
  }) async {
    if (base.cover.isNotEmpty &&
        base.actors.isNotEmpty &&
        base.description.trim().length > 80 &&
        !base.description.trim().startsWith('磁力：')) {
      return null;
    }

    final hint = searchHint?.trim() ?? '';
    // 元数据检索优先用当前磁力资源标题，不用用户搜索词（搜索词仅作中文别名参考）。
    final torrentTitle = ImdbLookupService.cleanTitleForLookup(base.name);
    final lookupTitle = torrentTitle.isNotEmpty
        ? torrentTitle
        : (hint.isNotEmpty
            ? hint
            : ImdbLookupService.cleanTitleForLookup(base.alias));
    if (lookupTitle.isEmpty) return null;

    final yearHint = base.year.trim().isNotEmpty
        ? base.year.trim()
        : (ImdbLookupService.yearFromUserQuery(lookupTitle) ??
            ImdbLookupService.yearFromUserQuery(base.name));

    var imdbId = torrentImdbId?.trim().toLowerCase();
    if (imdbId != null && imdbId.isEmpty) imdbId = null;
    imdbId ??= ImdbLookupService.parseImdbIdFromText(base.name);
    imdbId ??= ImdbLookupService.parseImdbIdFromText(base.alias);

    VideoTitleResolveResult? resolved;
    if (!_cjkPattern.hasMatch(lookupTitle) || imdbId == null) {
      resolved = await VideoTitleResolveService.instance.resolve(
        lookupTitle,
        year: yearHint,
        alias: hint.isNotEmpty ? hint : base.alias,
      );
      imdbId ??= resolved?.imdbId;
    }

    final chineseLabel = _pickChineseLabel(hint, resolved, base);
    final englishName = resolved?.englishTitle?.trim() ?? '';
    final year = resolved?.year ?? yearHint ?? base.year;
    final displayName =
        base.name.trim().isNotEmpty ? base.name.trim() : lookupTitle;

    final magnetFooter = _extractMagnetFooter(base.description);

    final tmdbKey =
        StorageService().getSetting(AppConstants.keyTmdbApiKey)?.trim() ?? '';
    if (tmdbKey.isNotEmpty && imdbId != null) {
      final tmdb = await TmdbLookupService.instance.fetchDetailsByImdbId(
        imdbId,
        apiKey: tmdbKey,
      );
      if (tmdb != null) {
        debugPrint('磁力详情 TMDB 补全: $lookupTitle -> ${tmdb.displayTitle}');
        return _merge(
          base: base,
          name: displayName,
          alias: _joinAlias(
            englishName,
            tmdb.englishTitle,
            chineseLabel,
            base.alias,
          ),
          cover: tmdb.posterUrl,
          backdrop: tmdb.backdropUrl,
          rating: tmdb.rating,
          genres: tmdb.genres,
          region: tmdb.region,
          year: tmdb.year.isNotEmpty ? tmdb.year : year,
          director: tmdb.director,
          actors: tmdb.actors,
          description: _composeDescription(tmdb.overview, magnetFooter),
          relatedMovies: _mapSimilar(tmdb.related),
        );
      }
    }

    final imdbEnrich =
        await ImdbLookupService.instance.lookupEnrichmentForMagnetDetail(
      englishName.isNotEmpty ? englishName : lookupTitle,
      year: year,
      alias: chineseLabel.isNotEmpty ? chineseLabel : base.alias,
    );

    if (imdbEnrich != null) {
      debugPrint('磁力详情 IMDb 补全: $lookupTitle -> ${imdbEnrich.title}');
      final starring = imdbEnrich.starringLine?.trim() ?? '';
      return _merge(
        base: base,
        name: displayName,
        alias:
            _joinAlias(englishName, imdbEnrich.title, chineseLabel, base.alias),
        cover: imdbEnrich.posterUrl ?? base.cover,
        backdrop: base.backdrop,
        rating: base.rating,
        genres: base.genres,
        region: base.region,
        year: imdbEnrich.year ?? year,
        director: starring.isNotEmpty ? starring.split(',').first.trim() : '',
        actors: starring.isNotEmpty
            ? starring
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .take(8)
                .toList()
            : base.actors,
        description: _composeDescription('', magnetFooter),
        relatedMovies: base.relatedMovies,
      );
    }

    if (chineseLabel.isNotEmpty || englishName.isNotEmpty) {
      return _merge(
        base: base,
        name: displayName,
        alias: _joinAlias(englishName, '', chineseLabel, base.alias),
        cover: base.cover,
        backdrop: base.backdrop,
        rating: base.rating,
        genres: base.genres,
        region: base.region,
        year: year.isNotEmpty ? year : base.year,
        director: base.director,
        actors: base.actors,
        description: base.description,
        relatedMovies: base.relatedMovies,
      );
    }

    return null;
  }

  /// 中文片名标签（写入 alias，不覆盖磁力资源主标题）。
  static String _pickChineseLabel(
    String hint,
    VideoTitleResolveResult? resolved,
    Movie base,
  ) {
    if (hint.isNotEmpty &&
        _cjkPattern.hasMatch(hint) &&
        hint.trim() != base.name.trim()) {
      return hint.trim();
    }
    final local = resolved?.localTitle?.trim() ?? '';
    if (local.isNotEmpty && local != base.name.trim()) return local;
    return '';
  }

  static String _joinAlias(String a, String b, String c, String existing) {
    final parts = <String>[];
    for (final s in [a, b, c, existing]) {
      final t = s.trim();
      if (t.isEmpty) continue;
      if (parts.any((p) => p.toLowerCase() == t.toLowerCase())) continue;
      parts.add(t);
    }
    return parts.join(' · ');
  }

  static String _extractMagnetFooter(String description) {
    final d = description.trim();
    if (d.isEmpty) return '';
    if (d.startsWith('磁力：') || d.contains('磁力索引')) return d;
    return d.startsWith('——') ? d : '磁力索引\n$d';
  }

  static String _composeDescription(String overview, String footer) {
    final buf = StringBuffer();
    if (overview.trim().isNotEmpty) {
      buf.writeln(overview.trim());
    }
    if (footer.trim().isNotEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      buf.write(footer.trim());
    }
    return buf.toString();
  }

  static List<Movie> _mapSimilar(List<TmdbSimilarItem> items) {
    return items
        .map(
          (s) => Movie(
            id: 'tmdb_${s.mediaType}_${s.tmdbId}',
            name: s.title,
            year: s.year,
            cover: s.posterUrl,
          ),
        )
        .toList();
  }

  static Movie _merge({
    required Movie base,
    required String name,
    required String alias,
    required String cover,
    required String backdrop,
    required double rating,
    required List<String> genres,
    required String region,
    required String year,
    required String director,
    required List<String> actors,
    required String description,
    required List<Movie> relatedMovies,
  }) {
    final keepName =
        base.name.trim().isNotEmpty ? base.name.trim() : name.trim();
    return base.copyWith(
      name: keepName.isNotEmpty ? keepName : base.name,
      alias: alias,
      cover: cover.trim().isNotEmpty ? cover : base.cover,
      backdrop: backdrop.trim().isNotEmpty ? backdrop : base.backdrop,
      rating: rating > 0 ? rating : base.rating,
      genres: genres.isNotEmpty ? genres : base.genres,
      region: region.trim().isNotEmpty ? region : base.region,
      year: year.trim().isNotEmpty ? year : base.year,
      director: director.trim().isNotEmpty ? director : base.director,
      actors: actors.isNotEmpty ? actors : base.actors,
      description:
          description.trim().isNotEmpty ? description : base.description,
      relatedMovies:
          relatedMovies.isNotEmpty ? relatedMovies : base.relatedMovies,
    );
  }
}
