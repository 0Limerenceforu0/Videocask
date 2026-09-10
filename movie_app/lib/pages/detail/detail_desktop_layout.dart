import 'package:flutter/material.dart';

import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/torrent_info.dart';

import 'package:movie_app/utils/episode_display_label.dart';

import 'detail_magnet_info_panel.dart';
import 'detail_magnet_results_panel.dart';
import 'detail_ui_tokens.dart';

/// 宽屏（Windows）左栏：标题、元信息、简介。
class DetailDesktopLeftSection extends StatelessWidget {
  const DetailDesktopLeftSection({
    super.key,
    required this.movie,
    this.isMagnetDetail = false,
    this.torrent,
    this.isMagnetPlaying = false,
  });

  final Movie movie;
  final bool isMagnetDetail;
  final TorrentInfo? torrent;
  final bool isMagnetPlaying;

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
          TabBar(
            controller: _episodeOrRouteTabController,
            labelColor: colors.onSurface,
            unselectedLabelColor: colors.muted,
            indicatorColor: colors.accent,
            tabs: [
              Tab(text: l10n.detailDesktopEpisodes),
              Tab(text: l10n.detailPlayRoutes),
            ],
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
                _DesktopRoutesPane(
                  l10n: l10n,
                  routes: routes,
                  safeRouteIndex: safeRouteIndex,
                  onRouteSelected: widget.onRouteSelected,
                ),
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

class _DesktopRoutesPane extends StatelessWidget {
  const _DesktopRoutesPane({
    required this.l10n,
    required this.routes,
    required this.safeRouteIndex,
    required this.onRouteSelected,
  });

  final AppLocalizations l10n;
  final List<PlayRoute> routes;
  final int safeRouteIndex;
  final ValueChanged<int> onRouteSelected;

  @override
  Widget build(BuildContext context) {
    final colors = DetailPageColors.of(context);
    if (routes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            l10n.detailMagnetSearchHint,
            style: TextStyle(color: colors.muted, fontSize: 13),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: routes.length,
      itemBuilder: (context, i) {
        final selected = i == safeRouteIndex;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: selected
                ? colors.accent.withValues(alpha: 0.35)
                : colors.surfaceTint,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => onRouteSelected(i),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        routes[i].name,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: selected ? colors.onSurface : colors.muted,
                      size: 20,
                    ),
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
