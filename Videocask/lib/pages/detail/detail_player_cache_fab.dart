import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/cache_episode_status.dart';
import '../../providers/cache_provider.dart';

import 'detail_ui_tokens.dart';

/// 下载悬浮钮布局位置。
enum DetailCacheFabPlacement {
  /// 全屏播放器内，随控制栏显隐。
  playerOverlay,

  /// 详情页整体右下角，常显（非全屏）。
  pageCorner,
}

/// 播放器 / 详情页缓存下载悬浮入口。
class DetailPlayerCacheFab extends StatelessWidget {
  const DetailPlayerCacheFab({
    super.key,
    required this.movieId,
    required this.sourceId,
    required this.episodeIndex,
    required this.placement,
    required this.isFullScreen,
    required this.bottomOffset,
    required this.onTap,
  });

  final String movieId;
  final String sourceId;
  final int episodeIndex;
  final DetailCacheFabPlacement placement;
  final bool isFullScreen;
  final double bottomOffset;
  final VoidCallback onTap;

  bool _hasDownloadTask(CacheProvider cache) {
    final tasks = cache.tasksForMovie(
      movieId: movieId,
      sourceId: sourceId,
    );
    return tasks.any(
      (t) => t.isWaiting || t.isDownloading || t.isPaused,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Consumer<CacheProvider>(
      builder: (context, cache, _) {
        final status = cache.episodeCacheStatus(
          movieId: movieId,
          episodeIndex: episodeIndex,
          sourceId: sourceId,
        );
        final hasDownloadTask = _hasDownloadTask(cache);
        final accent = detailAccentColor(context);
        final (icon, _) = _iconForStatus(status, accent);
        final statusHint = _statusHint(l10n, status);
        final bg = hasDownloadTask ? accent : accent.withValues(alpha: 0.42);
        final borderColor = hasDownloadTask
            ? accent.withValues(alpha: 0.95)
            : accent.withValues(alpha: 0.65);
        final size = placement == DetailCacheFabPlacement.pageCorner
            ? 48.0
            : (isFullScreen ? 44.0 : 40.0);
        final iconSize = size * 0.5;

        final button = Semantics(
          button: true,
          label: statusHint.isEmpty
              ? l10n.detailPlayerTooltipCache
              : '${l10n.detailPlayerTooltipCache} · $statusHint',
          child: Tooltip(
            message:
                statusHint.isEmpty ? l10n.detailPlayerTooltipCache : statusHint,
            child: Material(
              color: Colors.transparent,
              elevation: hasDownloadTask ? 4 : 2,
              shadowColor: accent.withValues(alpha: 0.35),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Ink(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: iconSize,
                  ),
                ),
              ),
            ),
          ),
        );

        if (placement == DetailCacheFabPlacement.pageCorner) {
          return button;
        }

        return Positioned(
          right: 12,
          bottom: bottomOffset,
          child: button,
        );
      },
    );
  }

  (IconData icon, Color? badgeColor) _iconForStatus(
    CacheEpisodeStatus status,
    Color accent,
  ) {
    switch (status) {
      case CacheEpisodeStatus.completed:
        return (Icons.download_done_rounded, accent);
      case CacheEpisodeStatus.downloading:
        return (Icons.downloading_rounded, accent);
      case CacheEpisodeStatus.waiting:
        return (Icons.hourglass_top_rounded, accent);
      case CacheEpisodeStatus.paused:
        return (Icons.pause_circle_outline_rounded, accent);
      case CacheEpisodeStatus.none:
        return (Icons.download_outlined, null);
    }
  }

  String _statusHint(AppLocalizations l10n, CacheEpisodeStatus status) {
    switch (status) {
      case CacheEpisodeStatus.completed:
        return l10n.detailCacheStatusCompleted;
      case CacheEpisodeStatus.downloading:
        return l10n.detailCacheStatusDownloading;
      case CacheEpisodeStatus.waiting:
        return l10n.detailCacheStatusWaiting;
      case CacheEpisodeStatus.paused:
        return l10n.detailCacheStatusPaused;
      case CacheEpisodeStatus.none:
        return '';
    }
  }
}
