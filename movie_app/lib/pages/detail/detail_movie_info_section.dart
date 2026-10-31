import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../utils/web_http_stub.dart'
    if (dart.library.html) '../../utils/web_http.dart' as web_http;

import 'package:movie_app/config/constants.dart';
import 'package:movie_app/config/routes.dart';
import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/torrent_info.dart';

import 'detail_episode_grid.dart';
import 'detail_magnet_info_panel.dart';
import 'detail_magnet_results_panel.dart';
import 'detail_source_switch_pane.dart';
import 'detail_ui_tokens.dart';

/// 详情页下方（Android / iOS 单列）：标题、可收起简介、选集/线路 Tab、推荐/磁力 Tab。
class DetailMovieInfoSection extends StatefulWidget {
  const DetailMovieInfoSection({
    super.key,
    required this.movie,
    required this.selectedRouteIndex,
    required this.playingRouteIndex,
    required this.playingEpisodeIndex,
    required this.onEpisodeSelected,
    required this.onRouteSelected,
    required this.magnetResults,
    required this.magnetLoading,
    required this.magnetMessage,
    required this.onMagnetRefreshStrict,
    required this.onMagnetRefreshLoose,
    this.onMagnetTabSelected,
    this.isMagnetDetail = false,
    this.torrent,
    this.isMagnetPlaying = false,
  });

  final Movie movie;
  final int selectedRouteIndex;
  final int playingRouteIndex;
  final int playingEpisodeIndex;
  final void Function(int routeIndex, int episodeIndex) onEpisodeSelected;
  final void Function(int routeIndex) onRouteSelected;
  final List<TorrentInfo> magnetResults;
  final bool magnetLoading;
  final String magnetMessage;
  final Future<void> Function() onMagnetRefreshStrict;
  final Future<void> Function() onMagnetRefreshLoose;
  final VoidCallback? onMagnetTabSelected;
  final bool isMagnetDetail;
  final TorrentInfo? torrent;
  final bool isMagnetPlaying;

  @override
  State<DetailMovieInfoSection> createState() => _DetailMovieInfoSectionState();
}

class _DetailMovieInfoSectionState extends State<DetailMovieInfoSection> {
  bool _introExpanded = false;
  int _upperTab = 0;
  int _lowerTab = 0;
  late int _viewRouteIndex;

  @override
  void initState() {
    super.initState();
    _viewRouteIndex = widget.selectedRouteIndex;
  }

  @override
  void didUpdateWidget(covariant DetailMovieInfoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playingRouteIndex != oldWidget.playingRouteIndex) {
      _viewRouteIndex = widget.playingRouteIndex;
    }
  }

  int _safeRouteIndex(int index) {
    final routes = widget.movie.playRoutes;
    if (routes.isEmpty) return 0;
    return index.clamp(0, routes.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = DetailPageColors.of(context);
    final movie = widget.movie;
    final safeViewRoute = _safeRouteIndex(_viewRouteIndex);
    final episodes = movie.playRoutes.isEmpty
        ? const <Episode>[]
        : movie.playRoutes[safeViewRoute].episodes;
    final overview = widget.isMagnetDetail
        ? detailMagnetOverviewText(movie.description)
        : movie.description.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTitleBlock(movie, colors),
          if (widget.isMagnetDetail) ...[
            const SizedBox(height: 12),
            DetailMagnetInfoPanel(
              movie: movie,
              torrent: widget.torrent,
              showPlayingBadge: widget.isMagnetPlaying,
            ),
          ],
          if (overview.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildIntroCollapsible(l10n, overview, colors),
          ],
          const SizedBox(height: 16),
          if (widget.isMagnetDetail &&
              movie.playRoutes.isNotEmpty &&
              movie.playRoutes.first.episodes.length > 1) ...[
            Text(
              l10n.detailDesktopEpisodes,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _buildEpisodesPane(
              l10n,
              movie,
              0,
              movie.playRoutes.first.episodes,
              colors,
            ),
            const SizedBox(height: 20),
          ] else if (!widget.isMagnetDetail) ...[
            // Tab 行：选集 / 换源。
            // 「播放线路」原本是第二个 Tab，但它只是个线路跳转列表，和标题区的
            // 「换路线」chip 功能重复且只有 1 条线路时毫无意义（用户实测「路线永远
            // 只有一个」）；换成「换源」才是真正缺的功能（跨站点换资源）。
            _DetailUnderlineTabs(
              labels: [
                l10n.detailDesktopEpisodes,
                l10n.detailSwitchSource,
              ],
              colors: colors,
              selectedIndex: _upperTab,
              onSelect: (i) => setState(() => _upperTab = i),
            ),
            const SizedBox(height: 12),
            if (_upperTab == 0)
              _buildEpisodesPane(l10n, movie, safeViewRoute, episodes, colors)
            else
              DetailSourceSwitchPane(movie: movie, dense: true),
            const SizedBox(height: 20),
          ],
          _DetailUnderlineTabs(
            labels: [
              l10n.detailDesktopTabRecommend,
              l10n.detailDesktopTabMagnet,
            ],
            colors: colors,
            selectedIndex: _lowerTab,
            onSelect: (i) {
              setState(() => _lowerTab = i);
              if (i == 1) {
                widget.onMagnetTabSelected?.call();
              }
            },
          ),
          const SizedBox(height: 12),
          if (_lowerTab == 0)
            _buildRelatedSection(l10n, movie, colors)
          else
            _buildMagnetSection(l10n, movie, colors),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTitleBlock(Movie movie, DetailPageColors colors) {
    final titleLines = widget.isMagnetDetail
        ? detailMagnetTitleLines(movie, widget.torrent)
        : (primary: movie.name, secondary: null as String?);
    final subtitle = titleLines.secondary?.trim().isNotEmpty == true
        ? titleLines.secondary!.trim()
        : (widget.isMagnetDetail ? '' : movie.alias.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                titleLines.primary,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.25,
                ),
              ),
            ),
            if (widget.isMagnetDetail && !widget.isMagnetPlaying) ...[
              const SizedBox(width: 8),
              const DetailMagnetPlayingBadge(compact: true),
            ],
          ],
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: colors.muted, fontSize: 14, height: 1.35),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (movie.rating > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  movie.rating.toStringAsFixed(1),
                  style: TextStyle(
                    color: colors.onAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (movie.year.trim().isNotEmpty)
              Text(
                movie.year,
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
            if (movie.genres.isNotEmpty)
              Text(
                movie.genres.join(' / '),
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
            // 「换路线」入口：放在标题区原「换源」位置；单线路时仍显示（提示仅 1 条线路）。
            if (!widget.isMagnetDetail && movie.playRoutes.isNotEmpty)
              _RouteSwitchChip(
                movie: movie,
                selectedRouteIndex: widget.playingRouteIndex,
                onTap: () => showDetailRouteSheet(
                  context,
                  movie,
                  widget.playingRouteIndex,
                  widget.onRouteSelected,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildIntroCollapsible(
    AppLocalizations l10n,
    String description,
    DetailPageColors colors,
  ) {
    return Semantics(
      button: true,
      label: _introExpanded
          ? l10n.designV3CollapseIntro
          : l10n.designV3ExpandIntro,
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: const Key('detail_intro_toggle'),
          onTap: () => setState(() => _introExpanded = !_introExpanded),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.detailIntro,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        maxLines: _introExpanded ? null : 1,
                        overflow: _introExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.muted,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _introExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: colors.accent,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodesPane(
    AppLocalizations l10n,
    Movie movie,
    int safeViewRoute,
    List<Episode> episodes,
    DetailPageColors colors,
  ) {
    if (movie.playRoutes.isEmpty) {
      return _emptyHint(l10n.detailDesktopNoEpisodes, colors);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (movie.playRoutes.length > 1) ...[
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: movie.playRoutes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final selected = i == safeViewRoute;
                final name = movie.playRoutes[i].name.isEmpty
                    ? '${l10n.detailPlayRoutes} ${i + 1}'
                    : movie.playRoutes[i].name;
                return ChoiceChip(
                  label: Text(name),
                  selected: selected,
                  onSelected: (_) => setState(() => _viewRouteIndex = i),
                  selectedColor: colors.accent,
                  labelStyle: TextStyle(
                    color: selected ? colors.onAccent : colors.muted,
                    fontSize: 12,
                  ),
                  backgroundColor: colors.chipBackground,
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (episodes.isEmpty)
          _emptyHint(l10n.detailDesktopNoEpisodes, colors)
        else
          DetailEpisodeGrid(
            episodes: episodes,
            playingIndex: widget.playingRouteIndex == safeViewRoute
                ? widget.playingEpisodeIndex
                : -1,
            l10n: l10n,
            colors: colors,
            onEpisodeTap: (ei) => widget.onEpisodeSelected(safeViewRoute, ei),
          ),
      ],
    );
  }

  Widget _buildMagnetSection(
    AppLocalizations l10n,
    Movie movie,
    DetailPageColors colors,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.detailMagnetSearchHint,
            style: TextStyle(
              color: colors.muted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          DetailMagnetResultsPanel(
            movie: movie,
            results: widget.magnetResults,
            isLoading: widget.magnetLoading,
            statusMessage: widget.magnetMessage,
            onRefreshStrict: widget.onMagnetRefreshStrict,
            onRefreshLoose: widget.onMagnetRefreshLoose,
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedSection(
    AppLocalizations l10n,
    Movie movie,
    DetailPageColors colors,
  ) {
    if (movie.relatedMovies.isEmpty) {
      return _emptyHint(l10n.detailRelatedHint, colors);
    }

    return SizedBox(
      height: 188,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: movie.relatedMovies.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final m = movie.relatedMovies[i];
          return _RelatedCard(
            movie: m,
            colors: colors,
            onTap: () {
              if (movie.sourceId == AppConstants.magnetDetailSourceId) {
                AppRoutes.toSearch(context, query: m.name);
                return;
              }
              AppRoutes.toDetail(
                context,
                id: m.id,
                sourceId: m.sourceId,
                movie: m,
              );
            },
          );
        },
      ),
    );
  }

  Widget _emptyHint(String text, DetailPageColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        text,
        style: TextStyle(color: colors.faint, fontSize: 13),
      ),
    );
  }
}

/// 详情页「换路线」入口（chip）：放在标题区原「换源」位置。
///
/// 单线路影片也照常显示（提示仅 1 条线路），点开弹出线路选择；
/// 多线路时直接切换 [onRouteSelected]。与播放器顶栏的「线路」图标同源。
class _RouteSwitchChip extends StatelessWidget {
  const _RouteSwitchChip({
    required this.movie,
    required this.selectedRouteIndex,
    required this.onTap,
  });

  final Movie movie;
  final int selectedRouteIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = DetailPageColors.of(context);
    final safeIndex = movie.playRoutes.isEmpty
        ? 0
        : selectedRouteIndex.clamp(0, movie.playRoutes.length - 1);
    final route = movie.playRoutes[safeIndex];
    final name = route.name.isEmpty ? '线路 ${safeIndex + 1}' : route.name;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: colors.accent.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.high_quality_rounded, size: 13, color: colors.accent),
            const SizedBox(width: 4),
            Text(
              name,
              style: TextStyle(
                color: colors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 详情页「换路线」底部弹窗：列出全部播放线路，单线路时提示仅 1 条。
///
/// 🔴 **尺寸**（用户实测「播放路线的弹窗也太小了」）：原来用的是默认
/// `showModalBottomSheet`，在内容少时只占屏幕底部一条窄带，选中线路几乎
/// 点不中。现在改为正规底部弹窗：透明背景 + 自绘圆角卡片 + 拖拽条 +
/// 标题/副标题 + 线路项（名称 + 集数 + 选中打勾），并给一个最小高度，
/// 内容多时可滚动。
void showDetailRouteSheet(
  BuildContext context,
  Movie movie,
  int selectedRouteIndex,
  ValueChanged<int> onRouteSelected,
) {
  final l10n = AppLocalizations.of(context)!;
  final colors = DetailPageColors.of(context);
  final theme = Theme.of(context);
  final muted = theme.hintColor;
  final routeCount = movie.playRoutes.length;
  final safeIndex = routeCount == 0
      ? 0
      : selectedRouteIndex.clamp(0, routeCount - 1);

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            // 至少占屏高 42%：内容少时不再缩成一条窄带。
            minHeight: MediaQuery.of(context).size.height * 0.42,
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.detailPlayRoutes,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      l10n.detailRouteSheetCount(routeCount),
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  routeCount <= 1
                      ? l10n.detailRouteSheetOnlyOne
                      : l10n.detailRouteSheetHint,
                  style: TextStyle(color: muted, fontSize: 12, height: 1.35),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: routeCount <= 1
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                        child: Text(
                          l10n.detailRouteSheetOnlyOneHint,
                          style: TextStyle(
                            color: muted,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: routeCount,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final route = movie.playRoutes[i];
                          final name =
                              route.name.isEmpty ? '线路 ${i + 1}' : route.name;
                          final selected = i == safeIndex;
                          final episodes = route.episodes.length;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 4,
                            ),
                            leading: Icon(
                              selected
                                  ? Icons.play_circle_fill_rounded
                                  : Icons.play_circle_outline_rounded,
                              color: selected ? colors.accent : muted,
                              size: 24,
                            ),
                            title: Text(
                              name,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 15,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                            subtitle: episodes > 0
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      l10n.detailSwitchSourceEpisodes(
                                        episodes,
                                      ),
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  )
                                : null,
                            trailing: selected
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: colors.accent,
                                    size: 22,
                                  )
                                : null,
                            onTap: () {
                              onRouteSelected(i);
                              Navigator.of(sheetContext).pop();
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _DetailUnderlineTabs extends StatelessWidget {
  const _DetailUnderlineTabs({
    required this.labels,
    required this.colors,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> labels;
  final DetailPageColors colors;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ...List.generate(labels.length, (i) {
          final selected = i == selectedIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onSelect(i),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected ? colors.onSurface : colors.muted,
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: selected ? colors.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _RelatedCard extends StatelessWidget {
  const _RelatedCard({
    required this.movie,
    required this.colors,
    required this.onTap,
  });

  final Movie movie;
  final DetailPageColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: movie.cover.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: web_http.webProxiedImageUrl(movie.cover),
                          fit: BoxFit.cover,
                          width: 108,
                          errorWidget: (_, __, ___) =>
                              _coverPlaceholder(colors),
                        )
                      : _coverPlaceholder(colors),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                movie.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              if (movie.rating > 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFB800),
                      size: 14,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      movie.rating.toStringAsFixed(1),
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverPlaceholder(DetailPageColors colors) {
    return Container(
      width: 108,
      color: colors.card,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          color: colors.faint,
          size: 36,
        ),
      ),
    );
  }
}
