import 'dart:async' show Timer, unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/routes.dart';
import '../../l10n/app_localizations.dart';
import '../../models/cache_item.dart';
import '../../models/movie.dart';
import '../../providers/cache_provider.dart';
import '../../services/cache_service.dart';
import '../../utils/cache_speed_formatter.dart';
import '../../utils/episode_display_label.dart';
import 'detail_cache_episode_picker.dart';

/// 详情页缓存面板所需的影片上下文。
class DetailCacheMovieScope {
  const DetailCacheMovieScope({
    required this.movieId,
    required this.sourceId,
    required this.movieName,
    required this.movieCover,
    required this.episodeIndex,
    required this.episodeName,
    required this.episodes,
    required this.isMagnetDetail,
    required this.onDownloadEpisode,
    required this.onDownloadEpisodes,
  });

  final String movieId;
  final String sourceId;
  final String movieName;
  final String movieCover;
  final int episodeIndex;
  final String episodeName;
  final List<Episode> episodes;
  final bool isMagnetDetail;
  final Future<void> Function(int episodeIndex) onDownloadEpisode;
  final Future<void> Function(List<int> episodeIndices) onDownloadEpisodes;
}

/// 详情页缓存管理（面板 + 刷新）。
class DetailCache {
  /// 是否显示缓存下拉面板
  bool showCachePanel = false;

  /// 缓存下拉面板 OverlayEntry
  OverlayEntry? cachePanelEntry;

  /// 缓存刷新定时器
  Timer? cacheRefreshTimer;

  /// 加载缓存列表
  Future<void> loadCache(BuildContext context) async {
    await context.read<CacheProvider>().loadCacheItems();
  }

  /// 显示缓存面板
  void displayCachePanel(
    BuildContext context,
    DetailCacheMovieScope scope, {
    /// 非全屏移动端：面板与遮罩从该 Y 以下开始，避免挡住顶部播放器。
    double? belowTopInset,
  }) {
    if (cachePanelEntry != null) return;

    cacheRefreshTimer?.cancel();

    cachePanelEntry = OverlayEntry(
      builder: (overlayContext) => _DetailCachePanel(
        scope: scope,
        belowTopInset: belowTopInset,
        onClose: hideCachePanel,
        onRefresh: () {
          if (!overlayContext.mounted) return;
          unawaited(overlayContext.read<CacheProvider>().loadCacheItems());
          cachePanelEntry?.markNeedsBuild();
        },
      ),
    );

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      debugPrint('DetailCache: 当前页面无 Overlay，无法显示缓存面板');
      cachePanelEntry = null;
      return;
    }
    overlay.insert(cachePanelEntry!);
    showCachePanel = true;

    cacheRefreshTimer?.cancel();
    cacheRefreshTimer =
        Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (cachePanelEntry == null) return;
      await context.read<CacheProvider>().loadCacheItems();
      cachePanelEntry?.markNeedsBuild();
    });
  }

  /// 隐藏缓存面板
  void hideCachePanel() {
    cacheRefreshTimer?.cancel();
    cacheRefreshTimer = null;
    if (cachePanelEntry != null) {
      cachePanelEntry?.remove();
      cachePanelEntry = null;
      showCachePanel = false;
    }
  }

  /// 释放资源
  void dispose() {
    hideCachePanel();
  }
}

class _DetailCachePanel extends StatefulWidget {
  const _DetailCachePanel({
    required this.scope,
    required this.onClose,
    required this.onRefresh,
    this.belowTopInset,
  });

  final DetailCacheMovieScope scope;
  final VoidCallback onClose;
  final VoidCallback onRefresh;
  final double? belowTopInset;

  @override
  State<_DetailCachePanel> createState() => _DetailCachePanelState();
}

class _DetailCachePanelState extends State<_DetailCachePanel> {
  late Set<int> _selectedIndices;

  @override
  void initState() {
    super.initState();
    _selectedIndices = {widget.scope.episodeIndex};
  }

  DetailCacheMovieScope get scope => widget.scope;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF222325) : Colors.white;
    final textColor =
        isDark ? const Color(0xFFE6E6E6) : const Color(0xFF212121);
    final subTextColor =
        isDark ? const Color(0xFF999999) : const Color(0xFF999999);
    final mq = MediaQuery.of(context);
    final useBelowPlayer = widget.belowTopInset != null;
    final panelTop =
        useBelowPlayer ? widget.belowTopInset! + 8 : mq.padding.top + 56;
    final maxPanelHeight = useBelowPlayer
        ? (mq.size.height - panelTop - mq.padding.bottom - 24)
            .clamp(120.0, 520.0)
        : 520.0;

    return Stack(
      children: [
        if (useBelowPlayer)
          Positioned(
            top: widget.belowTopInset,
            left: 0,
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: widget.onClose,
              behavior: HitTestBehavior.opaque,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
            ),
          )
        else
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onClose,
              behavior: HitTestBehavior.opaque,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
            ),
          ),
        Positioned(
          top: panelTop,
          left: 16,
          right: 16,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: cardColor,
            child: Consumer<CacheProvider>(
              builder: (context, provider, _) {
                final items = provider.tasksForMovie(
                  movieId: scope.movieId,
                  sourceId: scope.sourceId,
                );
                final currentTask = provider.findTaskForEpisode(
                  movieId: scope.movieId,
                  episodeIndex: scope.episodeIndex,
                  sourceId: scope.sourceId,
                );
                final canDownload = !kIsWeb && !scope.isMagnetDetail;

                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxPanelHeight),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.detailCachePanelTitle,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.detailClose,
                              onPressed: widget.onClose,
                              icon: Icon(Icons.close, color: subTextColor),
                            ),
                          ],
                        ),
                        if (currentTask != null) ...[
                          const SizedBox(height: 8),
                          _CurrentEpisodeStatus(
                            item: currentTask,
                            episodeLabel: _episodeLabel(
                              l10n,
                              scope.episodeIndex,
                              scope.episodeName,
                            ),
                            textColor: textColor,
                            subTextColor: subTextColor,
                            theme: theme,
                          ),
                        ],
                        if (canDownload && scope.episodes.length > 1) ...[
                          const SizedBox(height: 12),
                          DetailCacheEpisodePicker(
                            episodes: scope.episodes,
                            movieId: scope.movieId,
                            sourceId: scope.sourceId,
                            playingEpisodeIndex: scope.episodeIndex,
                            selectedIndices: _selectedIndices,
                            onSelectionChanged: (next) {
                              setState(() => _selectedIndices = next);
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (canDownload)
                          scope.episodes.length > 1
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () async {
                                          await scope.onDownloadEpisode(
                                            scope.episodeIndex,
                                          );
                                          widget.onRefresh();
                                        },
                                        icon: const Icon(
                                          Icons.playlist_play_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          l10n.detailCacheDownloadCurrent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: _selectedIndices.isEmpty
                                            ? null
                                            : () async {
                                                final indices = _selectedIndices
                                                    .toList()
                                                  ..sort();
                                                await scope.onDownloadEpisodes(
                                                  indices,
                                                );
                                                widget.onRefresh();
                                              },
                                        icon: const Icon(
                                          Icons.download_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          l10n.detailCacheDownloadSelected(
                                            _selectedIndices.length,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : FilledButton.icon(
                                  onPressed: () async {
                                    await scope.onDownloadEpisode(
                                      scope.episodeIndex,
                                    );
                                    widget.onRefresh();
                                  },
                                  icon: const Icon(
                                    Icons.download_outlined,
                                    size: 20,
                                  ),
                                  label: Text(l10n.detailCacheDownloadCurrent),
                                )
                        else if (kIsWeb)
                          Text(
                            l10n.cacheWebBanner,
                            style: TextStyle(color: subTextColor, fontSize: 13),
                          )
                        else if (scope.isMagnetDetail)
                          Text(
                            l10n.detailCacheMagnetUnsupported,
                            style: TextStyle(color: subTextColor, fontSize: 13),
                          ),
                        const SizedBox(height: 12),
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              l10n.detailCacheEmptyForMovie,
                              style:
                                  TextStyle(color: subTextColor, fontSize: 13),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              return _CacheTaskTile(
                                item: items[index],
                                textColor: textColor,
                                subTextColor: subTextColor,
                                theme: theme,
                                onAction: widget.onRefresh,
                              );
                            },
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              widget.onClose();
                              AppRoutes.toCacheManager(context);
                            },
                            child: Text(l10n.detailCacheManageAll),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

String _episodeLabel(AppLocalizations l10n, int index, String name) {
  if (name.isNotEmpty) {
    return EpisodeDisplayLabel.forEpisode(name: name, index: index).full;
  }
  return l10n.detailEpisodeLabel(index + 1);
}

class _CurrentEpisodeStatus extends StatelessWidget {
  const _CurrentEpisodeStatus({
    required this.item,
    required this.episodeLabel,
    required this.textColor,
    required this.subTextColor,
    required this.theme,
  });

  final CacheItem item;
  final String episodeLabel;
  final Color textColor;
  final Color subTextColor;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final statusText = _statusLabel(l10n, item);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            episodeLabel,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            statusText,
            style: TextStyle(color: subTextColor, fontSize: 12),
          ),
          if (item.showsDownloadProgress) ...[
            const SizedBox(height: 8),
            _DetailCacheProgressDetails(
              item: item,
              subTextColor: subTextColor,
              theme: theme,
            ),
          ],
        ],
      ),
    );
  }
}

class _CacheTaskTile extends StatelessWidget {
  const _CacheTaskTile({
    required this.item,
    required this.textColor,
    required this.subTextColor,
    required this.theme,
    required this.onAction,
  });

  final CacheItem item;
  final Color textColor;
  final Color subTextColor;
  final ThemeData theme;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<CacheProvider>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.35),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.episodeName.isNotEmpty
                      ? EpisodeDisplayLabel.forEpisode(
                          name: item.episodeName,
                          index: item.episodeIndex,
                        ).primary
                      : l10n.detailEpisodeLabel(item.episodeIndex + 1),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _statusLabel(l10n, item),
                  style: TextStyle(color: subTextColor, fontSize: 11),
                ),
                if (item.showsDownloadProgress) ...[
                  const SizedBox(height: 6),
                  _DetailCacheProgressDetails(
                    item: item,
                    subTextColor: subTextColor,
                    theme: theme,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
          if (item.isDownloading)
            IconButton(
              tooltip: l10n.detailCachePause,
              icon: const Icon(Icons.pause, size: 20),
              onPressed: () {
                provider.pauseDownload(item.id);
                onAction();
              },
            )
          else if (item.isPaused || item.isFailed)
            IconButton(
              tooltip: l10n.detailCacheResume,
              icon: const Icon(Icons.play_arrow, size: 20),
              onPressed: () async {
                await provider.resumeDownload(item.id);
                await provider.scheduleWaitingDownloads();
                onAction();
              },
            ),
          IconButton(
            tooltip: l10n.detailCacheDelete,
            icon: Icon(Icons.delete_outline, size: 20, color: subTextColor),
            onPressed: () async {
              await provider.deleteCache(item.id);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.detailCacheDeleted)),
              );
              onAction();
            },
          ),
        ],
      ),
    );
  }
}

String _statusLabel(AppLocalizations l10n, CacheItem item) {
  if (item.isCompleted) {
    return '${l10n.detailCacheStatusCompleted} · ${CacheService.formatFileSize(item.fileSize)}';
  }
  if (item.isDownloading) {
    return l10n.detailCacheStatusDownloading;
  }
  if (item.isPaused) return l10n.detailCacheStatusPaused;
  if (item.isFailed) return l10n.detailCacheStatusFailed;
  if (item.isWaiting) return l10n.detailCacheStatusWaiting;
  return item.status;
}

class _DetailCacheProgressDetails extends StatelessWidget {
  const _DetailCacheProgressDetails({
    required this.item,
    required this.subTextColor,
    required this.theme,
    this.compact = false,
  });

  final CacheItem item;
  final Color subTextColor;
  final ThemeData theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sizeLabel = item.progressSizeLabel;
    final speedLabel =
        item.speed > 0 ? CacheSpeedFormatter.format(item.speed) : null;
    final detailParts = [
      if (sizeLabel.isNotEmpty) sizeLabel,
      if (speedLabel != null) speedLabel,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: item.fileSize > 0 ? item.progressPercent : null,
            minHeight: compact ? 4 : 5,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        if (detailParts.isNotEmpty) ...[
          SizedBox(height: compact ? 3 : 4),
          Text(
            detailParts.join(' · '),
            style: TextStyle(color: subTextColor, fontSize: compact ? 10 : 11),
          ),
        ],
      ],
    );
  }
}
