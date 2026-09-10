import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';

part 'movie.g.dart';

/// 多源搜索合并：同一影片在其它 CMS 源的详情入口（用于跳转与展示）
@immutable
@JsonSerializable()
class MovieAlternateSource {
  final String sourceId;
  final String movieId;
  final String sourceDisplayName;

  const MovieAlternateSource({
    required this.sourceId,
    required this.movieId,
    required this.sourceDisplayName,
  });

  factory MovieAlternateSource.fromJson(Map<String, dynamic> json) =>
      _$MovieAlternateSourceFromJson(json);
  Map<String, dynamic> toJson() => _$MovieAlternateSourceToJson(this);
}

/// 影片模型
@JsonSerializable()
class Movie {
  /// HTML标签正则（编译一次，复用）
  static final _htmlTagRegex = RegExp(r'<[^>]*>');

  /// 影片唯一标识
  final String id;

  /// 所属源ID
  final String sourceId;

  /// 影片名称
  final String name;

  /// 影片别名
  final String alias;

  /// 封面图片URL
  final String cover;

  /// 背景图URL
  final String backdrop;

  /// 评分（0-10）
  final double rating;

  /// 类型标签（如：动作, 科幻, 爱情）
  final List<String> genres;

  /// 地区
  final String region;

  /// 年份
  final String year;

  /// 导演
  final String director;

  /// 演员列表
  final List<String> actors;

  /// 简介
  final String description;

  /// 更新状态（如：更新至第12集, 已完结）
  final String updateStatus;

  /// 播放线路列表
  final List<PlayRoute> playRoutes;

  /// 相关推荐
  @JsonKey(defaultValue: [])
  final List<Movie> relatedMovies;

  /// 语言
  final String language;

  /// 时长（分钟）
  final int duration;

  /// 是否完结
  final bool isCompleted;

  /// 最后更新时间
  @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
  final DateTime lastUpdate;

  /// 创建时间
  @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
  final DateTime createdAt;

  /// 多源搜索合并条目：其它 CMS 源也有同款（可跳转对应详情）
  final List<MovieAlternateSource> alternateSources;

  Movie({
    required this.id,
    this.sourceId = '',
    required this.name,
    this.alias = '',
    this.cover = '',
    this.backdrop = '',
    this.rating = 0.0,
    this.genres = const [],
    this.region = '',
    this.year = '',
    this.director = '',
    this.actors = const [],
    this.description = '',
    this.updateStatus = '',
    this.playRoutes = const [],
    this.relatedMovies = const [],
    this.language = '',
    this.duration = 0,
    this.isCompleted = false,
    this.alternateSources = const [],
    DateTime? lastUpdate,
    DateTime? createdAt,
  })  : lastUpdate = lastUpdate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  /// 从JSON创建（原有自定义格式）
  factory Movie.fromJson(Map<String, dynamic> json) => _$MovieFromJson(json);
  Map<String, dynamic> toJson() => _$MovieToJson(this);

  /// 日期时间从JSON解析
  static DateTime _dateTimeFromJson(dynamic value) {
    if (value == null) return DateTime.now();
    final valueStr = value.toString();
    final parsed = DateTime.tryParse(valueStr);
    return parsed ?? DateTime.now();
  }

  /// 日期时间转JSON
  static String _dateTimeToJson(DateTime value) {
    return value.toIso8601String();
  }

  /// 从苹果CMS采集接口JSON创建
  ///
  /// 字段映射关系：
  /// - vod_id → id
  /// - vod_name → name
  /// - vod_pic → cover
  /// - vod_class → genres（逗号分隔转List）
  /// - vod_year → year
  /// - vod_area → region
  /// - vod_lang → language
  /// - vod_remarks → updateStatus
  /// - vod_content → description（去除HTML标签）
  /// - type_name → 添加到genres
  /// - vod_director → director
  /// - vod_actor → actors（逗号分隔转List）
  /// - vod_play_from / vod_play_url → playRoutes
  /// - vod_time → lastUpdate
  /// - vod_score → rating
  factory Movie.fromCmsJson(Map<String, dynamic> json) {
    // 解析vod_class为类型列表
    final classStr = json['vod_class']?.toString() ?? '';
    final genres = classStr
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // 将type_name也添加到类型中（如果不在已有类型中）
    final typeName = json['type_name']?.toString() ?? '';
    if (typeName.isNotEmpty && !genres.contains(typeName)) {
      genres.insert(0, typeName);
    }

    // 解析vod_actor为演员列表
    final actorStr = json['vod_actor']?.toString() ?? '';
    final actors = actorStr
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // 去除vod_content中的HTML标签
    final contentHtml = json['vod_content']?.toString() ?? '';
    final description = _stripHtmlTags(contentHtml);

    // 解析播放线路和集数（结构化 vod_play_list 与 vod_play_from/url 取线路更多者）
    final playRoutes = _resolvePlayRoutesFromCmsJson(json);

    // 解析最后更新时间（vod_time 可能是 Unix 时间戳）
    final timeStr = json['vod_time']?.toString() ?? '';
    DateTime lastUpdate;
    if (timeStr.isNotEmpty) {
      // 优先尝试作为 Unix 时间戳解析（秒级）
      final timestamp = int.tryParse(timeStr);
      if (timestamp != null && timestamp > 0) {
        // 判断是秒级还是毫秒级时间戳（毫秒级大于 10^12）
        if (timestamp > 1000000000000) {
          lastUpdate = DateTime.fromMillisecondsSinceEpoch(timestamp);
        } else {
          lastUpdate = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        }
      } else {
        lastUpdate = DateTime.tryParse(timeStr) ?? DateTime.now();
      }
    } else {
      lastUpdate = DateTime.now();
    }

    // 解析评分
    final scoreStr = json['vod_score']?.toString() ?? '';
    double rating = 0.0;
    if (scoreStr.isNotEmpty) {
      rating = double.tryParse(scoreStr) ?? 0.0;
    }

    return Movie(
      id: json['vod_id']?.toString() ?? '',
      name: json['vod_name']?.toString() ?? '',
      cover: json['vod_pic']?.toString() ?? '',
      rating: rating,
      genres: genres,
      region: json['vod_area']?.toString() ?? '',
      year: json['vod_year']?.toString() ?? '',
      director: json['vod_director']?.toString() ?? '',
      actors: actors,
      description: description,
      updateStatus: json['vod_remarks']?.toString() ?? '',
      playRoutes: playRoutes,
      language: json['vod_lang']?.toString() ?? '',
      lastUpdate: lastUpdate,
    );
  }

  /// 去除HTML标签
  static String _stripHtmlTags(String htmlString) {
    if (htmlString.isEmpty) return '';
    // 使用正则去除所有HTML标签（复用预编译正则）
    final cleanText = htmlString.replaceAll(_htmlTagRegex, '');
    // 解码常见的HTML实体
    return cleanText
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&rdquo;', '"')
        .replaceAll('&ldquo;', '"')
        .replaceAll('&mdash;', '—')
        .trim();
  }

  /// 解析播放线路和集数
  ///
  /// vod_play_from格式: "线路1$$$线路2" 或 "youku,qiyi"（逗号分隔播放器）
  /// vod_play_url格式: "第1集$url1#第2集$url2$$$第1集$url3#第2集$url4"
  /// 用$$$分割不同线路，用#分割同一线路的不同集数，用$分割集数名称和URL
  ///
  /// 常见采集站仅填一个 [vod_play_from]（如 `lzm3u8`），多线路全在 [vod_play_url] 的 `$$$` 分段里。
  static List<PlayRoute> _parsePlayRoutes(String playFrom, String playUrl) {
    final fromList = _splitCmsRouteNames(playFrom);
    final urlList = _splitCmsRouteUrlBlocks(
      playUrl,
      expectedRoutes: fromList.length,
    );
    if (fromList.isEmpty || urlList.isEmpty) return [];

    final routeCount =
        urlList.length > fromList.length ? urlList.length : fromList.length;

    final routes = <PlayRoute>[];
    for (var i = 0; i < routeCount; i++) {
      final routeName = _routeDisplayName(fromList, i);
      final routeUrlStr = i < urlList.length ? urlList[i] : '';
      if (routeUrlStr.isEmpty) continue;

      final episodes = _parseEpisodesFromRouteBlock(routeUrlStr);
      if (episodes.isNotEmpty) {
        routes.add(
          PlayRoute(
            name: routeName,
            episodes: episodes,
          ),
        );
      }
    }

    return routes;
  }

  /// 合并 CMS 结构化 [vod_play_list] 与经典 [vod_play_from]/[vod_play_url] 解析结果。
  ///
  /// 部分采集站 [vod_play_list] 仅含默认播放器一条线路，完整多线路仍在
  /// [vod_play_url] 的 `$$$` 分段里，不可因前者存在而丢弃后者。
  static List<PlayRoute> _resolvePlayRoutesFromCmsJson(
    Map<String, dynamic> json,
  ) {
    final fromStructured =
        _parsePlayRoutesFromJson(json) ?? const <PlayRoute>[];
    final fromClassic = _parsePlayRoutes(
      json['vod_play_from']?.toString() ?? '',
      json['vod_play_url']?.toString() ?? '',
    );
    if (fromStructured.isEmpty) return fromClassic;
    if (fromClassic.isEmpty) return fromStructured;
    if (fromClassic.length > fromStructured.length) return fromClassic;
    if (fromStructured.length > fromClassic.length) return fromStructured;
    final classicEpisodes = fromClassic.fold<int>(
      0,
      (sum, r) => sum + r.episodes.length,
    );
    final structuredEpisodes = fromStructured.fold<int>(
      0,
      (sum, r) => sum + r.episodes.length,
    );
    return classicEpisodes > structuredEpisodes ? fromClassic : fromStructured;
  }

  /// 部分接口直接返回结构化的 `vod_play_list`（也可能是 JSON 字符串）。
  static List<PlayRoute>? _parsePlayRoutesFromJson(Map<String, dynamic> json) {
    final raw = json['vod_play_list'];
    final List<dynamic>? list = switch (raw) {
      final List<dynamic> l => l,
      final String s when s.trim().isNotEmpty => _decodePlayListString(s),
      _ => null,
    };
    if (list == null || list.isEmpty) return null;

    final routes = <PlayRoute>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);

      var name = map['from']?.toString().trim() ?? '';
      if (name.isEmpty) {
        final playerInfo = map['player_info'];
        if (playerInfo is Map) {
          name = playerInfo['show']?.toString().trim() ?? '';
        }
      }
      if (name.isEmpty) {
        name = '线路 ${i + 1}';
      }

      final urlsRaw = map['urls'];
      if (urlsRaw is List && urlsRaw.isNotEmpty) {
        final episodes = <Episode>[];
        for (var j = 0; j < urlsRaw.length; j++) {
          final u = urlsRaw[j];
          if (u is! Map) continue;
          final episodeUrl = u['url']?.toString().trim() ?? '';
          if (episodeUrl.isEmpty) continue;
          final episodeName = u['name']?.toString().trim() ?? '';
          episodes.add(
            Episode(
              index: j,
              name: episodeName.isNotEmpty ? episodeName : '第${j + 1}集',
              url: episodeUrl,
            ),
          );
        }
        if (episodes.isNotEmpty) {
          routes.add(PlayRoute(name: name, episodes: episodes));
        }
        continue;
      }

      final urlStr = map['url']?.toString().trim() ?? '';
      if (urlStr.isEmpty) continue;
      final episodes = _parseEpisodesFromRouteBlock(urlStr);
      if (episodes.isNotEmpty) {
        routes.add(PlayRoute(name: name, episodes: episodes));
      }
    }

    return routes.isEmpty ? null : routes;
  }

  static List<dynamic>? _decodePlayListString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
    } catch (_) {}
    return null;
  }

  static String _normalizeCmsPlayField(String raw) {
    var s = raw.trim();
    if (s.contains('%24%24%24')) {
      s = s.replaceAll('%24%24%24', r'$$$');
    }
    return s;
  }

  static List<String> _splitCmsRouteNames(String playFrom) {
    final normalized = _normalizeCmsPlayField(playFrom);
    if (normalized.isEmpty) return [];

    List<String> parts;
    if (normalized.contains(r'$$$')) {
      parts = normalized.split(r'$$$');
    } else if (normalized.contains(',')) {
      parts = normalized.split(',');
    } else {
      parts = [normalized];
    }

    return parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static List<String> _splitCmsRouteUrlBlocks(
    String playUrl, {
    int expectedRoutes = 0,
  }) {
    final normalized = _normalizeCmsPlayField(playUrl);
    if (normalized.isEmpty) return [];

    List<String> splitBlocks(String separator) {
      return normalized
          .split(separator)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    var blocks = splitBlocks(r'$$$');
    if (blocks.length <= 1 && expectedRoutes > 1) {
      final alt = splitBlocks(r'$$');
      if (alt.length > blocks.length) {
        blocks = alt;
      }
    }
    return blocks;
  }

  static String _routeDisplayName(List<String> fromList, int index) {
    if (index < fromList.length && fromList[index].isNotEmpty) {
      return fromList[index];
    }
    if (fromList.isNotEmpty && fromList.first.isNotEmpty) {
      return '${fromList.first} ${index + 1}';
    }
    return '线路 ${index + 1}';
  }

  static List<Episode> _parseEpisodesFromRouteBlock(String routeUrlStr) {
    final episodeParts = routeUrlStr.split('#');
    final episodes = <Episode>[];

    for (var j = 0; j < episodeParts.length; j++) {
      final part = episodeParts[j].trim();
      if (part.isEmpty) continue;

      final dollarIndex = part.indexOf(r'$');
      final String episodeName;
      final String episodeUrl;

      if (dollarIndex > 0) {
        episodeName = part.substring(0, dollarIndex).trim();
        episodeUrl = part.substring(dollarIndex + 1).trim();
      } else {
        episodeName = '第${j + 1}集';
        episodeUrl = part;
      }

      if (episodeUrl.isNotEmpty) {
        episodes.add(
          Episode(
            index: j,
            name: episodeName,
            url: episodeUrl,
          ),
        );
      }
    }

    return episodes;
  }

  /// 复制并修改部分字段
  Movie copyWith({
    String? id,
    String? sourceId,
    String? name,
    String? alias,
    String? cover,
    String? backdrop,
    double? rating,
    List<String>? genres,
    String? region,
    String? year,
    String? director,
    List<String>? actors,
    String? description,
    String? updateStatus,
    List<PlayRoute>? playRoutes,
    List<Movie>? relatedMovies,
    String? language,
    int? duration,
    bool? isCompleted,
    List<MovieAlternateSource>? alternateSources,
    DateTime? lastUpdate,
  }) {
    return Movie(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      name: name ?? this.name,
      alias: alias ?? this.alias,
      cover: cover ?? this.cover,
      backdrop: backdrop ?? this.backdrop,
      rating: rating ?? this.rating,
      genres: genres ?? this.genres,
      region: region ?? this.region,
      year: year ?? this.year,
      director: director ?? this.director,
      actors: actors ?? this.actors,
      description: description ?? this.description,
      updateStatus: updateStatus ?? this.updateStatus,
      playRoutes: playRoutes ?? this.playRoutes,
      relatedMovies: relatedMovies ?? this.relatedMovies,
      language: language ?? this.language,
      duration: duration ?? this.duration,
      isCompleted: isCompleted ?? this.isCompleted,
      alternateSources: alternateSources ?? this.alternateSources,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Movie && other.id == id && other.sourceId == sourceId;
  }

  @override
  int get hashCode => id.hashCode ^ sourceId.hashCode;

  @override
  String toString() => 'Movie(id: $id, name: $name, rating: $rating)';
}

/// 播放线路
@JsonSerializable()
class PlayRoute {
  /// 线路名称
  final String name;

  /// 播放集数列表
  final List<Episode> episodes;

  PlayRoute({
    required this.name,
    this.episodes = const [],
  });

  factory PlayRoute.fromJson(Map<String, dynamic> json) =>
      _$PlayRouteFromJson(json);
  Map<String, dynamic> toJson() => _$PlayRouteToJson(this);

  PlayRoute copyWith({
    String? name,
    List<Episode>? episodes,
  }) {
    return PlayRoute(
      name: name ?? this.name,
      episodes: episodes ?? this.episodes,
    );
  }
}

/// 单集信息
@JsonSerializable()
class Episode {
  /// 集数索引（从0开始）
  final int index;

  /// 集数名称（如：第1集, HD中字）
  final String name;

  /// 播放地址
  final String url;

  Episode({
    required this.index,
    required this.name,
    required this.url,
  });

  factory Episode.fromJson(Map<String, dynamic> json) =>
      _$EpisodeFromJson(json);
  Map<String, dynamic> toJson() => _$EpisodeToJson(this);

  Episode copyWith({
    int? index,
    String? name,
    String? url,
  }) {
    return Episode(
      index: index ?? this.index,
      name: name ?? this.name,
      url: url ?? this.url,
    );
  }
}
