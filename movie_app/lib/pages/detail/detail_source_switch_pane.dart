import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/routes.dart';
import '../../l10n/app_localizations.dart';
import '../../models/movie.dart';
import '../../providers/movie_provider.dart';
import '../../providers/source_provider.dart';
import '../../services/detail_source_matcher.dart';

/// 详情页「换源」面板（2026-10-23）。
///
/// 用途：详情页 Tab 行的第二个 Tab（原「播放线路」）改成「换源」——
/// 播放线路的选择已由标题区的「换路线」chip 承担（点开是底部弹窗），
/// 而「换源」是跨站点换资源，天然是**面板**而不是 Tab 内容里的一个列表项，
/// 所以直接做成可嵌入的 widget。
///
/// ⚠️ 各 CMS 的 `vod_id` 仅在本站唯一，**换源不能复用同一个 id**，所以这里
/// 是按片名到其他启用源各搜第 1 页、用 [DetailSourceMatcher] 匹配出「同一部
/// 片的其它源条目」，选中后用**该源自己的 id** 重新进详情页。
///
/// 🔴 **增量显示**（用户实测「点击换源半天不能出来结果」）：搜索走 CMS 的
/// `ac=detail&wd=`，单源响应可达数百 KB～1MB，站点慢就迟迟不出结果。
/// 现在每个源一回来就立刻追加显示（见 [MovieProvider.searchMovieAcrossSources]
/// 的 `onPartial`），并显示「已从 N/M 个源取到结果」进度。
class DetailSourceSwitchPane extends StatefulWidget {
  const DetailSourceSwitchPane({
    super.key,
    required this.movie,
    this.dense = false,
  });

  final Movie movie;

  /// 紧凑模式：用于窄屏 Tab 内容区（行高更小、信息更少）。
  final bool dense;

  @override
  State<DetailSourceSwitchPane> createState() => _DetailSourceSwitchPaneState();
}

class _DetailSourceSwitchPaneState extends State<DetailSourceSwitchPane> {
  bool _loading = true;
  List<DetailSourceCandidate> _candidates = const <DetailSourceCandidate>[];
  int _doneSources = 0;
  int _totalSources = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  Future<void> _search() async {
    final provider = context.read<MovieProvider>();
    final sources = context.read<SourceProvider>().enabledSources;
    final total = sources.where((s) => s.id != widget.movie.sourceId).length;
    if (!mounted) return;
    setState(() {
      _totalSources = total;
      _doneSources = 0;
      _candidates = const <DetailSourceCandidate>[];
      _loading = true;
    });
    final list = await provider.searchMovieAcrossSources(
      keyword: widget.movie.name,
      year: widget.movie.year,
      sources: sources,
      excludeSourceId: widget.movie.sourceId,
      // 增量投递：哪个源先回来就先显示哪个，不等全部。
      onPartial: (snapshot) {
        if (!mounted) return;
        setState(() {
          _candidates = snapshot;
          _doneSources = (_doneSources + 1).clamp(0, _totalSources);
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _candidates = list;
      _doneSources = _totalSources;
      _loading = false;
    });
  }

  Future<void> _pick(DetailSourceCandidate candidate) async {
    final sourceProvider = context.read<SourceProvider>();
    final movieProvider = context.read<MovieProvider>();
    // 先切全局源：详情页按 `sourceId` 拉详情，进度/历史也按源走。
    await sourceProvider.selectSource(candidate.source.id);
    if (!mounted) return;
    movieProvider.setCurrentSource(candidate.source);
    if (!mounted) return;
    // 用**该源自己的 id** 重新进详情（不能复用原 id）。
    final uri = Uri.parse(AppRoutes.detail).replace(
      queryParameters: <String, String>{
        'id': candidate.movie.id,
        'sourceId': candidate.source.id,
      },
    );
    // go_router 的替换导航在 GoRouter 实例上（BuildContext 只暴露 push/go/replace）。
    unawaited(
      GoRouter.of(context)
          .pushReplacement(uri.toString(), extra: candidate.movie),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // 深色主题（surface #393E46）：次要文字不能写死 Colors.black54（会隐形）。
    final muted = theme.hintColor;

    if (_loading && _candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.detailSwitchSourceSearching,
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: Center(
          child: Text(
            l10n.detailSwitchSourceEmpty,
            style: TextStyle(color: muted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final rows = <Widget>[];
    for (final c in _candidates) {
      rows.add(
        _buildRow(l10n, theme, muted, c),
      );
      rows.add(const Divider(height: 1));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 进度提示：还有源在搜时明确告知「已经找到几个」，而不是干等。
        if (_loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.detailSwitchSourceProgress(_doneSources, _totalSources),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        Flexible(child: ListView.builder(shrinkWrap: true, itemCount: rows.length, itemBuilder: (_, i) => rows[i])),
      ],
    );
  }

  Widget _buildRow(
    AppLocalizations l10n,
    ThemeData theme,
    Color muted,
    DetailSourceCandidate c,
  ) {
    final exact = c.score >= 100;
    final episodes = c.movie.playRoutes.fold<int>(
      0,
      (sum, r) => sum + r.episodes.length,
    );
    final subtitle = StringBuffer(c.movie.name);
    if (c.movie.year.trim().isNotEmpty) {
      subtitle.write(' · ${c.movie.year}');
    }
    if (episodes > 0) {
      subtitle.write(' · ${l10n.detailSwitchSourceEpisodes(episodes)}');
    }
    return ListTile(
      dense: widget.dense,
      contentPadding: EdgeInsets.symmetric(horizontal: widget.dense ? 12 : 16),
      title: Text(
        c.source.name,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle.toString(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: exact
              ? theme.colorScheme.primary.withValues(alpha: 0.16)
              : muted.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          exact ? l10n.detailSwitchSourceExact : l10n.detailSwitchSourceFuzzy,
          style: TextStyle(
            color: exact ? theme.colorScheme.primary : muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      onTap: () => unawaited(_pick(c)),
    );
  }
}
