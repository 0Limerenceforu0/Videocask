import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/movie.dart';
import '../../utils/episode_display_label.dart';
import '../../widgets/episode_selection_row.dart';
import 'detail_ui_tokens.dart';

/// 详情选集网格：小列表一次展示；大列表分页，避免海量分集卡死 UI。
class DetailEpisodeGrid extends StatefulWidget {
  const DetailEpisodeGrid({
    super.key,
    required this.episodes,
    required this.playingIndex,
    required this.l10n,
    required this.colors,
    required this.onEpisodeTap,
    this.maxHeight = 480,
    this.largeListThreshold = 30,
    this.rowsPerPage = 4,
  });

  final List<Episode> episodes;
  final int playingIndex;
  final AppLocalizations l10n;
  final DetailPageColors colors;
  final ValueChanged<int> onEpisodeTap;
  final double maxHeight;
  final int largeListThreshold;
  final int rowsPerPage;

  @override
  State<DetailEpisodeGrid> createState() => _DetailEpisodeGridState();
}

class _DetailEpisodeGridState extends State<DetailEpisodeGrid> {
  late int _pageIndex;
  bool _pageSyncedFromPlaying = false;

  bool get _usePagination => widget.episodes.length > widget.largeListThreshold;

  bool get _useListLayout =>
      EpisodeDisplayLabel.episodesPreferListLayout(widget.episodes);

  static const _listRowsPerPage = 8;
  static const _listRowSpacing = 6.0;

  int _crossCountForWidth(double width) => width >= 520 ? 5 : 4;

  int _itemsPerPage(double width) {
    if (_useListLayout) return _listRowsPerPage;
    return _crossCountForWidth(width) * widget.rowsPerPage;
  }

  int _pageCount(double width) {
    final perPage = _itemsPerPage(width);
    return (widget.episodes.length + perPage - 1) ~/ perPage;
  }

  int _pageForEpisode(int episodeIndex, double width) {
    if (episodeIndex < 0) return _pageIndex;
    final perPage = _itemsPerPage(width);
    return episodeIndex ~/ perPage;
  }

  @override
  void initState() {
    super.initState();
    _pageIndex = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pageSyncedFromPlaying && _usePagination && widget.playingIndex >= 0) {
      final width = MediaQuery.sizeOf(context).width;
      _pageIndex = _pageForEpisode(widget.playingIndex, width);
      _pageSyncedFromPlaying = true;
    }
  }

  @override
  void didUpdateWidget(covariant DetailEpisodeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playingIndex >= 0 &&
        widget.playingIndex != oldWidget.playingIndex) {
      final width = MediaQuery.sizeOf(context).width;
      _pageIndex = _pageForEpisode(widget.playingIndex, width);
    }
  }

  void _goToPage(int page, double width) {
    final maxPage = _pageCount(width) - 1;
    setState(() => _pageIndex = page.clamp(0, maxPage));
  }

  Future<void> _showJumpDialog(double width) async {
    final controller = TextEditingController();
    final maxEpisode = widget.episodes.length;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(widget.l10n.detailEpisodeGridJumpTitle),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.l10n.detailEpisodeGridJumpHint(maxEpisode),
            ),
            onSubmitted: (value) {
              final n = int.tryParse(value.trim());
              if (n != null && n >= 1 && n <= maxEpisode) {
                Navigator.pop(ctx, n - 1);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(widget.l10n.detailClose),
            ),
            TextButton(
              onPressed: () {
                final n = int.tryParse(controller.text.trim());
                if (n == null || n < 1 || n > maxEpisode) {
                  return;
                }
                Navigator.pop(ctx, n - 1);
              },
              child: Text(widget.l10n.detailEpisodeGridJumpConfirm),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (!mounted || result == null) return;
    _goToPage(_pageForEpisode(result, width), width);
  }

  static double _gridHeightForRows({
    required int rowCount,
    required double cellHeight,
    required double spacing,
  }) {
    if (rowCount <= 0) return 0;
    return rowCount * cellHeight + (rowCount - 1) * spacing + 1;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.episodes.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return _buildGrid(context, width);
      },
    );
  }

  Widget _buildGrid(BuildContext context, double width) {
    if (_useListLayout) {
      return _buildList(context, width);
    }

    final crossCount = _crossCountForWidth(width);
    // 标题可换两行：调高 cell（aspectRatio 减小），避免长集数名被裁断。
    const spacing = 8.0;
    const aspectRatio = 1.25;
    final cellWidth =
        (width - spacing * (crossCount - 1)).clamp(48.0, width) / crossCount;
    final cellHeight = cellWidth / aspectRatio;

    final perPage = _itemsPerPage(width);
    final pageCount = _pageCount(width);
    _pageIndex = _pageIndex.clamp(0, pageCount - 1);

    final List<Episode> visibleEpisodes;
    final int startIndex;
    if (_usePagination) {
      startIndex = _pageIndex * perPage;
      final end = (startIndex + perPage).clamp(0, widget.episodes.length);
      visibleEpisodes = widget.episodes.sublist(startIndex, end);
    } else {
      startIndex = 0;
      visibleEpisodes = widget.episodes;
    }

    final rowCount = (visibleEpisodes.length + crossCount - 1) ~/ crossCount;
    final paginatedRows = _usePagination ? widget.rowsPerPage : rowCount;
    final gridHeight = _gridHeightForRows(
      rowCount: paginatedRows,
      cellHeight: cellHeight,
      spacing: spacing,
    ).clamp(96.0, widget.maxHeight);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 分页条放顶部：分页很多时（>3 页）保证在屏幕中可见，避免被底部 FAB / 浏览器栏遮挡。
        if (_usePagination) ...[
          _buildPaginationBar(width, pageCount),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: gridHeight,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossCount,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: aspectRatio,
            ),
            itemCount: visibleEpisodes.length,
            itemBuilder: (context, localIndex) {
              final ei = startIndex + localIndex;
              final ep = visibleEpisodes[localIndex];
              final selected = ei == widget.playingIndex;
              final display = EpisodeDisplayLabel.forEpisode(
                name: ep.name,
                index: ei,
              );
              final textColor =
                  selected ? widget.colors.onAccent : widget.colors.muted;
              // 集数多时允许 2 行避免标题被裁；行数根据总数动态决定。
              final titleMaxLines = widget.episodes.length > 24 ? 2 : 1;
              final double titleFontSize = display.secondary != null
                  ? 13
                  : (titleMaxLines == 2 ? 12 : 13);
              return Semantics(
                button: true,
                label: display.full,
                child: Tooltip(
                  message: display.full,
                  child: Material(
                    color: selected
                        ? widget.colors.accent.withValues(alpha: 0.28)
                        : widget.colors.card,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: () => widget.onEpisodeTap(ei),
                      borderRadius: BorderRadius.circular(8),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 3,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  display.primary,
                                  maxLines: titleMaxLines,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: titleFontSize,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                  ),
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
                                    color: textColor.withValues(alpha: 0.75),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildList(BuildContext context, double width) {
    final perPage = _itemsPerPage(width);
    final pageCount = _pageCount(width);
    _pageIndex = _pageIndex.clamp(0, pageCount - 1);

    final List<Episode> visibleEpisodes;
    final int startIndex;
    if (_usePagination) {
      startIndex = _pageIndex * perPage;
      final end = (startIndex + perPage).clamp(0, widget.episodes.length);
      visibleEpisodes = widget.episodes.sublist(startIndex, end);
    } else {
      startIndex = 0;
      visibleEpisodes = widget.episodes;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 分页条放顶部：分页很多时（>3 页）保证在屏幕中可见，避免被底部 FAB / 浏览器栏遮挡。
        if (_usePagination) ...[
          _buildPaginationBar(width, pageCount),
          const SizedBox(height: 8),
        ],
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: visibleEpisodes.length,
          separatorBuilder: (_, __) => const SizedBox(height: _listRowSpacing),
          itemBuilder: (context, localIndex) {
            final ei = startIndex + localIndex;
            final ep = visibleEpisodes[localIndex];
            final selected = ei == widget.playingIndex;
            final display = EpisodeDisplayLabel.forEpisode(
              name: ep.name,
              index: ei,
            );
            final textColor =
                selected ? widget.colors.onAccent : widget.colors.onSurface;
            final subTextColor = selected
                ? widget.colors.onAccent.withValues(alpha: 0.75)
                : widget.colors.muted;
            return EpisodeSelectionRow(
              display: display,
              selected: selected,
              showFullSubtitle: true,
              onTap: () => widget.onEpisodeTap(ei),
              backgroundColor: widget.colors.card,
              selectedBackgroundColor:
                  widget.colors.accent.withValues(alpha: 0.28),
              textColor: textColor,
              subTextColor: subTextColor,
              trailing: selected
                  ? Icon(
                      Icons.play_arrow_rounded,
                      color: widget.colors.onAccent,
                      size: 22,
                    )
                  : null,
            );
          },
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildPaginationBar(double width, int pageCount) {
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.l10n.detailEpisodeGridCount(widget.episodes.length),
            style: TextStyle(color: widget.colors.muted, fontSize: 12),
          ),
        ),
        Semantics(
          button: true,
          label: widget.l10n.detailEpisodeGridJumpToEpisode,
          child: IconButton(
            tooltip: widget.l10n.detailEpisodeGridJumpToEpisode,
            icon: Icon(Icons.search, size: 20, color: widget.colors.muted),
            visualDensity: VisualDensity.compact,
            onPressed: () => _showJumpDialog(width),
          ),
        ),
        Semantics(
          button: true,
          label: widget.l10n.detailEpisodeGridPrevPage,
          child: IconButton(
            tooltip: widget.l10n.detailEpisodeGridPrevPage,
            icon: Icon(
              Icons.chevron_left,
              color: _pageIndex > 0
                  ? widget.colors.muted
                  : widget.colors.muted.withValues(alpha: 0.35),
            ),
            visualDensity: VisualDensity.compact,
            onPressed:
                _pageIndex > 0 ? () => _goToPage(_pageIndex - 1, width) : null,
          ),
        ),
        Text(
          widget.l10n.detailEpisodeGridPageInfo(_pageIndex + 1, pageCount),
          style: TextStyle(
            color: widget.colors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        Semantics(
          button: true,
          label: widget.l10n.detailEpisodeGridNextPage,
          child: IconButton(
            tooltip: widget.l10n.detailEpisodeGridNextPage,
            icon: Icon(
              Icons.chevron_right,
              color: _pageIndex < pageCount - 1
                  ? widget.colors.muted
                  : widget.colors.muted.withValues(alpha: 0.35),
            ),
            visualDensity: VisualDensity.compact,
            onPressed: _pageIndex < pageCount - 1
                ? () => _goToPage(_pageIndex + 1, width)
                : null,
          ),
        ),
      ],
    );
  }
}
