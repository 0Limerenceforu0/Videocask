import 'package:flutter/material.dart';

import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/torrent_info.dart';

import 'detail_magnet_results_panel.dart';
import 'detail_ui_tokens.dart';

/// 宽屏（Windows）左栏：标题、元信息、简介。
class DetailDesktopLeftSection extends StatelessWidget {
  const DetailDesktopLeftSection({super.key, required this.movie});

  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            movie.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
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
                    color: kDetailAccentColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${movie.rating}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              Text(
                movie.year,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Text(
                movie.genres.join(' / '),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.detailIntro,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            movie.description,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.5,
            ),
          ),
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
    final routes = widget.movie.playRoutes;
    final safeRouteIndex = routes.isEmpty
        ? 0
        : widget.selectedRouteIndex.clamp(0, routes.length - 1);
    final episodes =
        routes.isEmpty ? const <Episode>[] : routes[safeRouteIndex].episodes;

    return Material(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _episodeOrRouteTabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: kDetailAccentColor,
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
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    indicatorColor: kDetailAccentColor,
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
    if (episodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            l10n.detailDesktopNoEpisodes,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white38,
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color:
                playing ? Colors.blue.withValues(alpha: 0.35) : Colors.white10,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => onEpisodeSelected(safeRouteIndex, ei),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  ep.name.isNotEmpty
                      ? ep.name
                      : '${l10n.detailDesktopEpisodes} ${ei + 1}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: playing ? FontWeight.w600 : FontWeight.normal,
                  ),
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
    if (routes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            l10n.detailMagnetSearchHint,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
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
                ? kDetailAccentColor.withValues(alpha: 0.35)
                : Colors.white10,
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
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: selected ? Colors.white : Colors.white54,
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
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          l10n.detailMagnetSearch,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.detailMagnetSearchHint,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
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
    final list = movie.relatedMovies;
    if (list.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.detailRelatedHint,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Colors.white12),
      itemBuilder: (context, i) {
        final m = list[i];
        return ListTile(
          dense: true,
          title: Text(
            m.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: m.year.isNotEmpty
              ? Text(
                  m.year,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                )
              : null,
          onTap: () => onOpenRelated(m),
        );
      },
    );
  }
}
