import 'package:flutter/material.dart';

import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/torrent_info.dart';

import 'package:movie_app/utils/episode_display_label.dart';

import 'detail_magnet_info_panel.dart';
import 'detail_magnet_results_panel.dart';
import 'detail_movie_info_section.dart';
import 'detail_source_switch_pane.dart';
import 'detail_ui_tokens.dart';

/// 宽屏左栏「换路线」入口 chip（放在标题区原「换源」位置）。
///
/// 单线路影片也照常显示（提示仅 1 条线路），点开弹出线路选择；
/// 与窄屏详情区、`showDetailRouteSheet` 同源。
class _DesktopRouteChip extends StatelessWidget {
  const _DesktopRouteChip({
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

/// 宽屏（Windows）左栏：标题、元信息、简介。
class DetailDesktopLeftSection extends StatelessWidget {
  const DetailDesktopLeftSection({
    super.key,
    required this.movie,
    this.isMagnetDetail = false,
    this.torrent,
    this.isMagnetPlaying = false,
    required this.onRouteSelected,
    required this.currentRouteIndex,
  });

  final Movie movie;
  final bool isMagnetDetail;
  final TorrentInfo? torrent;
  final bool isMagnetPlaying;
  final ValueChanged<int> onRouteSelected;
  final int currentRouteIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = DetailPageColors.of(context);
    final overview = isMagnetDetail
        ? detailMagnetOverviewText(movie.description)
        : movie.description.trim();
    final titleLines = isMagnetDetail
        ? detailMagnetTitleLines(movie, torrent)
        : (primary: movie.name, secondary: null as String?);
    final subtitle = titleLines.secondary?.trim().isNotEmpty == true
        ? titleLines.secondary!.trim()
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
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
                  ),
                ),
              ),
              if (isMagnetDetail && !isMagnetPlaying) ...[
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
            runSpacing: 8,
            children: [
              if (movie.rating > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${movie.rating}',
                    style: TextStyle(color: colors.onAccent, fontSize: 12),
                  ),
                ),
              if (movie.year.trim().isNotEmpty)
                Text(
                  movie.year,
                  style: TextStyle(color: colors.muted, fontSize: 14),
                ),
              if (movie.genres.isNotEmpty)
                Text(
                  movie.genres.join(' / '),
                  style: TextStyle(color: colors.muted, fontSize: 14),
                ),
              // 「换路线」入口：放在标题区原「换源」位置；单线路时仍显示（提示仅 1 条线路）。
              if (!isMagnetDetail && movie.playRoutes.isNotEmpty)
                _DesktopRouteChip(
                  movie: movie,
                  selectedRouteIndex: currentRouteIndex,
                  onTap: () => showDetailRouteSheet(
                    context,
                    movie,
                    currentRouteIndex,
                    onRouteSelected,
                  ),
                ),
            ],
          ),
          if (isMagnetDetail) ...[
            const SizedBox(height: 12),
            DetailMagnetInfoPanel(
              movie: movie,
              torrent: torrent,
              showPlayingBadge: isMagnetPlaying,
            ),
          ],
          if (overview.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.detailIntro,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    overview,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 宽屏右栏：**顶部**「选集 / 播放线路」Tab，其下为「磁力 / 推荐」Tab。
class DetailDesktopRightSidebar extends StatefulWidget {
  const DetailDesktopRightSidebar({
    super.key,
    required this.movie,
    required this.isMagnetDetail,
    required this.scrollController,
    required this.selectedRouteIndex,
    required this.onRouteSelected,
    required this.onEpisodeSelected,
    required this.playingRouteIndex,
    required this.playingEpisodeIndex,
    required this.onOpenRelated,
    required this.magnetResults,
    required this.magnetLoading,
    required this.magnetMessage,
    required this.onMagnetRefreshStrict,
    required this.onMagnetRefreshLoose,
  });

  final Movie movie;
  final bool isMagnetDetail;
  final ScrollController scrollController;
  final int selectedRouteIndex;
  final ValueChanged<int> onRouteSelected;
  final void Function(int routeIndex, int episodeIndex) onEpisodeSelected;
  final int playingRouteIndex;
  final int playingEpisodeIndex;
  final void Function(Movie related) onOpenRelated;
  final List<TorrentInfo> magnetResults;
  final bool magnetLoading;
  final String magnetMessage;
  final Future<void> Function() onMagnetRefreshStrict;
  final Future<void> Function() onMagnetRefreshLoose;

  @override
  State<DetailDesktopRightSidebar> createState() =>
      _DetailDesktopRightSidebarState();
}

class _DetailDesktopRightSidebarState extends State<DetailDesktopRightSidebar>
    with SingleTickerProviderStateMixin {
  late TabController _episodeOrRouteTabController;

  @override
  void initState() {
    super.initState();
    _episodeOrRouteTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _episodeOrRouteTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = DetailPageColors.of(context);
    final routes = widget.movie.playRoutes;
    final safeRouteIndex = routes.isEmpty
        ? 0
        : widget.selectedRouteIndex.clamp(0, routes.length - 1);
    final episodes =
        routes.isEmpty ? const <Episode>[] : routes[safeRouteIndex].episodes;

    return Material(
      color: colors.scaffold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TabBar(
              controller: _episodeOrRouteTabController,
              labelColor: colors.onSurface,
              unselectedLabelColor: colors.muted,
              indicatorColor: colors.accent,
              tabs: [
                Tab(text: l10n.detailDesktopEpisodes),
                // 「播放线路」Tab 换成「换源」：线路选择已由标题区的「换路线」
                // chip 承担（点开是底部弹窗），Tab 位置给真正缺的功能。
                Tab(text: l10n.detailSwitchSource),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: TabBarView(
              controller: _episodeOrRouteTabController,
              children: [
                _DesktopEpisodesPane(
                  l10n: l10n,
                  episodes: episodes,
                  scrollController: widget.scrollController,
                  safeRouteIndex: safeRouteIndex,
                  playingRouteIndex: widget.playingRouteIndex,
                  playingEpisodeIndex: widget.playingEpisodeIndex,
                  onEpisodeSelected: widget.onEpisodeSelected,
                ),
                DetailSourceSwitchPane(movie: widget.movie),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: DefaultTabController(
              length: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TabBar(
                    labelColor: colors.onSurface,
                    unselectedLabelColor: colors.muted,
                    indicatorColor: colors.accent,
                    tabs: [
                      Tab(text: l10n.detailDesktopTabMagnet),
                      Tab(text: l10n.detailDesktopTabRecommend),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _MagnetTabBody(
                          l10n: l10n,
                          movie: widget.movie,
                          magnetResults: widget.magnetResults,
                          magnetLoading: widget.magnetLoading,
                          magnetMessage: widget.magnetMessage,
                          onMagnetRefreshStrict: widget.onMagnetRefreshStrict,
                          onMagnetRefreshLoose: widget.onMagnetRefreshLoose,
                        ),
                        _RelatedTabBody(
                          movie: widget.movie,
                          onOpenRelated: widget.onOpenRelated,
                          l10n: l10n,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopEpisodesPane extends StatelessWidget {
  const _DesktopEpisodesPane({
    required this.l10n,
    required this.episodes,
    required this.scrollController,
    required this.safeRouteIndex,
    required this.playingRouteIndex,
    required this.playingEpisodeIndex,
    required this.onEpisodeSelected,
  });

  final AppLocalizations l10n;
  final List<Episode> episodes;
  final ScrollController scrollController;
  final int safeRouteIndex;
  final int playingRouteIndex;
  final int playingEpisodeIndex;
  final void Function(int routeIndex, int episodeIndex) onEpisodeSelected;

  @override
  Widget build(BuildContext context) {
    final colors = DetailPageColors.of(context);
    if (episodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            l10n.detailDesktopNoEpisodes,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.faint,
              fontSize: 13,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: episodes.length,
      itemBuilder: (context, ei) {
        final ep = episodes[ei];
        final playing =
            playingRouteIndex == safeRouteIndex && playingEpisodeIndex == ei;
        final display = EpisodeDisplayLabel.forEpisode(
          name: ep.name,
          index: ei,
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: playing
                ? colors.accent.withValues(alpha: 0.35)
                : colors.surfaceTint,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => onEpisodeSelected(safeRouteIndex, ei),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      display.primary,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 14,
                        fontWeight: playing ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (display.full != display.primary) ...[
                      const SizedBox(height: 4),
                      Text(
                        display.full,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}


class _MagnetTabBody extends StatelessWidget {
  const _MagnetTabBody({
    required this.l10n,
    required this.movie,
    required this.magnetResults,
    required this.magnetLoading,
    required this.magnetMessage,
    required this.onMagnetRefreshStrict,
    required this.onMagnetRefreshLoose,
  });

  final AppLocalizations l10n;
  final Movie movie;
  final List<TorrentInfo> magnetResults;
  final bool magnetLoading;
  final String magnetMessage;
  final Future<void> Function() onMagnetRefreshStrict;
  final Future<void> Function() onMagnetRefreshLoose;

  @override
  Widget build(BuildContext context) {
    final colors = DetailPageColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          l10n.detailMagnetSearch,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surfaceTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.detailMagnetSearchHint,
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              DetailMagnetResultsPanel(
                movie: movie,
                results: magnetResults,
                isLoading: magnetLoading,
                statusMessage: magnetMessage,
                onRefreshStrict: onMagnetRefreshStrict,
                onRefreshLoose: onMagnetRefreshLoose,
                dense: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RelatedTabBody extends StatelessWidget {
  const _RelatedTabBody({
    required this.movie,
    required this.onOpenRelated,
    required this.l10n,
  });

  final Movie movie;
  final void Function(Movie related) onOpenRelated;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = DetailPageColors.of(context);
    final list = movie.relatedMovies;
    if (list.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.detailRelatedHint,
            style: TextStyle(color: colors.muted, fontSize: 14),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: colors.divider),
      itemBuilder: (context, i) {
        final m = list[i];
        return ListTile(
          dense: true,
          title: Text(
            m.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.onSurface, fontSize: 14),
          ),
          subtitle: m.year.isNotEmpty
              ? Text(
                  m.year,
                  style: TextStyle(color: colors.muted, fontSize: 12),
                )
              : null,
          onTap: () => onOpenRelated(m),
        );
      },
    );
  }
}
