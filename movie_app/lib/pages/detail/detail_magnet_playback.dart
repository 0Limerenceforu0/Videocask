import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import '../../l10n/app_localizations.dart';
import '../../models/movie.dart';
import '../../services/torrent_player_service.dart';
import '../../utils/magnet_episode_parser.dart';

import 'detail_player.dart';
import 'detail_torrent.dart';
import 'playback_error_type.dart';

typedef DetailMagnetMounted = bool Function();
typedef DetailMagnetVoidCallback = void Function();

typedef DetailMagnetFilesCallback = void Function(List<TorrentFileItem> files);

/// 磁力 P2P 边下边播（从 [DetailPage] 抽离）。
class DetailMagnetPlayback {
  DetailMagnetPlayback({
    required this.player,
    required this.torrent,
    required this.isMounted,
    required this.onStateChanged,
    required this.cancelRouteFallback,
    required this.applyPlayerTuning,
    required this.startHideTimer,
    required this.startProgressPersistTimer,
    required this.scheduleSubtitleMatch,
    required this.l10n,
    this.onStreamReady,
    this.onTorrentFilesReady,
  });

  final DetailPlayer player;
  final DetailTorrent torrent;
  final DetailMagnetMounted isMounted;
  final DetailMagnetVoidCallback onStateChanged;
  final DetailMagnetVoidCallback cancelRouteFallback;
  final Future<void> Function() applyPlayerTuning;
  final DetailMagnetVoidCallback startHideTimer;
  final DetailMagnetVoidCallback startProgressPersistTimer;
  final Future<void> Function(Movie movie, String playUrl)
      scheduleSubtitleMatch;
  final AppLocalizations l10n;
  final Future<void> Function(Movie movie)? onStreamReady;
  final DetailMagnetFilesCallback? onTorrentFilesReady;

  Future<void> play(
    String magnetUri,
    Movie movie, {
    int episodeIndex = 0,
    int? preferredFileIndex,
  }) async {
    if (kIsWeb || !isMounted() || magnetUri.isEmpty) return;

    cancelRouteFallback();

    final playVersion = ++torrent.magnetPlayVersion;
    final sameTorrent = player.lastMagnetUri == magnetUri &&
        player.torrentService.isInitialized &&
        player.torrentService.files.isNotEmpty &&
        player.torrentService.state != TorrentPlayState.error;

    if (sameTorrent && preferredFileIndex != null) {
      await _playFileIndex(
        magnetUri: magnetUri,
        movie: movie,
        playVersion: playVersion,
        fileIndex: preferredFileIndex,
        episodeIndex: episodeIndex,
      );
      return;
    }

    await player.playerService.stop();

    player.lastMagnetUri = magnetUri;
    player.magnetSourcePreparing = true;
    player.torrentStep = 1;
    player.torrentMessage = l10n.detailMagnetParsingMeta;
    player.playbackErrorType = PlaybackErrorType.none;
    player.playerErrorMessage = '';
    onStateChanged();

    try {
      await player.torrentService.init();
      if (!isMounted() || playVersion != torrent.magnetPlayVersion) return;
      if (!player.torrentService.isInitialized) {
        _fail(l10n.detailMagnetAddFailed);
        return;
      }

      final added = await player.torrentService.addMagnet(magnetUri);
      if (!isMounted() || playVersion != torrent.magnetPlayVersion) return;
      if (!added) {
        _fail(l10n.detailMagnetAddFailed);
        return;
      }

      final pickedFileIndex = await _waitForPlayableFile(
        playVersion,
        episodeIndex: episodeIndex,
        preferredFileIndex: preferredFileIndex,
        torrentTitle: movie.name,
      );
      if (!isMounted() || playVersion != torrent.magnetPlayVersion) return;
      if (pickedFileIndex == null) {
        final msg = player.torrentService.errorMessage;
        _fail(msg.isNotEmpty ? msg : l10n.detailMagnetNoVideoFile);
        return;
      }

      await _playFileIndex(
        magnetUri: magnetUri,
        movie: movie,
        playVersion: playVersion,
        fileIndex: pickedFileIndex,
        episodeIndex: episodeIndex,
      );
    } catch (e, st) {
      debugPrint('DetailMagnetPlayback.play failed: $e\n$st');
      if (isMounted() && playVersion == torrent.magnetPlayVersion) {
        _fail('$e');
      }
    }
  }

  Future<void> _playFileIndex({
    required String magnetUri,
    required Movie movie,
    required int playVersion,
    required int fileIndex,
    required int episodeIndex,
  }) async {
    player.torrentStep = 3;
    player.torrentMessage = l10n.detailMagnetBuffering;
    onStateChanged();

    final streamUrl = await player.torrentService.playFile(fileIndex);
    if (!isMounted() || playVersion != torrent.magnetPlayVersion) return;
    if (streamUrl == null || streamUrl.isEmpty) {
      _fail(l10n.detailMagnetStreamFailed);
      return;
    }

    player.lastMagnetUri = magnetUri;
    player.currentPlayUrl = MagnetEpisodeParser.fileUrl(fileIndex);
    player.activeStreamUrl = streamUrl;
    // 记下当前视频文件名，字幕匹配优先用它（release 名命中率最高）。
    player.currentMagnetFileName = _fileNameOfIndex(fileIndex);
    player.currentEpisodeIndex = episodeIndex;
    player.currentRouteIndex = 0;
    player.showReplayOverlay = false;

    await player.ensureInitialized();
    if (!isMounted() || playVersion != torrent.magnetPlayVersion) return;

    await applyPlayerTuning();
    if (!isMounted() || playVersion != torrent.magnetPlayVersion) return;

    // 磁力本地 HTTP 流在 open 后立即 seek 易触发 mpv/libtorrent 原生崩溃；
    // 续播改由 onDurationChanged → _applyPendingResume 在时长就绪后再 seek。
    player.resetResumeConsumeForNewOpen();
    await player.playerService.play(streamUrl);
    if (!isMounted()) return;

    player.magnetSourcePreparing = false;
    player.playback.onOpenSucceeded();
    player.torrentStep = 0;
    player.torrentMessage = '';
    onStateChanged();
    startHideTimer();
    startProgressPersistTimer();
    unawaited(onStreamReady?.call(movie));
    unawaited(
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (!isMounted()) return;
        unawaited(scheduleSubtitleMatch(movie, streamUrl));
      }),
    );
  }

  /// 取指定索引的种子内文件名（找不到时返回空串）。
  String _fileNameOfIndex(int fileIndex) {
    final files = player.torrentService.files;
    for (final f in files) {
      if (f.index == fileIndex) return f.name;
    }
    if (fileIndex >= 0 && fileIndex < files.length) {
      return files[fileIndex].name;
    }
    return '';
  }

  Future<int?> _waitForPlayableFile(
    int playVersion, {
    int episodeIndex = 0,
    int? preferredFileIndex,
    String? torrentTitle,
  }) async {
    const maxWait = Duration(minutes: 2);
    const interval = Duration(milliseconds: 300);
    var elapsed = Duration.zero;

    while (elapsed < maxWait) {
      if (!isMounted() || playVersion != torrent.magnetPlayVersion) {
        return null;
      }

      final svc = player.torrentService;
      if (svc.state == TorrentPlayState.error) return null;

      final files = svc.files;
      if (files.isNotEmpty) {
        onTorrentFilesReady?.call(files);
        final pick = MagnetEpisodeParser.pickFileIndex(
          files,
          episodeIndex: episodeIndex,
          torrentTitle: torrentTitle,
          preferredFileIndex: preferredFileIndex,
        );
        if (pick != null) return pick;
      }

      if (svc.state == TorrentPlayState.fetchingMeta) {
        player.torrentStep = 1;
        player.torrentMessage = l10n.detailMagnetParsingMeta;
      } else {
        player.torrentStep = 2;
        player.torrentMessage = l10n.detailMagnetConnectingPeers;
      }
      onStateChanged();

      await Future<void>.delayed(interval);
      elapsed += interval;
    }
    return null;
  }

  void _fail(String message) {
    player.magnetSourcePreparing = false;
    player.torrentStep = -1;
    player.torrentMessage = message;
    player.playerErrorMessage = message;
    player.playbackErrorType = PlaybackErrorType.magnetFailed;
    if (isMounted()) onStateChanged();
  }
}
