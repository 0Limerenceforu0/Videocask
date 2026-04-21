import 'package:flutter/material.dart';

import 'package:movie_app/config/routes.dart';
import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/torrent_info.dart';

import 'detail_magnet_results_panel.dart';
import 'detail_ui_tokens.dart';

/// 详情页下方：标题、简介、线路、磁力与相关推荐模块。
class DetailMovieInfoSection extends StatelessWidget {
  const DetailMovieInfoSection({
    super.key,
    required this.movie,
    required this.onPlayRoute,
    required this.magnetResults,
    required this.magnetLoading,
    required this.magnetMessage,
    required this.onMagnetRefreshStrict,
    required this.onMagnetRefreshLoose,
  });

  final Movie movie;
  final void Function(int routeIndex) onPlayRoute;
  final List<TorrentInfo> magnetResults;
  final bool magnetLoading;
  final String magnetMessage;
  final Future<void> Function() onMagnetRefreshStrict;
  final Future<void> Function() onMagnetRefreshLoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              Text(
                movie.year,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              Text(
                movie.genres.join(' / '),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
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
            overflow: TextOverflow.visible,
            softWrap: true,
          ),
          const SizedBox(height: 20),
          Text(
            l10n.detailPlayRoutes,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          if (movie.playRoutes.isNotEmpty)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: movie.playRoutes.asMap().entries.map((entry) {
                final index = entry.key;
                final route = entry.value;
                return GestureDetector(
                  onTap: () => onPlayRoute(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          route.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.chevron_right,
                          color: Colors.white54,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 20),
          Text(
            l10n.detailMagnetSearch,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.detailMagnetSearchHint,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                DetailMagnetResultsPanel(
                  movie: movie,
                  results: magnetResults,
                  isLoading: magnetLoading,
                  statusMessage: magnetMessage,
                  onRefreshStrict: onMagnetRefreshStrict,
                  onRefreshLoose: onMagnetRefreshLoose,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.detailRelated,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          if (movie.relatedMovies.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.detailRelatedHint,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: movie.relatedMovies.map((m) {
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    m.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: m.year.isNotEmpty
                      ? Text(
                          m.year,
                          style: const TextStyle(color: Colors.white54),
                        )
                      : null,
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white38,
                  ),
                  onTap: () => AppRoutes.toDetail(
                    context,
                    id: m.id,
                    sourceId: m.sourceId,
                    movie: m,
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
