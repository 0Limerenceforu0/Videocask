import 'package:flutter/foundation.dart';

import '../utils/lan_address.dart';
import '../utils/magnet_episode_parser.dart';
import 'local_media_http_server.dart';
import 'playback_url_resolver.dart';

enum DlnaResolveFailure {
  noLanIp,
  noActiveStream,
  unsupportedScheme,
  localServeFailed,
  resolveEmpty,
}

class DlnaResolveResult {
  const DlnaResolveResult.success(this.url) : failure = null;

  const DlnaResolveResult.failure(this.failure) : url = null;

  final String? url;
  final DlnaResolveFailure? failure;

  bool get isSuccess => url != null && url!.isNotEmpty;
}

/// 将各类片源解析为 DLNA 电视可访问的 HTTP(S) URL。
class DlnaPlaybackUrlResolver {
  DlnaPlaybackUrlResolver({
    PlaybackUrlResolver? playbackUrlResolver,
    LocalMediaHttpServer? localServer,
  })  : _playbackUrlResolver = playbackUrlResolver ?? PlaybackUrlResolver(),
        _localServer = localServer ?? LocalMediaHttpServer.instance;

  final PlaybackUrlResolver _playbackUrlResolver;
  final LocalMediaHttpServer _localServer;

  Future<DlnaResolveResult> resolve({
    required String currentPlayUrl,
    String? activeStreamUrl,
    String? episodeUrl,
    required String movieId,
    required int episodeIndex,
    String sourceId = '',
  }) async {
    if (kIsWeb) {
      return const DlnaResolveResult.failure(
        DlnaResolveFailure.unsupportedScheme,
      );
    }

    final play = currentPlayUrl.trim();
    if (play.startsWith(MagnetEpisodeParser.fileUrlPrefix) &&
        (activeStreamUrl == null || activeStreamUrl.trim().isEmpty)) {
      return const DlnaResolveResult.failure(
        DlnaResolveFailure.noActiveStream,
      );
    }

    final lanIp = await LanAddress.preferredIPv4();
    if (lanIp == null || lanIp.isEmpty) {
      return const DlnaResolveResult.failure(DlnaResolveFailure.noLanIp);
    }

    var candidate = activeStreamUrl?.trim() ?? '';
    if (candidate.isEmpty) {
      candidate = await _resolveCandidate(
        currentPlayUrl: currentPlayUrl,
        episodeUrl: episodeUrl,
        movieId: movieId,
        episodeIndex: episodeIndex,
        sourceId: sourceId,
      );
    }

    if (candidate.isEmpty) {
      return const DlnaResolveResult.failure(DlnaResolveFailure.resolveEmpty);
    }

    final lower = candidate.toLowerCase();
    if (lower.startsWith('magnet:') ||
        lower.startsWith('magnet-file://') ||
        candidate == MagnetEpisodeParser.fileUrlPrefix) {
      return const DlnaResolveResult.failure(DlnaResolveFailure.noActiveStream);
    }

    if (lower.startsWith('file://')) {
      final path = Uri.parse(candidate).toFilePath(windows: false);
      final httpUrl = await _localServer.serveFilePath(path);
      if (httpUrl == null || httpUrl.isEmpty) {
        return const DlnaResolveResult.failure(
          DlnaResolveFailure.localServeFailed,
        );
      }
      return DlnaResolveResult.success(httpUrl);
    }

    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return const DlnaResolveResult.failure(
        DlnaResolveFailure.unsupportedScheme,
      );
    }

    final castUrl = await _castUrlForDevice(candidate, lanIp);
    if (castUrl == null || castUrl.isEmpty) {
      return const DlnaResolveResult.failure(
        DlnaResolveFailure.localServeFailed,
      );
    }
    return DlnaResolveResult.success(castUrl);
  }

  Future<String?> _castUrlForDevice(String candidate, String lanIp) async {
    final lower = candidate.toLowerCase();
    if (_isHlsUrl(lower)) {
      final proxied = await _localServer.serveHlsPlaylist(candidate);
      return proxied;
    }
    if (_looksLikeDirectMedia(lower)) {
      final proxied = await _localServer.serveRemoteMedia(candidate);
      return proxied ?? LanAddress.rewriteLocalHost(candidate, lanIp);
    }
    return LanAddress.rewriteLocalHost(candidate, lanIp);
  }

  static bool _isHlsUrl(String lower) {
    return lower.contains('.m3u8') || lower.contains('/hls/');
  }

  static bool _looksLikeDirectMedia(String lower) {
    return lower.contains('.mp4') ||
        lower.contains('.mkv') ||
        lower.contains('.ts') ||
        lower.contains('.webm');
  }

  Future<String> _resolveCandidate({
    required String currentPlayUrl,
    String? episodeUrl,
    required String movieId,
    required int episodeIndex,
    String sourceId = '',
  }) async {
    final play = currentPlayUrl.trim();
    final episode = (episodeUrl ?? play).trim();

    if (play.startsWith(MagnetEpisodeParser.fileUrlPrefix)) {
      return '';
    }

    if (play.startsWith('file://')) {
      return play;
    }

    if (play.startsWith('http://') || play.startsWith('https://')) {
      if (PlaybackUrlResolver.needsWebParse(play)) {
        return _playbackUrlResolver.resolveForPlayback(
          episodeUrl: play,
          movieId: movieId,
          episodeIndex: episodeIndex,
          sourceId: sourceId,
        );
      }
      return play;
    }

    if (episode.isNotEmpty) {
      return _playbackUrlResolver.resolveForPlayback(
        episodeUrl: episode,
        movieId: movieId,
        episodeIndex: episodeIndex,
        sourceId: sourceId,
      );
    }

    return play;
  }
}
