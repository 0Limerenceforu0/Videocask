import 'package:flutter/material.dart';

import 'package:movie_app/config/routes.dart';
import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/torrent_info.dart';
import 'package:movie_app/utils/torrent_title_display.dart';

import 'detail_ui_tokens.dart';

String? _magnetHintFromMovie(Movie movie) {
  final name = movie.name.trim();
  if (name.isNotEmpty && RegExp(r'[\u4e00-\u9fff]').hasMatch(name)) {
    return name;
  }
  return null;
}

/// 详情页内嵌：磁力聚合结果列表（与搜索页相同 [TorrentSearchService] 逻辑，由上层传入 strict/loose 搜索结果）。
class DetailMagnetResultsPanel extends StatelessWidget {
  const DetailMagnetResultsPanel({
    super.key,
    required this.movie,
    required this.results,
    required this.isLoading,
    required this.statusMessage,
    required this.onRefreshStrict,
    required this.onRefreshLoose,
    this.dense = false,
  });

  final Movie movie;
  final List<TorrentInfo> results;
  final bool isLoading;

  /// 非空时表示提示或错误（加载中时由上层文案覆盖）
  final String statusMessage;
  final Future<void> Function() onRefreshStrict;
  final Future<void> Function() onRefreshLoose;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = DetailPageColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: isLoading ? null : () => onRefreshStrict(),
              icon: const Icon(Icons.manage_search, size: 18),
              label: Text(l10n.detailMagnetRefreshStrict),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.onSurface,
                side: BorderSide(color: colors.muted.withValues(alpha: 0.6)),
              ),
            ),
            OutlinedButton.icon(
              onPressed: isLoading ? null : () => onRefreshLoose(),
              icon: const Icon(Icons.zoom_out_map, size: 18),
              label: Text(l10n.detailMagnetRefreshLoose),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.onSurface,
                side: BorderSide(color: colors.muted.withValues(alpha: 0.6)),
              ),
            ),
            TextButton.icon(
              onPressed: isLoading
                  ? null
                  : () => AppRoutes.toSearch(context, query: movie.name),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l10n.detailMagnetOpenInSearch),
              style: TextButton.styleFrom(foregroundColor: colors.accent),
            ),
          ],
        ),
        if (isLoading) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.muted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.detailMagnetSearching,
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
        if (!isLoading && statusMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            statusMessage,
            style: TextStyle(color: colors.muted, fontSize: 13),
          ),
        ],
        if (!isLoading && results.isNotEmpty) ...[
          SizedBox(height: dense ? 8 : 14),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: results.length,
            separatorBuilder: (_, __) => SizedBox(height: dense ? 8 : 10),
            itemBuilder: (context, i) {
              return _MagnetResultTile(
                movie: movie,
                torrent: results[i],
                colors: colors,
                dense: dense,
              );
            },
          ),
        ],
      ],
    );
  }
}

class _MagnetResultTile extends StatelessWidget {
  const _MagnetResultTile({
    required this.movie,
    required this.torrent,
    required this.colors,
    required this.dense,
  });

  final Movie movie;
  final TorrentInfo torrent;
  final DetailPageColors colors;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lines = splitTorrentDisplayTitle(torrent.name);
    final showZhLabel = torrentTitlePrimaryIsMostlyLatin(torrent.name);

    return Material(
      color: colors.surfaceTint,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.fromLTRB(dense ? 10 : 12, dense ? 10 : 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showZhLabel && movie.name.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        movie.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.detailMagnetZhLabelHint,
                        style: TextStyle(
                          color: colors.faint,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              lines.primary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            if (lines.secondary != null && lines.secondary!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  lines.secondary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _meta(Icons.storage_outlined, torrent.sizeFormatted, colors),
                _meta(Icons.cloud_outlined, torrent.source, colors),
                _meta(
                  Icons.arrow_upward,
                  '${torrent.seedersFormatted}↑',
                  colors,
                ),
                if (torrent.imdbId != null && torrent.imdbId!.isNotEmpty)
                  _meta(Icons.movie_outlined, torrent.imdbId!, colors),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => AppRoutes.toMagnetTorrentDetail(
                    context,
                    torrent,
                    enrichFrom: movie,
                    displayTitleHint: _magnetHintFromMovie(movie),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: Text(l10n.detailMagnetPlay),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => AppRoutes.toMagnetTorrentDetail(
                    context,
                    torrent,
                    enrichFrom: movie,
                    displayTitleHint: _magnetHintFromMovie(movie),
                  ),
                  child: Text(l10n.detailMagnetOpenDetail),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, DetailPageColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.muted),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(color: colors.muted, fontSize: 11),
        ),
      ],
    );
  }
}
