import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/movie.dart';
import 'network/dio_factory.dart';
import 'playback_strategy.dart';
import 'playback_url_resolver.dart';

/// 按播放策略为指定集数选择更合适的线路。
class PlaybackRouteSelector {
  PlaybackRouteSelector({PlaybackUrlResolver? urlResolver})
      : _urlResolver = urlResolver ?? PlaybackUrlResolver();

  final PlaybackUrlResolver _urlResolver;

  /// 线路名称画质分（越高越清晰），用于 quality / balanced。
  static int routeQualityScore(String routeName) {
    final n = routeName.toLowerCase();
    if (n.contains('4k') || n.contains('2160') || n.contains('uhd')) {
      return 100;
    }
    if (n.contains('1080') || n.contains('蓝光') || n.contains('bd')) {
      return 80;
    }
    if (n.contains('超清') || n.contains('720') || n.contains('高清')) {
      return 60;
    }
    if (n.contains('标清') || n.contains('流畅') || n.contains('普清')) {
      return 30;
    }
    if (n.contains('hd')) return 55;
    return 40;
  }

  /// 默认清晰度设置与线路名匹配加分。
  ///
  /// 只认完整的画质词：早先的 `'标'`、`'hd'`、`'bd'` 这类短词会把「标签」
  /// 「hdplay」之类的线路名误判成对应画质档，反而让选线偏离用户预期。
  static int defaultQualityBonus(String routeName, String defaultQuality) {
    if (defaultQuality == '自动') return 0;
    final keywords = <String, List<String>>{
      '标清': ['标清', '流畅', '普清', '360', '480'],
      '高清': ['高清', '超清', '720'],
      '1080P': ['1080', '蓝光', 'bd'],
      '4K': ['4k', '2160', 'uhd'],
    };
    final keys = keywords[defaultQuality];
    if (keys == null) return 0;
    final n = routeName.toLowerCase();
    for (final k in keys) {
      if (n.contains(k.toLowerCase())) return 25;
    }
    return 0;
  }

  /// 在 [movie.playRoutes] 中为 [episodeIndex] 选线；失败时返回 [fallbackIndex]。
  Future<int> selectBestRoute({
    required Movie movie,
    required int episodeIndex,
    required String strategy,
    String defaultQuality = '自动',
    int fallbackIndex = 0,
    Set<int> excludeRouteIndices = const {},
  }) async {
    if (movie.playRoutes.isEmpty) return 0;
    if (movie.playRoutes.length == 1) return 0;

    final candidates = <_RouteCandidate>[];
    for (var i = 0; i < movie.playRoutes.length; i++) {
      if (excludeRouteIndices.contains(i)) continue;
      final route = movie.playRoutes[i];
      if (episodeIndex < 0 || episodeIndex >= route.episodes.length) continue;
      final url = route.episodes[episodeIndex].url;
      if (url.isEmpty) continue;
      candidates.add(
        _RouteCandidate(
          index: i,
          routeName: route.name,
          episodeUrl: url,
        ),
      );
    }

    if (candidates.isEmpty) {
      return fallbackIndex.clamp(0, movie.playRoutes.length - 1);
    }
    if (candidates.length == 1) return candidates.first.index;

    final timeoutMs =
        PlaybackStrategyConfig.fromKey(strategy).routeProbeTimeoutMs;
    final probes = await Future.wait(
      candidates.map((c) async {
        final probeUrl = await _urlResolver.resolveForProbe(c.episodeUrl);
        final latency = await probeStreamLatency(
          probeUrl,
          timeoutMs: timeoutMs,
        );
        return _ProbedRoute(
          candidate: c,
          latencyMs: latency,
          qualityScore: routeQualityScore(c.routeName) +
              defaultQualityBonus(c.routeName, defaultQuality),
        );
      }),
    );

    final viable = probes.where((p) => p.latencyMs != null).toList();
    if (viable.isEmpty) {
      return fallbackIndex.clamp(0, movie.playRoutes.length - 1);
    }

    switch (strategy) {
      case 'smooth':
        viable.sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
        return viable.first.candidate.index;
      case 'quality':
        viable.sort((a, b) {
          final q = b.qualityScore.compareTo(a.qualityScore);
          if (q != 0) return q;
          return a.latencyMs!.compareTo(b.latencyMs!);
        });
        return viable.first.candidate.index;
      default:
        viable.sort((a, b) {
          final scoreA = _balancedScore(a);
          final scoreB = _balancedScore(b);
          return scoreB.compareTo(scoreA);
        });
        return viable.first.candidate.index;
    }
  }

  double _balancedScore(_ProbedRoute route) {
    final latency = route.latencyMs!.toDouble();
    final latencyScore = (8000 - latency.clamp(0, 8000)) / 80;
    return route.qualityScore * 0.45 + latencyScore * 0.55;
  }

  /// 对可播放 URL 做 Range 探针，返回耗时（毫秒）；失败为 null。
  static Future<int?> probeStreamLatency(
    String url, {
    int timeoutMs = 4000,
  }) async {
    if (url.isEmpty) return null;
    final lower = url.toLowerCase();
    if (lower.startsWith('file://')) {
      return 1;
    }
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return null;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final dio = await DioFactory.plainText(
        connectTimeout: Duration(milliseconds: timeoutMs),
        receiveTimeout: Duration(milliseconds: timeoutMs),
      );
      await dio.get<String>(
        url,
        options: Options(
          headers: const {'Range': 'bytes=0-32767'},
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      debugPrint('线路探针失败: $url → $e');
      return null;
    }
  }
}

class _RouteCandidate {
  const _RouteCandidate({
    required this.index,
    required this.routeName,
    required this.episodeUrl,
  });

  final int index;
  final String routeName;
  final String episodeUrl;
}

class _ProbedRoute {
  const _ProbedRoute({
    required this.candidate,
    required this.latencyMs,
    required this.qualityScore,
  });

  final _RouteCandidate candidate;
  final int? latencyMs;
  final int qualityScore;
}
