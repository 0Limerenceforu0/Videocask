import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/channel_portal_kind.dart';
import '../l10n/app_localizations.dart';
import '../theme/hifi_design_tokens.dart';

/// Web 宽屏顶栏：频道文字入口（对齐静态稿 `hifi-kp-topbar` 中的频道链接）。
class HiFiChannelNavRow extends StatelessWidget {
  const HiFiChannelNavRow({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentPath = GoRouterState.of(context).uri.path;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChannelLink(
          label: l10n.navChannelMovies,
          path: ChannelPortalKind.movies.path,
          currentPath: currentPath,
        ),
        _ChannelLink(
          label: l10n.navChannelTv,
          path: ChannelPortalKind.tv.path,
          currentPath: currentPath,
        ),
        _ChannelLink(
          label: l10n.navChannelVariety,
          path: ChannelPortalKind.variety.path,
          currentPath: currentPath,
        ),
        _ChannelLink(
          label: l10n.navChannelAnime,
          path: ChannelPortalKind.anime.path,
          currentPath: currentPath,
        ),
        _ChannelLink(
          label: l10n.navChannelShort,
          path: ChannelPortalKind.short.path,
          currentPath: currentPath,
        ),
      ],
    );
  }
}

class _ChannelLink extends StatelessWidget {
  const _ChannelLink({
    required this.label,
    required this.path,
    required this.currentPath,
  });

  final String label;
  final String path;
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = currentPath == path;
    final color =
        selected ? HiFiDesignTokens.accent : theme.colorScheme.onSurface;

    return TextButton(
      onPressed: selected ? null : () => context.push(path),
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}
