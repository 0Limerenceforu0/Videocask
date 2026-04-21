import 'package:flutter/material.dart';

import '../../config/routes.dart';
import '../../l10n/app_localizations.dart';
import '../../models/movie.dart';
import '../../theme/hifi_design_tokens.dart';

/// 频道页右侧「热播榜」：按评分排序的本地切片，与静态稿侧栏信息架构一致。
class CategoryPortalSideRank extends StatelessWidget {
  const CategoryPortalSideRank({
    super.key,
    required this.movies,
    this.rankHeading,
  });

  final List<Movie> movies;

  /// 为 `null` 时使用 [AppLocalizations.categoryPortalHotRankTitle]。
  final String? rankHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (movies.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.categoryPortalRankEmpty,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rankHeading ?? l10n.categoryPortalHotRankTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...List<Widget>.generate(movies.length, (i) {
              final m = movies[i];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: i < 3
                          ? HiFiDesignTokens.accent
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                title: Text(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: m.rating > 0
                    ? Text(
                        l10n.categoryPortalRankScore(
                          m.rating.toStringAsFixed(1),
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.hintColor,
                        ),
                      )
                    : null,
                onTap: () => AppRoutes.toDetail(
                  context,
                  id: m.id,
                  sourceId: m.sourceId,
                  movie: m,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
