import '../../l10n/app_localizations.dart';
import '../../models/movie.dart';
import '../../models/watch_history.dart';
import '../../providers/history_provider.dart';

import 'detail_player.dart';

/// 详情页观看历史 / 断点续播协调（从 [DetailPage] 抽离，便于单测与维护）。
class DetailResumeCoordinator {
  DetailResumeCoordinator._();

  /// 进入详情时解析应恢复的历史记录。
  static WatchHistory? resolveHistory({
    required HistoryProvider history,
    required String movieId,
    required String sourceId,
    required String magnetUri,
  }) {
    return history.findHistoryForDetail(
      movieId: movieId,
      sourceId: sourceId,
      magnetUri: magnetUri,
    );
  }

  /// 将 [WatchHistory] 同步到播放器模块与桌面线路索引。
  static DetailWatchHistoryApply applyHistory(
    WatchHistory? history,
    Movie movie,
    DetailPlayer player,
    int desktopRouteIndex,
  ) {
    if (history == null) {
      player.hasHistory = false;
      player.lastPlayProgress = 0;
      player.lastPlayDuration = 0;
      player.pendingResumePosition = null;
      player.resumeTargetRouteIndex = null;
      player.resumeTargetEpisodeIndex = null;
      return DetailWatchHistoryApply(desktopRouteIndex: desktopRouteIndex);
    }

    player.hasHistory = true;
    player.lastPlayProgress = history.progress;
    player.lastPlayDuration = history.duration;

    final rc = movie.playRoutes.length;
    final routeIdx = rc > 0 ? history.routeIndex.clamp(0, rc - 1) : 0;
    var episodeIdx = history.episodeIndex;
    var nextDesktopRoute = desktopRouteIndex;
    if (rc > 0) {
      final episodes = movie.playRoutes[routeIdx].episodes;
      if (episodes.isNotEmpty) {
        episodeIdx = _resolveEpisodeIndex(history, episodes);
      } else {
        episodeIdx = 0;
      }
      nextDesktopRoute = routeIdx;
    }

    player.resumeTargetRouteIndex = routeIdx;
    player.resumeTargetEpisodeIndex = episodeIdx;
    player.pendingResumePosition =
        history.progress > 0 ? Duration(milliseconds: history.progress) : null;

    return DetailWatchHistoryApply(desktopRouteIndex: nextDesktopRoute);
  }

  /// 优先按历史 [WatchHistory.episodeName] 匹配集数（综艺等线路顺序不一致时更可靠）。
  static int _resolveEpisodeIndex(
    WatchHistory history,
    List<Episode> episodes,
  ) {
    final savedName = history.episodeName.trim();
    if (savedName.isNotEmpty) {
      for (var i = 0; i < episodes.length; i++) {
        if (episodes[i].name.trim() == savedName) return i;
      }
    }
    return history.episodeIndex.clamp(0, episodes.length - 1);
  }

  static int episodeIndexForResume(
    Movie movie,
    int routeIndex,
    DetailPlayer player,
  ) {
    if (routeIndex < 0 || routeIndex >= movie.playRoutes.length) return 0;
    final episodes = movie.playRoutes[routeIndex].episodes;
    if (episodes.isEmpty) return 0;
    if (player.resumeTargetRouteIndex == routeIndex &&
        player.resumeTargetEpisodeIndex != null) {
      final ei = player.resumeTargetEpisodeIndex!;
      if (ei >= 0 && ei < episodes.length) return ei;
    }
    return 0;
  }

  static String historyOverlayLabel(
    AppLocalizations l10n,
    DetailPlayer player,
  ) {
    final ep =
        (player.resumeTargetEpisodeIndex ?? player.currentEpisodeIndex) + 1;
    final pct = player.lastPlayDuration > 0
        ? (player.lastPlayProgress / player.lastPlayDuration * 100)
            .clamp(0.0, 100.0)
        : player.progressPercent * 100;
    return l10n.detailHistoryOverlay(ep, pct.toStringAsFixed(0));
  }
}

/// [_syncWatchHistory] 对 `_desktopRouteIndex` 的更新结果。
class DetailWatchHistoryApply {
  const DetailWatchHistoryApply({required this.desktopRouteIndex});

  final int desktopRouteIndex;
}
