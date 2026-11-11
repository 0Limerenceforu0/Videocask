import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../models/movie.dart';
import 'api_service.dart';
import 'douban_lookup_service.dart';
import 'imdb_lookup_service.dart';
import 'storage_service.dart';
import 'subtitle/subtitle_title_extractor.dart';
import 'tmdb_lookup_service.dart';
import 'video_title_resolve_service.dart';

/// 磁力详情页元数据补全：中文片名 → 海报 / 简介 / 演职员 / 相似推荐。
class MagnetDetailEnrichmentService {
  MagnetDetailEnrichmentService._();
  static final MagnetDetailEnrichmentService instance =
      MagnetDetailEnrichmentService._();

  static final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');

  /// 把磁力 release 名转成元数据检索用的「干净片名 + 年份」。
  ///
  /// 旧实现用 `ImdbLookupService.cleanTitleForLookup`（只去版本号），纯英文
  /// release 名 `Hi Mom 2021 720p Chinese HDRip HC H264 BONE` 会原样喂给
  /// IMDb / 豆瓣 / CMS，联想 0 命中 → 整个详情页补全失败。真机 2026-11-11
  /// 13:32 logcat：`keyword=Hi Mom 2021 720p... → 0 条`、`(无补全)`。
  ///
  /// 复用字幕链路的 [extractSubtitleTitleQuery]，避免两套噪声词表漂移。
  /// 中文分支会残留紧跟其后的英文规格词（`肖申克的救赎 1080p BluRay x264`），
  /// 再用本服务的 [cleanSearchTitle] 从第一个技术标签处截断。
  @visibleForTesting
  static ({String title, String? year}) cleanLookupParts(String raw) {
    final q = extractSubtitleTitleQuery(primary: raw);
    final local = cleanSearchTitle(q.local);
    final english = q.english.trim();
    // 英文检索对 IMDb 联想更友好；没有英文时才退回中文。
    return (title: english.isNotEmpty ? english : local, year: q.year);
  }

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
    // 🔴 必须走 cleanLookupParts（复用字幕链路清洗器），不能直接用
    // `cleanTitleForLookup`：后者只去版本号，压制组噪声会导致联想全灭。
    final parts = cleanLookupParts(base.name);
    final torrentTitle = parts.title;
    final lookupTitle = torrentTitle.isNotEmpty
        ? torrentTitle
        : (hint.isNotEmpty ? hint : cleanLookupParts(base.alias).title);
    if (lookupTitle.isEmpty) return null;

    // 年份取清洗器抽出的值：片名剥干净后 `yearFromUserQuery(lookupTitle)`
    // 已经拿不到 2021 这种夹在分辨率前面的年份了。
    final yearHint = base.year.trim().isNotEmpty
        ? base.year.trim()
        : (parts.year ?? ImdbLookupService.yearFromUserQuery(base.name));

    var imdbId = torrentImdbId?.trim().toLowerCase();
    if (imdbId != null && imdbId.isEmpty) imdbId = null;
    imdbId ??= ImdbLookupService.parseImdbIdFromText(base.name);
    imdbId ??= ImdbLookupService.parseImdbIdFromText(base.alias);

    VideoTitleResolveResult? resolved;
    if (!_cjkPattern.hasMatch(lookupTitle) || imdbId == null) {
      resolved = await VideoTitleResolveService.instance.resolve(
        lookupTitle,
        year: yearHint,
        // 脏英文别名会被 resolve 当成 englishTitle，反过来污染后面
        // IMDb enrichment 的检索词（它优先用 englishName）。
        alias: hint.isNotEmpty ? hint : cleanLookupParts(base.alias).title,
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

    // 中文兜底：没有 TMDB Key（或 TMDB 没给简介）时，用豆瓣条目页补中文简介 + 主创。
    if (imdbId != null || englishName.isNotEmpty || hint.isNotEmpty) {
      var doubanId = resolved?.doubanId;
      if (doubanId == null || doubanId.isEmpty) {
        // 用中文 hint 或英文检索名再探一次豆瓣联想，拿 doubanId。
        final probe = (hint.isNotEmpty ? hint : lookupTitle).trim();
        if (probe.isNotEmpty) {
          final sug = await DoubanLookupService.instance.suggest(
            probe,
            year: yearHint,
          );
          doubanId = sug?.doubanId;
        }
      }
      if (doubanId != null && doubanId.isNotEmpty) {
        final subject =
            await DoubanLookupService.instance.getSubject(doubanId);
        if (subject != null) {
          debugPrint('磁力详情 豆瓣补全: $lookupTitle');
          return _merge(
            base: base,
            name: displayName,
            alias: _joinAlias(
              englishName,
              chineseLabel,
              base.alias,
              subject.year,
            ),
            cover: base.cover,
            backdrop: base.backdrop,
            rating: base.rating,
            genres: subject.genres.isNotEmpty ? subject.genres : base.genres,
            region: subject.region.isNotEmpty ? subject.region : base.region,
            year: subject.year.isNotEmpty ? subject.year : year,
            director: subject.director.isNotEmpty
                ? subject.director
                : base.director,
            actors: subject.actors.isNotEmpty ? subject.actors : base.actors,
            description: _composeDescription(subject.summary ?? '', magnetFooter),
            relatedMovies: base.relatedMovies,
          );
        }
      }
    }

    // 中文兜底 2：豆瓣在当前网络常被反爬（suggest 返回空数组、条目页 302 跳到
    // sec.douban.com），改用 App 自身 CMS 采集站补中文简介 + 主创 / 类型 / 地区。
    // CMS 是 App 的主数据源，必定可达；`ac=detail` 的搜索结果已带 vod_content。
    final cmsMatch = await _lookupCmsMovie(
      cleanSearchTitle(lookupTitle),
      hint: cleanSearchTitle(hint),
      yearHint: yearHint,
    );
    if (cmsMatch != null) {
      debugPrint(
        '磁力详情 CMS 补全: $lookupTitle -> ${cmsMatch.name} '
        '(演员 ${cmsMatch.actors.length} 人, 导演=${cmsMatch.director})',
      );
      return _merge(
        base: base,
        name: displayName,
        alias: _joinAlias(englishName, chineseLabel, '', base.alias),
        cover: cmsMatch.cover.isNotEmpty ? cmsMatch.cover : base.cover,
        backdrop: base.backdrop,
        rating: cmsMatch.rating > 0 ? cmsMatch.rating : base.rating,
        genres: cmsMatch.genres.isNotEmpty ? cmsMatch.genres : base.genres,
        region:
            cmsMatch.region.trim().isNotEmpty ? cmsMatch.region : base.region,
        year: cmsMatch.year.trim().isNotEmpty ? cmsMatch.year : year,
        director: cmsMatch.director.trim().isNotEmpty
            ? cmsMatch.director
            : base.director,
        actors: cmsMatch.actors.isNotEmpty ? cmsMatch.actors : base.actors,
        description: _composeDescription(cmsMatch.description, magnetFooter),
        relatedMovies: base.relatedMovies,
      );
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
        // IMDb 补全只给「主演」行，没有导演；不要拿第一个演员冒充导演。
        director: base.director,
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

  /// 去除资源名里的发布标签，得到适合 CMS 检索的片名。
  ///
  /// 例：`肖申克的救赎.1994.1080p` → `肖申克的救赎`；
  /// `Blade.Runner.2049.2017.1080p` → `Blade Runner 2049`
  /// （先截画质标签、再剥结尾年份，避免把片名自带的 2049 当成年份删掉）。
  @visibleForTesting
  static String cleanSearchTitle(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    // 1. 去掉 [] 【】 () 内的发布组 / 语言 / 字幕标签。
    s = s.replaceAll(RegExp(r'[\[【（(][^\]】）)]*[\]】）)]'), ' ');

    // 2. 从第一个画质 / 片源 / 编码 / 音轨标签开始截断。
    s = s.replaceAll(
      RegExp(
        r'[.\s_-]+(?:4k|2160p|1080p|720p|480p|blu-?ray|bdrip|brrip|dvdrip|'
        r'dvd|web-?dl|webrip|hdtv|remux|x264|x265|h\.?264|h\.?265|hevc|avc|'
        r'aac|ac3|dts|ddp?|flac|hdr|国语|粤语|中字|双语|简繁).*$',
        caseSensitive: false,
        dotAll: true,
      ),
      '',
    );

    // 3. 去掉结尾残留的发布年份（如 `...Redemption.1994`）。
    s = s.replaceAll(RegExp(r'[.\s_-]+(?:19|20)\d{2}\s*$'), '');

    // 4. 分隔符归一为空格。
    s = s.replaceAll(RegExp(r'[._]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// 用 App 自带 CMS 采集站按片名检索，取最佳匹配项的完整中文元数据。
  ///
  /// 为什么需要：豆瓣在当前网络被反爬（suggest 返回空数组、条目页 302 到
  /// sec.douban.com），IMDb 只有英文且没有剧情简介；CMS 是 App 的主数据源，
  /// 必定可达，且 `ac=detail` 的搜索结果自带 `vod_content`（中文简介）。
  /// 失败 / 无匹配一律返回 null（绝不抛），不阻断后续 IMDb 兜底。
  static Future<Movie?> _lookupCmsMovie(
    String title, {
    String hint = '',
    String? yearHint,
  }) async {
    final queries = <String>[];
    for (final q in [hint, title]) {
      final t = q.trim();
      if (t.isEmpty) continue;
      if (queries.any((e) => e.toLowerCase() == t.toLowerCase())) continue;
      queries.add(t);
    }

    for (final q in queries) {
      try {
        final movies = await ApiService()
            .searchMovies(q, page: 1, maxPages: 1)
            .timeout(const Duration(seconds: 10));
        var best = _pickCmsMatch(movies, q, yearHint);
        if (best == null) continue;
        // 2026-10-28 用户反馈「聚合资源没有这么详细的演员表」：
        // 部分采集站列表接口（ac=detail&wd=）会省略 vod_actor / vod_director，
        // 只给简介。此时按 id 再取一次详情（ac=detail&ids=），把演职员补齐。
        if (best.actors.isEmpty || best.director.trim().isEmpty) {
          final full = await _fetchCmsDetail(best.id);
          if (full != null) {
            best = best.copyWith(
              director: full.director.trim().isNotEmpty
                  ? full.director
                  : best.director,
              actors: full.actors.isNotEmpty ? full.actors : best.actors,
              genres: full.genres.isNotEmpty ? full.genres : best.genres,
              region:
                  full.region.trim().isNotEmpty ? full.region : best.region,
              year: full.year.trim().isNotEmpty ? full.year : best.year,
              description: full.description.trim().isNotEmpty
                  ? full.description
                  : best.description,
            );
          }
        }
        return best;
      } catch (e) {
        debugPrint('磁力详情 CMS 补全失败 ($q): $e');
      }
    }
    return null;
  }

  /// 按 CMS id 取完整详情；失败返回 null（不抛）。
  static Future<Movie?> _fetchCmsDetail(String id) async {
    if (id.trim().isEmpty) return null;
    try {
      return await ApiService()
          .getMovieDetail(id)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('磁力详情 CMS 详情补取失败 ($id): $e');
      return null;
    }
  }

  /// 从 CMS 搜索结果里挑最佳匹配项。
  ///
  /// 片名精确命中优先，年份相同加分；有中文简介的再加分（简介正是要补的）。
  /// 完全不相关的结果直接跳过，避免把别的影片信息贴到磁力资源上。
  static Movie? _pickCmsMatch(
    List<Movie> movies,
    String query,
    String? yearHint,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    final yh = (yearHint ?? '').trim();

    Movie? best;
    var bestScore = 0;
    for (final m in movies) {
      final name = m.name.trim().toLowerCase();
      if (name.isEmpty) continue;
      var score = 0;
      if (name == q) {
        score += 100;
      } else if (name.contains(q) || q.contains(name)) {
        score += 60;
      }
      if (score == 0) continue;
      if (yh.length == 4 && m.year.trim() == yh) score += 20;
      if (m.description.trim().length > 40) score += 10;
      // 有演职员的条目优先：磁力页最缺的正是「导演/主演」，
      // 同名片（翻拍、同名不同年）之间优先选信息更全的那条。
      if (m.actors.isNotEmpty) score += 15;
      if (score > bestScore) {
        bestScore = score;
        best = m;
      }
    }
    return best;
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
