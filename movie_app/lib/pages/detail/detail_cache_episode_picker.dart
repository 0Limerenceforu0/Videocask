import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/cache_episode_status.dart';
import '../../models/movie.dart';
import '../../providers/cache_provider.dart';
import 'episode_download_coordinator.dart';
import '../../utils/episode_display_label.dart';
import '../../widgets/episode_selection_row.dart';

/// 缓存面板内多选集数（长标题自动一行一集）。
class DetailCacheEpisodePicker extends StatefulWidget {
  const DetailCacheEpisodePicker({
    super.key,
    required this.episodes,
    required this.movieId,
    required this.sourceId,
    required this.playingEpisodeIndex,
    required this.selectedIndices,
    required this.onSelectionChanged,
  });

  final List<Episode> episodes;
  final String movieId;
  final String sourceId;
  final int playingEpisodeIndex;
  final Set<int> selectedIndices;
  final ValueChanged<Set<int>> onSelectionChanged;

  @override
  State<DetailCacheEpisodePicker> createState() =>
      _DetailCacheEpisodePickerState();
}

class _DetailCacheEpisodePickerState extends State<DetailCacheEpisodePicker> {
  static const _crossCount = 4;
  static const _spacing = 6.0;
  static const _aspectRatio = 1.45;
  static const _listHeight = 240.0;
  static const _listRowSpacing = 6.0;

  bool get _useListLayout =>
      EpisodeDisplayLabel.episodesPreferListLayout(widget.episodes);

  void _toggle(int index, CacheEpisodeStatus status) {
    if (!EpisodeDownloadCoordinator.isEpisodeSelectableForBatch(
      episodeUrl: widget.episodes[index].url,
      cacheCompleted: status == CacheEpisodeStatus.completed,
    )) {
      return;
    }
    final next = Set<int>.from(widget.selectedIndices);
    if (next.contains(index)) {
      next.remove(index);
    } else {
      next.add(index);
    }
    widget.onSelectionChanged(next);
  }

  void _selectAllDownloadable(CacheProvider cache) {
    final next = <int>{};
    for (var i = 0; i < widget.episodes.length; i++) {
      final status = _statusFor(cache, i);
      if (!EpisodeDownloadCoordinator.isEpisodeSelectableForBatch(
        episodeUrl: widget.episodes[i].url,
        cacheCompleted: status == CacheEpisodeStatus.completed,
      )) {
        continue;
      }
      next.add(i);
    }
    widget.onSelectionChanged(next);
  }

  CacheEpisodeStatus _statusFor(CacheProvider cache, int index) {
    return cache.episodeCacheStatus(
      movieId: widget.movieId,
      episodeIndex: index,
      sourceId: widget.sourceId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Consumer<CacheProvider>(
      builder: (context, cache, _) {
        final selectedCount = widget.selectedIndices.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.detailCacheSelectEpisodes,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _selectAllDownloadable(cache),
                  child: Text(l10n.detailCacheSelectAll),
                ),
                TextButton(
                  onPressed: selectedCount == 0
                      ? null
                      : () => widget.onSelectionChanged({}),
                  child: Text(l10n.detailCacheClearSelection),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: _useListLayout ? _listHeight : 196,
              child: _useListLayout
                  ? _buildList(cache, cs)
                  : _buildGrid(cache, cs),
            ),
          ],
        );
      },
    );
  }

  Widget _buildList(CacheProvider cache, ColorScheme cs) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: widget.episodes.length,
      separatorBuilder: (_, __) => const SizedBox(height: _listRowSpacing),
      itemBuilder: (context, index) {
        final ep = widget.episodes[index];
        final status = _statusFor(cache, index);
        final selected = widget.selectedIndices.contains(index);
        final playing = index == widget.playingEpisodeIndex;
        final completed = status == CacheEpisodeStatus.completed;
        final display = EpisodeDisplayLabel.forEpisode(
          name: ep.name,
          index: index,
        );
        return EpisodeSelectionRow(
          display: display,
          selected: selected || playing,
          dense: true,
          showFullSubtitle: true,
          onTap: completed ? null : () => _toggle(index, status),
          backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          selectedBackgroundColor: selected
              ? cs.primary.withValues(alpha: 0.18)
              : cs.secondaryContainer.withValues(alpha: 0.35),
          textColor: cs.onSurface,
          subTextColor: cs.onSurface.withValues(alpha: 0.65),
          leading: completed
              ? Icon(Icons.download_done_rounded, size: 20, color: cs.primary)
              : Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  size: 20,
                  color: selected ? cs.primary : cs.outline,
                ),
          trailing: _StatusBadge(status: status),
        );
      },
    );
  }

  Widget _buildGrid(CacheProvider cache, ColorScheme cs) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _crossCount,
        mainAxisSpacing: _spacing,
        crossAxisSpacing: _spacing,
        childAspectRatio: _aspectRatio,
      ),
      itemCount: widget.episodes.length,
      itemBuilder: (context, index) {
        final ep = widget.episodes[index];
        final status = _statusFor(cache, index);
        final selected = widget.selectedIndices.contains(index);
        final playing = index == widget.playingEpisodeIndex;
        final display = EpisodeDisplayLabel.forEpisode(
          name: ep.name,
          index: index,
          secondaryMaxLength: 12,
        );
        return _EpisodeGridCell(
          display: display,
          status: status,
          selected: selected,
          playing: playing,
          onTap: () => _toggle(index, status),
        );
      },
    );
  }
}

class _EpisodeGridCell extends StatelessWidget {
  const _EpisodeGridCell({
    required this.display,
    required this.status,
    required this.selected,
    required this.playing,
    required this.onTap,
  });

  final EpisodeDisplayLabel display;
  final CacheEpisodeStatus status;
  final bool selected;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final completed = status == CacheEpisodeStatus.completed;

    Color bg;
    Color border;
    if (completed) {
      bg = cs.primaryContainer.withValues(alpha: 0.35);
      border = cs.primary.withValues(alpha: 0.45);
    } else if (selected) {
      bg = cs.primary.withValues(alpha: 0.18);
      border = cs.primary;
    } else if (playing) {
      bg = cs.secondaryContainer.withValues(alpha: 0.35);
      border = cs.secondary.withValues(alpha: 0.55);
    } else {
      bg = cs.surfaceContainerHighest.withValues(alpha: 0.45);
      border = theme.dividerColor.withValues(alpha: 0.35);
    }

    final textColor = completed
        ? cs.onPrimaryContainer.withValues(alpha: 0.85)
        : cs.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      label: display.full,
      child: Tooltip(
        message: _tooltip(l10n, display.full, status),
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: border, width: selected ? 1.5 : 1),
          ),
          child: InkWell(
            onTap: completed ? null : onTap,
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          display.primary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (display.secondary != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            display.secondary!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.72),
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (selected && !completed)
                  Positioned(
                    top: 2,
                    left: 2,
                    child: Icon(
                      Icons.check_circle,
                      size: 14,
                      color: cs.primary,
                    ),
                  ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: _StatusBadge(status: status),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _tooltip(
    AppLocalizations l10n,
    String full,
    CacheEpisodeStatus status,
  ) {
    final statusText = switch (status) {
      CacheEpisodeStatus.completed => l10n.detailCacheStatusCompleted,
      CacheEpisodeStatus.downloading => l10n.detailCacheStatusDownloading,
      CacheEpisodeStatus.waiting => l10n.detailCacheStatusWaiting,
      CacheEpisodeStatus.paused => l10n.detailCacheStatusPaused,
      CacheEpisodeStatus.none => '',
    };
    if (statusText.isEmpty) return full;
    return '$full · $statusText';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.status,
  });

  final CacheEpisodeStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == CacheEpisodeStatus.none) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    IconData icon;
    Color color;
    switch (status) {
      case CacheEpisodeStatus.completed:
        icon = Icons.download_done_rounded;
        color = const Color(0xFF43A047);
      case CacheEpisodeStatus.downloading:
        icon = Icons.downloading_rounded;
        color = cs.primary;
      case CacheEpisodeStatus.waiting:
        icon = Icons.hourglass_top_rounded;
        color = cs.tertiary;
      case CacheEpisodeStatus.paused:
        icon = Icons.pause_circle_outline_rounded;
        color = cs.error;
      case CacheEpisodeStatus.none:
        return const SizedBox.shrink();
    }

    return Icon(icon, size: 18, color: color);
  }
}
