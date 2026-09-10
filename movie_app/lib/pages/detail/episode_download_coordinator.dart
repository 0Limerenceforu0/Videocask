import 'package:flutter/foundation.dart' show kIsWeb;

import '../../l10n/app_localizations.dart';
import '../../models/cache_item.dart';
import '../../models/movie.dart';
import '../../services/cache_service.dart';
import '../../services/playback_url_resolver.dart';

/// 详情页单集下载结果（与 UI SnackBar 一一对应）。
enum EpisodeDownloadOutcome {
  queued,
  resumed,
  alreadyCompleted,
  alreadyActive,
  skipped,
}

/// 跳过下载时的原因（映射到 l10n）。
enum EpisodeDownloadSkipReason {
  webUnsupported,
  magnetUnsupported,
  noEpisode,
  parseFailed,
  unsupportedUrl,
}

/// 详情页离线缓存入队协调（纯逻辑，便于穷举单测）。
class EpisodeDownloadCoordinator {
  EpisodeDownloadCoordinator._();

  /// 平台 / 详情类型 / 集数是否允许继续下载流程。
  static EpisodeDownloadSkipReason? preflightSkipReason({
    required bool isMagnetDetail,
    required Movie movie,
    required int routeIndex,
    required int episodeIndex,
  }) {
    if (kIsWeb) return EpisodeDownloadSkipReason.webUnsupported;
    if (isMagnetDetail) return EpisodeDownloadSkipReason.magnetUnsupported;
    if (movie.playRoutes.isEmpty) {
      return EpisodeDownloadSkipReason.noEpisode;
    }

    final ri = routeIndex.clamp(0, movie.playRoutes.length - 1);
    final route = movie.playRoutes[ri];
    if (route.episodes.isEmpty ||
        episodeIndex < 0 ||
        episodeIndex >= route.episodes.length) {
      return EpisodeDownloadSkipReason.noEpisode;
    }

    if (route.episodes[episodeIndex].url.trim().isEmpty) {
      return EpisodeDownloadSkipReason.noEpisode;
    }
    return null;
  }

  /// 已有缓存任务时的结果（无任务则返回 null，表示应继续解析 URL）。
  static EpisodeDownloadOutcome? outcomeForExistingTask(CacheItem? existing) {
    if (existing == null) return null;
    if (existing.isCompleted) {
      return EpisodeDownloadOutcome.alreadyCompleted;
    }
    if (existing.isDownloading || existing.isWaiting) {
      return EpisodeDownloadOutcome.alreadyActive;
    }
    if (existing.isPaused || existing.isFailed) {
      return EpisodeDownloadOutcome.resumed;
    }
    return null;
  }

  /// 解析后的 URL 是否可入队；不可则返回跳过原因。
  static EpisodeDownloadSkipReason? validateResolvedUrl({
    required String episodePageUrl,
    required String downloadUrl,
  }) {
    if (PlaybackUrlResolver.needsWebParse(episodePageUrl) &&
        (downloadUrl == episodePageUrl ||
            PlaybackUrlResolver.needsWebParse(downloadUrl))) {
      return EpisodeDownloadSkipReason.parseFailed;
    }

    final lower = downloadUrl.trim().toLowerCase();
    if (lower.startsWith('magnet:') ||
        lower.startsWith('file:') ||
        lower.startsWith('magnet-file:')) {
      return EpisodeDownloadSkipReason.unsupportedUrl;
    }
    if (!CacheService.isCacheableUrl(downloadUrl)) {
      return EpisodeDownloadSkipReason.unsupportedUrl;
    }
    return null;
  }

  /// 批量下载：计入「已加入 / 已恢复」的数量。
  static int countBatchAdded(Iterable<EpisodeDownloadOutcome> outcomes) {
    var added = 0;
    for (final outcome in outcomes) {
      if (outcome == EpisodeDownloadOutcome.queued ||
          outcome == EpisodeDownloadOutcome.resumed) {
        added++;
      }
    }
    return added;
  }

  /// 集数是否可被多选面板选中（已完成或空 URL 不可选）。
  static bool isEpisodeSelectableForBatch({
    required String episodeUrl,
    required bool cacheCompleted,
  }) {
    if (cacheCompleted) return false;
    return episodeUrl.trim().isNotEmpty;
  }

  static String skipMessage(
    AppLocalizations l10n,
    EpisodeDownloadSkipReason reason,
  ) {
    switch (reason) {
      case EpisodeDownloadSkipReason.webUnsupported:
        return l10n.detailCacheWebUnsupported;
      case EpisodeDownloadSkipReason.magnetUnsupported:
        return l10n.detailCacheMagnetUnsupported;
      case EpisodeDownloadSkipReason.noEpisode:
        return l10n.detailCacheNoEpisode;
      case EpisodeDownloadSkipReason.parseFailed:
        return l10n.detailCacheParseFailed;
      case EpisodeDownloadSkipReason.unsupportedUrl:
        return l10n.detailCacheUnsupportedUrl;
    }
  }

  /// 下载请求 HTTP 头（Referer 来自采集站播放页）。
  static Map<String, String> fetchHeadersForItem(
    CacheItem item, {
    String? url,
  }) {
    return CacheService.headersFor(item, url: url);
  }

  /// 下载完成后校验文件体积，过小视为失败（如 HTML 错误页）。
  static bool isValidDownloadedVideoSize(int bytes) {
    return bytes >= CacheService.minValidVideoBytes;
  }
}
