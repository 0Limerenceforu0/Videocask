// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'movie.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MovieAlternateSource _$MovieAlternateSourceFromJson(
        Map<String, dynamic> json) =>
    MovieAlternateSource(
      sourceId: json['sourceId'] as String,
      movieId: json['movieId'] as String,
      sourceDisplayName: json['sourceDisplayName'] as String,
    );

Map<String, dynamic> _$MovieAlternateSourceToJson(
        MovieAlternateSource instance) =>
    <String, dynamic>{
      'sourceId': instance.sourceId,
      'movieId': instance.movieId,
      'sourceDisplayName': instance.sourceDisplayName,
    };

Movie _$MovieFromJson(Map<String, dynamic> json) => Movie(
      id: json['id'] as String,
      sourceId: json['sourceId'] as String? ?? '',
      name: json['name'] as String,
      alias: json['alias'] as String? ?? '',
      cover: json['cover'] as String? ?? '',
      backdrop: json['backdrop'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      region: json['region'] as String? ?? '',
      year: json['year'] as String? ?? '',
      director: json['director'] as String? ?? '',
      actors: (json['actors'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      description: json['description'] as String? ?? '',
      updateStatus: json['updateStatus'] as String? ?? '',
      playRoutes: (json['playRoutes'] as List<dynamic>?)
              ?.map((e) => PlayRoute.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      relatedMovies: (json['relatedMovies'] as List<dynamic>?)
              ?.map((e) => Movie.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      language: json['language'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      isCompleted: json['isCompleted'] as bool? ?? false,
      alternateSources: (json['alternateSources'] as List<dynamic>?)
              ?.map((e) =>
                  MovieAlternateSource.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      lastUpdate: Movie._dateTimeFromJson(json['lastUpdate']),
      createdAt: Movie._dateTimeFromJson(json['createdAt']),
    );

Map<String, dynamic> _$MovieToJson(Movie instance) => <String, dynamic>{
      'id': instance.id,
      'sourceId': instance.sourceId,
      'name': instance.name,
      'alias': instance.alias,
      'cover': instance.cover,
      'backdrop': instance.backdrop,
      'rating': instance.rating,
      'genres': instance.genres,
      'region': instance.region,
      'year': instance.year,
      'director': instance.director,
      'actors': instance.actors,
      'description': instance.description,
      'updateStatus': instance.updateStatus,
      'playRoutes': instance.playRoutes,
      'relatedMovies': instance.relatedMovies,
      'language': instance.language,
      'duration': instance.duration,
      'isCompleted': instance.isCompleted,
      'lastUpdate': Movie._dateTimeToJson(instance.lastUpdate),
      'createdAt': Movie._dateTimeToJson(instance.createdAt),
      'alternateSources': instance.alternateSources,
    };

PlayRoute _$PlayRouteFromJson(Map<String, dynamic> json) => PlayRoute(
      name: json['name'] as String,
      episodes: (json['episodes'] as List<dynamic>?)
              ?.map((e) => Episode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$PlayRouteToJson(PlayRoute instance) => <String, dynamic>{
      'name': instance.name,
      'episodes': instance.episodes,
    };

Episode _$EpisodeFromJson(Map<String, dynamic> json) => Episode(
      index: (json['index'] as num).toInt(),
      name: json['name'] as String,
      url: json['url'] as String,
    );

Map<String, dynamic> _$EpisodeToJson(Episode instance) => <String, dynamic>{
      'index': instance.index,
      'name': instance.name,
      'url': instance.url,
    };
