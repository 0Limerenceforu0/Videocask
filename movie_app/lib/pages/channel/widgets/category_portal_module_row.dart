import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/movie.dart';
import '../../../theme/hifi_design_tokens.dart';
import '../../home/movie_card.dart';
import '../../../widgets/movie_grid_layout.dart';
import '../category_portal_side_rank.dart';

/// 对齐静态稿 `hifi-kp-mod-row`：模块标题 + 左栅格 + 右热播榜。
class CategoryPortalModuleRow extends StatelessWidget {
  const CategoryPortalModuleRow({
    super.key,
    required this.title,
    required this.movies,
    required this.wide,
    required this.rankMovies,
    this.isLoading = false,
    this.errorMessage,
    this.onMorePressed,
    this.moreTooltip,
    this.filterChips,
    this.rankHeading,
  });

  final String title;
  final List<Movie> movies;
  final bool wide;
  final List<Movie> rankMovies;
  final bool isLoading;
  final String? errorMessage;

  /// 对齐静态 `hifi-kp-more-iconbtn`；为 `null` 时不显示。
  final VoidCallback? onMorePressed;

  /// [onMorePressed] 非空时应提供读屏/悬停说明。
  final String? moreTooltip;

  /// 对齐静态稿 `hifi-kp-mod-filters`；为 `null` 时不展示。
  final Widget? filterChips;

  /// 传入 [CategoryPortalSideRank] 的标题；为 `null` 时用默认「热播榜」。
  final String? rankHeading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final Widget grid;
    final err = errorMessage;
    if (err != null && err.isNotEmpty) {
      grid = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          err,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.error),
        ),
      );
    } else if (isLoading && movies.isEmpty) {
      grid = const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (movies.isEmpty) {
      grid = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          l10n.categoryPortalModuleEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
      );
    } else {
      grid = LayoutBuilder(
        builder: (context, constraints) {
          final contentW =
              constraints.maxWidth.isFinite && constraints.maxWidth > 0
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width - 24;
          final metrics = MovieGridLayout.metricsForWidth(contentW);
          final crossCount = wide
              ? math.min(5, metrics.crossAxisCount)
              : metrics.crossAxisCount;
          return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossCount,
            childAspectRatio: metrics.childAspectRatio,
            crossAxisSpacing: metrics.crossAxisSpacing,
            mainAxisSpacing: metrics.mainAxisSpacing,
            padding: EdgeInsets.zero,
            children: [for (final m in movies) MovieCard(movie: m)],
          );
        },
      );
    }

    final onMore = onMorePressed;
    final chips = filterChips;
    final head = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: HiFiDesignTokens.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 0,
            fit: FlexFit.loose,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ),
          if (chips != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: chips,
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (onMore != null)
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: onMore,
              tooltip: moreTooltip ?? l10n.categoryPortalModuleMore,
              style: IconButton.styleFrom(
                foregroundColor: theme.hintColor,
                padding: const EdgeInsets.all(4),
                minimumSize: const Size(40, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );

    final mainColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        grid,
      ],
    );

    if (wide) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: LayoutBuilder(
          builder: (context, c) {
            final total = c.maxWidth;
            if (!total.isFinite || total <= 0) {
              return mainColumn;
            }
            const gutter = 16.0;
            const minMain = 200.0;
            final rankW = math.min(
              300.0,
              math.max(160.0, total * 0.28),
            );
            final mainW = total - gutter - rankW;
            if (mainW < minMain) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  mainColumn,
                  const SizedBox(height: 12),
                  CategoryPortalSideRank(
                    movies: rankMovies,
                    rankHeading: rankHeading,
                  ),
                ],
              );
            }
            // 父级常为纵向无限高；stretch 会施加 h=∞。start 与左侧 Column 自然高度一致。
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: mainW, child: mainColumn),
                const SizedBox(width: gutter),
                SizedBox(
                  width: rankW,
                  child: SingleChildScrollView(
                    child: CategoryPortalSideRank(
                      movies: rankMovies,
                      rankHeading: rankHeading,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          mainColumn,
          const SizedBox(height: 12),
          CategoryPortalSideRank(
            movies: rankMovies,
            rankHeading: rankHeading,
          ),
        ],
      ),
    );
  }
}
