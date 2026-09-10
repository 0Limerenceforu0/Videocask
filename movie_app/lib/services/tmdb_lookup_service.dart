import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// TMDB 搜索 + external_ids，将中文/英文片名解析为 IMDb `tt` 与英文主名。
class TmdbLookupService {
  TmdbLookupService._();
  static final TmdbLookupService instance = TmdbLookupService._();

  static const _baseUrl = 'https://api.themoviedb.org/3';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 14),
      headers: {'Accept': 'application/json'},
    ),
  );

  Future<TmdbResolveMatch?> resolve(
    String query, {
    required String apiKey,
    String? year,
    String? englishHint,
  }) async {
    final key = apiKey.trim();
    final q = query.trim();
    if (key.isEmpty || q.isEmpty) return null;

    try {
      TmdbSearchCandidate? best;
      var bestScore = 0.0;
      final yearHint = year?.trim();

      for (final endpoint in ['multi', 'movie', 'tv']) {
        final list = await _searchEndpoint(
          endpoint: endpoint,
          query: q,
          apiKey: key,
          language: 'zh-CN',
        );
        for (final c in list) {
          final score = _scoreCandidate(
            c,
            query: q,
            englishHint: englishHint,
            yearHint: yearHint,
          );
          if (score > bestScore) {
            bestScore = score;
            best = c;
          }
        }
      }

      if (best == null || bestScore < 70) return null;

      final imdbId = await _fetchImdbId(
        mediaType: best.mediaType,
        tmdbId: best.id,
        apiKey: key,
      );
      if (imdbId == null || imdbId.isEmpty) return null;

      debugPrint(
        'TMDB 解析: $q -> $imdbId (${best.englishTitle}, ${best.year})',
      );
      return TmdbResolveMatch(
        imdbId: imdbId.toLowerCase(),
        englishTitle: best.englishTitle,
        year: best.year,
        tmdbId: best.id,
        mediaType: best.mediaType,
      );
    } catch (e) {
      debugPrint('TMDB 解析失败 ($q): $e');
      return null;
    }
  }

  Future<List<TmdbSearchCandidate>> _searchEndpoint({
    required String endpoint,
    required String query,
    required String apiKey,
    required String language,
  }) async {
    final url = Uri.parse('$_baseUrl/search/$endpoint').replace(
      queryParameters: {
        'api_key': apiKey,
        'query': query,
        'language': language,
        'include_adult': 'false',
      },
    );
    final resp = await _dio.get<Map<String, dynamic>>(url.toString());
    final results = resp.data?['results'];
    if (results is! List) return [];

    final out = <TmdbSearchCandidate>[];
    for (final raw in results) {
      if (raw is! Map) continue;
      final parsed = parseSearchResult(Map<String, dynamic>.from(raw));
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  @visibleForTesting
  static TmdbSearchCandidate? parseSearchResult(Map<String, dynamic> raw) {
    final mediaType = raw['media_type']?.toString() ?? 'movie';
    if (mediaType != 'movie' && mediaType != 'tv') return null;

    final id = raw['id'];
    final tmdbId = id is int ? id : int.tryParse(id?.toString() ?? '');
    if (tmdbId == null || tmdbId <= 0) return null;

    String display;
    String original;
    String date;
    if (mediaType == 'tv') {
      display = raw['name']?.toString().trim() ?? '';
      original = raw['original_name']?.toString().trim() ?? '';
      date = raw['first_air_date']?.toString().trim() ?? '';
    } else {
      display = raw['title']?.toString().trim() ?? '';
      original = raw['original_title']?.toString().trim() ?? '';
      date = raw['release_date']?.toString().trim() ?? '';
    }
    if (display.isEmpty) return null;

    final english = _pickLatinTitle(display, original);
    final year = date.length >= 4 ? date.substring(0, 4) : '';

    return TmdbSearchCandidate(
      id: tmdbId,
      mediaType: mediaType,
      displayTitle: display,
      englishTitle: english,
      year: year,
      popularity: (raw['popularity'] is num)
          ? (raw['popularity'] as num).toDouble()
          : 0,
    );
  }

  static String _pickLatinTitle(String display, String original) {
    final o = original.trim();
    if (o.isNotEmpty && !_hasCjk(o)) return o;
    if (!_hasCjk(display)) return display;
    return o.isNotEmpty ? o : display;
  }

  static bool _hasCjk(String s) => RegExp(r'[\u4e00-\u9fff]').hasMatch(s);

  static double _scoreCandidate(
    TmdbSearchCandidate c, {
    required String query,
    String? englishHint,
    String? yearHint,
  }) {
    var s = 0.0;
    final qn = query.toLowerCase().trim();
    final dn = c.displayTitle.toLowerCase();
    final en = c.englishTitle.toLowerCase();
    if (dn == qn || en == qn) {
      s += 220;
    } else if (dn.contains(qn) || qn.contains(dn) || en.contains(qn)) {
      s += 130;
    }
    final hint = englishHint?.trim().toLowerCase() ?? '';
    if (hint.isNotEmpty &&
        (en == hint || en.contains(hint) || hint.contains(en))) {
      s += 160;
    }
    final yh = yearHint ?? '';
    if (yh.length == 4 && c.year == yh) s += 110;
    s += (c.popularity / 10).clamp(0, 35);
    return s;
  }

  Future<String?> _fetchImdbId({
    required String mediaType,
    required int tmdbId,
    required String apiKey,
  }) async {
    final path = mediaType == 'tv' ? 'tv' : 'movie';
    final url = Uri.parse('$_baseUrl/$path/$tmdbId/external_ids').replace(
      queryParameters: {'api_key': apiKey},
    );
    final resp = await _dio.get<Map<String, dynamic>>(url.toString());
    final imdb = resp.data?['imdb_id']?.toString().trim();
    if (imdb == null || imdb.isEmpty || imdb == 'null') return null;
    return imdb;
  }

  static const _imageBase = 'https://image.tmdb.org/t/p';

  /// 通过 IMDb ID 拉取 TMDB 详情（简介、海报、演职员、相似片单）。
  Future<TmdbDetailEnrichment?> fetchDetailsByImdbId(
    String imdbId, {
    required String apiKey,
  }) async {
    final key = apiKey.trim();
    final imdb = imdbId.trim().toLowerCase();
    if (key.isEmpty || !imdb.startsWith('tt')) return null;

    try {
      final findUrl = Uri.parse('$_baseUrl/find/$imdb').replace(
        queryParameters: {
          'api_key': key,
          'external_source': 'imdb_id',
          'language': 'zh-CN',
        },
      );
      final findResp = await _dio.get<Map<String, dynamic>>(findUrl.toString());
      final data = findResp.data;
      if (data == null) return null;

      Map<String, dynamic>? pick;
      String mediaType = 'movie';
      final movies = data['movie_results'];
      if (movies is List && movies.isNotEmpty && movies.first is Map) {
        pick = Map<String, dynamic>.from(movies.first as Map);
        mediaType = 'movie';
      } else {
        final tvs = data['tv_results'];
        if (tvs is List && tvs.isNotEmpty && tvs.first is Map) {
          pick = Map<String, dynamic>.from(tvs.first as Map);
          mediaType = 'tv';
        }
      }
      if (pick == null) return null;

      final tmdbId = pick['id'];
      final id =
          tmdbId is int ? tmdbId : int.tryParse(tmdbId?.toString() ?? '');
      if (id == null || id <= 0) return null;

      final path = mediaType == 'tv' ? 'tv' : 'movie';
      final detailUrl = Uri.parse('$_baseUrl/$path/$id').replace(
        queryParameters: {
          'api_key': key,
          'language': 'zh-CN',
          'append_to_response': 'credits',
        },
      );
      final detailResp =
          await _dio.get<Map<String, dynamic>>(detailUrl.toString());
      final detail = detailResp.data;
      if (detail == null) return null;

      final similarUrl = Uri.parse('$_baseUrl/$path/$id/similar').replace(
        queryParameters: {
          'api_key': key,
          'language': 'zh-CN',
          'page': '1',
        },
      );
      final similarResp =
          await _dio.get<Map<String, dynamic>>(similarUrl.toString());
      final similarList = similarResp.data?['results'];
      final related = similarList is List
          ? parseSimilarResults(similarList)
          : const <TmdbSimilarItem>[];

      return parseDetailEnrichment(
        detail,
        mediaType: mediaType,
        related: related,
      );
    } catch (e) {
      debugPrint('TMDB 详情失败 ($imdb): $e');
      return null;
    }
  }

  @visibleForTesting
  static TmdbDetailEnrichment? parseDetailEnrichment(
    Map<String, dynamic> detail, {
    required String mediaType,
    List<TmdbSimilarItem> related = const [],
  }) {
    final isTv = mediaType == 'tv';
    final display = isTv
        ? detail['name']?.toString().trim() ?? ''
        : detail['title']?.toString().trim() ?? '';
    if (display.isEmpty) return null;

    final original = isTv
        ? detail['original_name']?.toString().trim() ?? ''
        : detail['original_title']?.toString().trim() ?? '';
    final english = _pickLatinTitle(display, original);

    final date = isTv
        ? detail['first_air_date']?.toString() ?? ''
        : detail['release_date']?.toString() ?? '';
    final year = date.length >= 4 ? date.substring(0, 4) : '';

    final poster = detail['poster_path']?.toString();
    final backdrop = detail['backdrop_path']?.toString();
    final overview = detail['overview']?.toString().trim() ?? '';
    final vote = detail['vote_average'];
    final rating = vote is num ? vote.toDouble().clamp(0.0, 10.0) : 0.0;

    final genresRaw = detail['genres'];
    final genres = <String>[];
    if (genresRaw is List) {
      for (final g in genresRaw) {
        if (g is Map) {
          final n = g['name']?.toString().trim();
          if (n != null && n.isNotEmpty) genres.add(n);
        }
      }
    }

    var region = '';
    if (!isTv) {
      final countries = detail['production_countries'];
      if (countries is List && countries.isNotEmpty) {
        final c0 = countries.first;
        if (c0 is Map) region = c0['name']?.toString().trim() ?? '';
      }
    }

    var director = '';
    final actors = <String>[];
    final credits = detail['credits'];
    if (credits is Map) {
      final crew = credits['crew'];
      if (crew is List) {
        for (final c in crew) {
          if (c is! Map) continue;
          if (c['job']?.toString() == 'Director') {
            director = c['name']?.toString().trim() ?? '';
            break;
          }
        }
      }
      final cast = credits['cast'];
      if (cast is List) {
        for (final i in cast.take(8)) {
          if (i is Map) {
            final n = i['name']?.toString().trim();
            if (n != null && n.isNotEmpty) actors.add(n);
          }
        }
      }
    }

    if (director.isEmpty && isTv) {
      final creators = detail['created_by'];
      if (creators is List && creators.isNotEmpty) {
        final c0 = creators.first;
        if (c0 is Map) director = c0['name']?.toString().trim() ?? '';
      }
    }

    return TmdbDetailEnrichment(
      displayTitle: display,
      englishTitle: english,
      year: year,
      overview: overview,
      posterUrl: _posterUrl(poster),
      backdropUrl: _backdropUrl(backdrop),
      rating: rating,
      genres: genres,
      region: region,
      director: director,
      actors: actors,
      related: related,
    );
  }

  @visibleForTesting
  static List<TmdbSimilarItem> parseSimilarResults(List<dynamic> list) {
    final out = <TmdbSimilarItem>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final mediaType = map['media_type']?.toString() ?? 'movie';
      if (mediaType != 'movie' && mediaType != 'tv') continue;
      final id = map['id'];
      final tmdbId = id is int ? id : int.tryParse(id?.toString() ?? '');
      if (tmdbId == null) continue;
      final title = mediaType == 'tv'
          ? map['name']?.toString().trim() ?? ''
          : map['title']?.toString().trim() ?? '';
      if (title.isEmpty) continue;
      final date = mediaType == 'tv'
          ? map['first_air_date']?.toString() ?? ''
          : map['release_date']?.toString() ?? '';
      out.add(
        TmdbSimilarItem(
          tmdbId: tmdbId,
          mediaType: mediaType,
          title: title,
          year: date.length >= 4 ? date.substring(0, 4) : '',
          posterUrl: _posterUrl(map['poster_path']?.toString()),
        ),
      );
      if (out.length >= 12) break;
    }
    return out;
  }

  static String _posterUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    return '$_imageBase/w500$path';
  }

  static String _backdropUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    return '$_imageBase/w780$path';
  }
}

class TmdbSearchCandidate {
  final int id;
  final String mediaType;
  final String displayTitle;
  final String englishTitle;
  final String year;
  final double popularity;

  const TmdbSearchCandidate({
    required this.id,
    required this.mediaType,
    required this.displayTitle,
    required this.englishTitle,
    required this.year,
    required this.popularity,
  });
}

class TmdbResolveMatch {
  final String imdbId;
  final String englishTitle;
  final String year;
  final int tmdbId;
  final String mediaType;

  const TmdbResolveMatch({
    required this.imdbId,
    required this.englishTitle,
    required this.year,
    required this.tmdbId,
    required this.mediaType,
  });
}

class TmdbDetailEnrichment {
  final String displayTitle;
  final String englishTitle;
  final String year;
  final String overview;
  final String posterUrl;
  final String backdropUrl;
  final double rating;
  final List<String> genres;
  final String region;
  final String director;
  final List<String> actors;
  final List<TmdbSimilarItem> related;

  const TmdbDetailEnrichment({
    required this.displayTitle,
    required this.englishTitle,
    required this.year,
    required this.overview,
    required this.posterUrl,
    required this.backdropUrl,
    required this.rating,
    required this.genres,
    required this.region,
    required this.director,
    required this.actors,
    required this.related,
  });
}

class TmdbSimilarItem {
  final int tmdbId;
  final String mediaType;
  final String title;
  final String year;
  final String posterUrl;

  const TmdbSimilarItem({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    required this.year,
    required this.posterUrl,
  });
}
