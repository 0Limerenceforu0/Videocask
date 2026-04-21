import 'package:flutter/material.dart';

import 'package:movie_app/config/routes.dart';
import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/torrent_info.dart';
import 'package:movie_app/utils/torrent_title_display.dart';

import 'detail_ui_tokens.dart';

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
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
            ),
            OutlinedButton.icon(
              onPressed: isLoading ? null : () => onRefreshLoose(),
              icon: const Icon(Icons.zoom_out_map, size: 18),
              label: Text(l10n.detailMagnetRefreshLoose),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
            ),
            TextButton.icon(
              onPressed: isLoading
                  ? null
                  : () => AppRoutes.toSearch(context, query: movie.name),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l10n.detailMagnetOpenInSearch),
              style:
                  TextButton.styleFrom(foregroundColor: Colors.lightBlueAccent),
            ),
          ],
        ),
        if (isLoading) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.detailMagnetSearching,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
        if (!isLoading && statusMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            statusMessage,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
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
    required this.dense,
  });

  final Movie movie;
  final TorrentInfo torrent;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lines = splitTorrentDisplayTitle(torrent.name);
    final showZhLabel = torrentTitlePrimaryIsMostlyLatin(torrent.name);

    return Material(
      color: Colors.white10,
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
                        color: kDetailAccentColor.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        movie.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.detailMagnetZhLabelHint,
                        style: const TextStyle(
                          color: Colors.white38,
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
              style: const TextStyle(
                color: Colors.white,
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
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _meta(Icons.storage_outlined, torrent.sizeFormatted),
                _meta(Icons.cloud_outlined, torrent.source),
                _meta(Icons.arrow_upward, '${torrent.seedersFormatted}↑'),
                if (torrent.imdbId != null && torrent.imdbId!.isNotEmpty)
                  _meta(Icons.movie_outlined, torrent.imdbId!),
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

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }
}
