import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/channel_portal_kind.dart';
import '../config/channel_portal_module_catalog.dart';
import '../config/routes.dart';
import '../l10n/app_localizations.dart';
import '../models/movie.dart';
import '../pages/channel/widgets/category_portal_module_row.dart';
import '../providers/movie_provider.dart';

/// 宽屏首页推荐区：对齐 `hifi-screen-home-windows.html` 各频道「左 5×2 + 右榜」。
class HiFiHomeWidePortalModules extends StatelessWidget {
  const HiFiHomeWidePortalModules({super.key});

  static bool _movieMatchesKind(Movie m, ChannelPortalKind kind) {
    final tag = kind.categoryApiValue;
    if (m.genres.contains(tag)) {
      return true;
    }
    if (kind == ChannelPortalKind.tv) {
      return m.genres.contains('连续剧') ||
          m.genres.contains('电视剧') ||
          m.genres.contains('国产剧');
    }
    return false;
  }

  static List<Movie> _orderedPool(MovieProvider p) {
    final byId = <String, Movie>{};
    void take(Iterable<Movie> list) {
      for (final m in list) {
        byId.putIfAbsent(m.id, () => m);
      }
    }

    take(p.latestMovies);
    take(p.hotMovies);
    take(p.topRatedMovies);
    take(p.homeMovies);
    take(p.classicMovies);
    take(p.bannerList);
    return byId.values.toList();
  }

  static List<Movie> _gridMovies(List<Movie> pool, ChannelPortalKind kind) {
    final out = <Movie>[];
    final seen = <String>{};
    for (final m in pool) {
      if (_movieMatchesKind(m, kind) && seen.add(m.id)) {
        out.add(m);
        if (out.length >= 10) {
          return out;
        }
      }
    }
    for (final m in pool) {
      if (seen.add(m.id)) {
        out.add(m);
        if (out.length >= 10) {
          return out;
        }
      }
    }
    return out;
  }

  static List<Movie> _rankMovies(List<Movie> pool, ChannelPortalKind kind) {
    final filtered = pool
        .where((m) => _movieMatchesKind(m, kind))
        .toList(growable: false)
      ..sort((a, b) => b.rating.compareTo(a.rating));
    if (filtered.length >= 7) {
      return filtered.take(7).toList(growable: false);
    }
    final ids = filtered.map((e) => e.id).toSet();
    final rest = pool.where((m) => !ids.contains(m.id)).toList(growable: false)
      ..sort((a, b) => b.rating.compareTo(a.rating));
    final out = [...filtered];
    for (final m in rest) {
      if (out.length >= 7) {
        break;
      }
      out.add(m);
    }
    return out.take(7).toList(growable: false);
  }

  static String _channelTitle(AppLocalizations l10n, ChannelPortalKind kind) {
    return switch (kind) {
      ChannelPortalKind.movies => l10n.navChannelMovies,
      ChannelPortalKind.tv => l10n.navChannelTv,
      ChannelPortalKind.variety => l10n.navChannelVariety,
      ChannelPortalKind.anime => l10n.navChannelAnime,
      ChannelPortalKind.short => l10n.navChannelShort,
    };
  }

  Widget _chipRow(
    BuildContext context, {
    required ChannelPortalKind kind,
    required AppLocalizations l10n,
  }) {
    final theme = Theme.of(context);
    final genres = ChannelPortalModuleCatalog.fixedGenres(kind);
    final chips = <Widget>[
      ActionChip(
        label: Text(l10n.homePortalChipLatest),
        visualDensity: VisualDensity.compact,
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        onPressed: () => AppRoutes.toChannelPortal(context, kind),
      ),
    ];
    for (var i = 1; i < genres.length; i++) {
      final g = genres[i];
      if (g == null || g.isEmpty) {
        continue;
      }
      chips.add(
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: ActionChip(
            label: Text(g),
            visualDensity: VisualDensity.compact,
            onPressed: () => AppRoutes.toChannelPortal(context, kind),
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: chips);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final movieProvider = context.watch<MovieProvider>();
    final pool = _orderedPool(movieProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final kind in ChannelPortalKind.values)
          CategoryPortalModuleRow(
            title: _channelTitle(l10n, kind),
            rankHeading: l10n.homePortalRankSectionTitle(
              _channelTitle(l10n, kind),
            ),
            movies: _gridMovies(pool, kind),
            rankMovies: _rankMovies(pool, kind),
            wide: true,
            narrowGridCrossAxisCount: 5,
            filterChips: _chipRow(context, kind: kind, l10n: l10n),
            onMorePressed: () => AppRoutes.toChannelPortal(context, kind),
            moreTooltip: l10n.categoryPortalModuleMore,
          ),
      ],
    );
  }
}
