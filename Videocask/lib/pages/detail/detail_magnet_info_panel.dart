import 'package:flutter/material.dart';

import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/torrent_info.dart';
import 'package:movie_app/utils/torrent_title_display.dart';
import 'package:movie_app/widgets/magnet_action_widgets.dart';

import 'detail_ui_tokens.dart';

/// 磁力详情主标题：优先当前播放资源名，而非 TMDB/搜索补全后的片名。
({String primary, String? secondary}) detailMagnetTitleLines(
  Movie movie,
  TorrentInfo? torrent,
) {
  if (torrent != null) {
    final lines = splitTorrentDisplayTitle(torrent.name);
    if (lines.primary.trim().isNotEmpty) {
      return (primary: lines.primary.trim(), secondary: lines.secondary);
    }
  }
  final alias = movie.alias.trim();
  return (
    primary: movie.name.trim().isNotEmpty ? movie.name.trim() : alias,
    secondary: alias.isNotEmpty && alias != movie.name.trim() ? alias : null,
  );
}

/// 播放器 / 标题区「磁力播放」标识。
class DetailMagnetPlayingBadge extends StatelessWidget {
  const DetailMagnetPlayingBadge({
    super.key,
    this.compact = false,
    this.onDark = false,
  });

  final bool compact;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = DetailPageColors.of(context);
    final bg = onDark
        ? Colors.white.withValues(alpha: 0.18)
        : colors.accent.withValues(alpha: 0.16);
    final fg = onDark ? Colors.white : colors.accent;
    final iconSize = compact ? 14.0 : 16.0;
    final fontSize = compact ? 11.0 : 12.0;
    final padH = compact ? 8.0 : 10.0;
    final padV = compact ? 3.0 : 4.0;

    return Semantics(
      label: l10n.detailMagnetPlayingBadge,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: fg.withValues(alpha: onDark ? 0.45 : 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_rounded, size: iconSize, color: fg),
            const SizedBox(width: 4),
            Text(
              l10n.detailMagnetPlayingBadge,
              style: TextStyle(
                color: fg,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 磁力详情页：扩展元信息与资源卡片（导演/主演/地区/种子统计等）。
class DetailMagnetInfoPanel extends StatelessWidget {
  const DetailMagnetInfoPanel({
    super.key,
    required this.movie,
    this.torrent,
    this.showPlayingBadge = false,
  });

  final Movie movie;
  final TorrentInfo? torrent;
  final bool showPlayingBadge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = DetailPageColors.of(context);
    final alias = movie.alias.trim();
    final director = movie.director.trim();
    final actors = movie.actors.where((a) => a.trim().isNotEmpty).toList();
    final region = movie.region.trim();
    final torrentTitle =
        torrent != null ? splitTorrentDisplayTitle(torrent!.name) : null;
    final showAliasLine = alias.isNotEmpty &&
        alias != movie.name.trim() &&
        alias != (torrentTitle?.primary.trim() ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPlayingBadge) ...[
          const DetailMagnetPlayingBadge(),
          const SizedBox(height: 10),
        ],
        if (torrent != null ||
            _parsedSourceFromDescription(movie.description).isNotEmpty) ...[
          _TorrentResourceCard(
            l10n: l10n,
            colors: colors,
            torrent: torrent,
            resourceTitle: torrentTitle?.primary,
            resourceSubtitle: torrentTitle?.secondary,
            sourceFallback: _parsedSourceFromDescription(movie.description),
          ),
          const SizedBox(height: 12),
        ],
        if (showAliasLine) ...[
          Text(
            alias,
            style: TextStyle(
              color: colors.muted,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (director.isNotEmpty)
          _MetaRow(
            label: l10n.detailMagnetMetaDirector,
            value: director,
            colors: colors,
          ),
        if (actors.isNotEmpty)
          _MetaRow(
            label: l10n.detailMagnetMetaActors,
            value: actors.join(' / '),
            colors: colors,
          ),
        if (region.isNotEmpty)
          _MetaRow(
            label: l10n.detailMagnetMetaRegion,
            value: region,
            colors: colors,
          ),
        if (movie.genres.isNotEmpty)
          _MetaRow(
            label: l10n.detailMagnetMetaGenre,
            value: movie.genres.join(' / '),
            colors: colors,
          ),
      ],
    );
  }

  static String _parsedSourceFromDescription(String description) {
    final d = description.trim();
    if (d.startsWith('磁力：')) {
      return d.substring('磁力：'.length).trim();
    }
    for (final line in d.split('\n')) {
      final t = line.trim();
      if (t.startsWith('磁力索引：')) {
        return t.substring('磁力索引：'.length).trim();
      }
      if (t.startsWith('磁力索引:')) {
        return t.substring('磁力索引:'.length).trim();
      }
    }
    return '';
  }
}

/// 从简介中剥离磁力资源脚注，仅保留剧情简介。
String detailMagnetOverviewText(String description) {
  final buf = StringBuffer();
  for (final raw in description.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      continue;
    }
    if (line.startsWith('——') ||
        line.startsWith('磁力：') ||
        line.startsWith('磁力索引') ||
        line.startsWith('资源标题') ||
        line.startsWith('副标题：') ||
        line.startsWith('副标题:')) {
      break;
    }
    if (buf.isNotEmpty) buf.writeln();
    buf.write(line);
  }
  return buf.toString().trim();
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final DetailPageColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: TextStyle(color: colors.faint, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: colors.muted, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _TorrentResourceCard extends StatelessWidget {
  const _TorrentResourceCard({
    required this.l10n,
    required this.colors,
    this.torrent,
    this.resourceTitle,
    this.resourceSubtitle,
    this.sourceFallback = '',
  });

  final AppLocalizations l10n;
  final DetailPageColors colors;
  final TorrentInfo? torrent;
  final String? resourceTitle;
  final String? resourceSubtitle;
  final String sourceFallback;

  @override
  Widget build(BuildContext context) {
    final source = torrent?.source.trim().isNotEmpty == true
        ? torrent!.source.trim()
        : sourceFallback.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.divider.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.detailMagnetResourceSection,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (resourceTitle != null && resourceTitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.detailMagnetMetaResourceTitle,
              style: TextStyle(color: colors.faint, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              resourceTitle!.trim(),
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            if (resourceSubtitle != null &&
                resourceSubtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                resourceSubtitle!.trim(),
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              if (source.isNotEmpty)
                _StatChip(
                  icon: Icons.public_rounded,
                  text: l10n.detailMagnetMetaSource(source),
                  colors: colors,
                ),
              if (torrent != null)
                _StatChip(
                  icon: Icons.sd_storage_outlined,
                  text: l10n.detailMagnetMetaSize(torrent!.sizeFormatted),
                  colors: colors,
                ),
              if (torrent != null && torrent!.seeders > 0)
                _StatChip(
                  icon: Icons.upload_rounded,
                  text: l10n.detailMagnetMetaSeeders(torrent!.seedersFormatted),
                  colors: colors,
                  valueColor: const Color(0xFF2E7D32),
                ),
              if (torrent != null && torrent!.leechers > 0)
                _StatChip(
                  icon: Icons.download_rounded,
                  text: l10n.detailMagnetMetaLeechers('${torrent!.leechers}'),
                  colors: colors,
                ),
              if (torrent?.imdbId != null && torrent!.imdbId!.isNotEmpty)
                _StatChip(
                  icon: Icons.movie_outlined,
                  text: 'IMDb ${torrent!.imdbId}',
                  colors: colors,
                ),
            ],
          ),
          const SizedBox(height: 10),
          // 详情页也要能一眼看到字幕状态，并直接下载这个资源。
          Row(
            children: [
              Flexible(
                // 用 Wrap 而不是 Row：字幕徽标可能再挂一个「本片可下中字」，
                // 加上语言徽标后窄屏必须能换行，不能把下载按钮挤出屏幕。
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    MagnetSubtitleBadge(
                      title: torrent?.name ?? resourceTitle ?? '',
                      magnetUri: torrent?.magnetUri,
                      imdbId: torrent?.imdbId,
                      // 详情页只有当前这一条资源，进页面就自动探测。
                      autoProbe: true,
                      compact: true,
                      muted: colors.muted,
                      accent: colors.accent,
                    ),
                    MagnetAudioLanguageBadge(
                      title: torrent?.name ?? resourceTitle ?? '',
                      compact: true,
                      muted: colors.muted,
                      accent: colors.accent,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (torrent != null)
                SizedBox(
                  width: 116,
                  child: MagnetDownloadButton(
                    magnetUri: torrent!.magnetUri,
                    name: torrent!.name,
                    foreground: colors.onSurface,
                    borderColor: colors.muted,
                    compact: true,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.text,
    required this.colors,
    this.valueColor,
  });

  final IconData icon;
  final String text;
  final DetailPageColors colors;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final fg = valueColor ?? colors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: fg),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: fg,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
