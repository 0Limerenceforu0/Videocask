import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:movie_app/config/routes.dart';
import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/torrent_info.dart';
import 'package:movie_app/utils/torrent_title_display.dart';
import 'package:movie_app/widgets/magnet_action_widgets.dart';

import 'detail_ui_tokens.dart';

String? _magnetHintFromMovie(Movie movie) {
  final name = movie.name.trim();
  if (name.isNotEmpty && RegExp(r'[\u4e00-\u9fff]').hasMatch(name)) {
    return name;
  }
  return null;
}

/// 详情页内嵌：磁力聚合结果列表（与搜索页相同 [TorrentSearchService] 逻辑，由上层传入 strict/loose 搜索结果）。
///
/// 结果分页展示：默认每页 [defaultPageSize] 条，可在 [pageSizeOptions] 之间切换。
/// 聚合结果动辄几十上百条，一次性构建全部卡片会让详情页滚动明显掉帧，
/// 分页同时改善流畅度与「翻到后面看什么」的可控性。
class DetailMagnetResultsPanel extends StatefulWidget {
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

  /// 每页条数可选项（用户可调）。
  static const List<int> pageSizeOptions = <int>[20, 50, 100];

  /// 默认每页条数。
  static const int defaultPageSize = 20;

  /// 每页条数持久化 key（记住上次选择）。
  static const String pageSizePrefsKey = 'detail_magnet_page_size';

  final Movie movie;
  final List<TorrentInfo> results;
  final bool isLoading;

  /// 非空时表示提示或错误（加载中时由上层文案覆盖）
  final String statusMessage;
  final Future<void> Function() onRefreshStrict;
  final Future<void> Function() onRefreshLoose;
  final bool dense;

  @override
  State<DetailMagnetResultsPanel> createState() =>
      _DetailMagnetResultsPanelState();
}

class _DetailMagnetResultsPanelState extends State<DetailMagnetResultsPanel> {
  /// 列表顶部锚点：翻页后把面板滚回可见区域顶部。
  final GlobalKey _anchorKey = GlobalKey();

  int _page = 0;
  int _pageSize = DetailMagnetResultsPanel.defaultPageSize;

  @override
  void initState() {
    super.initState();
    _restorePageSize();
  }

  @override
  void didUpdateWidget(covariant DetailMagnetResultsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 新一轮搜索会换掉列表实例 → 回到第 1 页。
    if (!identical(widget.results, oldWidget.results)) {
      _page = 0;
    }
  }

  Future<void> _restorePageSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(DetailMagnetResultsPanel.pageSizePrefsKey);
      if (!mounted) return;
      if (saved != null &&
          DetailMagnetResultsPanel.pageSizeOptions.contains(saved) &&
          saved != _pageSize) {
        setState(() => _pageSize = saved);
      }
    } catch (e) {
      debugPrint('读取磁力每页条数失败: $e');
    }
  }

  Future<void> _savePageSize(int size) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(DetailMagnetResultsPanel.pageSizePrefsKey, size);
    } catch (e) {
      debugPrint('保存磁力每页条数失败: $e');
    }
  }

  void _changePageSize(int size) {
    if (size == _pageSize) return;
    setState(() {
      _pageSize = size;
      _page = 0;
    });
    _savePageSize(size);
    _scrollToPanelTop();
  }

  void _goToPage(int page) {
    setState(() => _page = page);
    _scrollToPanelTop();
  }

  /// 翻页后把面板顶部滚到可视区（避免从第 2 页底部继续往下翻时看不见列表开头）。
  void _scrollToPanelTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _anchorKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = DetailPageColors.of(context);

    final results = widget.results;
    final total = results.length;
    final pageSize = _pageSize;
    final pageCount = total == 0 ? 1 : ((total - 1) ~/ pageSize) + 1;
    final currentPage = _page.clamp(0, pageCount - 1);
    final start = currentPage * pageSize;
    final end = (start + pageSize).clamp(0, total);
    final pageItems = total == 0
        ? const <TorrentInfo>[]
        : results.sublist(start, end);

    return Column(
      key: _anchorKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: widget.isLoading
                  ? null
                  : () => widget.onRefreshStrict(),
              icon: const Icon(Icons.manage_search, size: 18),
              label: Text(l10n.detailMagnetRefreshStrict),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.onSurface,
                side: BorderSide(color: colors.muted.withValues(alpha: 0.6)),
              ),
            ),
            OutlinedButton.icon(
              onPressed: widget.isLoading
                  ? null
                  : () => widget.onRefreshLoose(),
              icon: const Icon(Icons.zoom_out_map, size: 18),
              label: Text(l10n.detailMagnetRefreshLoose),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.onSurface,
                side: BorderSide(color: colors.muted.withValues(alpha: 0.6)),
              ),
            ),
            TextButton.icon(
              onPressed: widget.isLoading
                  ? null
                  : () => AppRoutes.toSearch(context, query: widget.movie.name),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l10n.detailMagnetOpenInSearch),
              style: TextButton.styleFrom(foregroundColor: colors.accent),
            ),
          ],
        ),
        if (widget.isLoading) ...[
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
        if (!widget.isLoading && widget.statusMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            widget.statusMessage,
            style: TextStyle(color: colors.muted, fontSize: 13),
          ),
        ],
        if (!widget.isLoading && total > 0) ...[
          SizedBox(height: widget.dense ? 8 : 14),
          _buildPagerBar(
            l10n,
            colors,
            total: total,
            pageCount: pageCount,
            currentPage: currentPage,
          ),
          SizedBox(height: widget.dense ? 8 : 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pageItems.length,
            separatorBuilder: (_, __) =>
                SizedBox(height: widget.dense ? 8 : 10),
            itemBuilder: (context, i) {
              return _MagnetResultTile(
                movie: widget.movie,
                torrent: pageItems[i],
                colors: colors,
                dense: widget.dense,
              );
            },
          ),
          if (pageCount > 1) ...[
            SizedBox(height: widget.dense ? 8 : 10),
            _buildPageNav(
              l10n,
              colors,
              pageCount: pageCount,
              currentPage: currentPage,
            ),
          ],
        ],
      ],
    );
  }

  /// 顶部信息条：结果总数 + 每页条数选择 + 页码跳转。
  Widget _buildPagerBar(
    AppLocalizations l10n,
    DetailPageColors colors, {
    required int total,
    required int pageCount,
    required int currentPage,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.detailMagnetPaginationCount('$total'),
          style: TextStyle(color: colors.muted, fontSize: 12),
        ),
        _pageSizeMenu(l10n, colors),
        if (pageCount > 1)
          _navGroup(
            l10n,
            colors,
            pageCount: pageCount,
            currentPage: currentPage,
            compact: true,
          ),
      ],
    );
  }

  /// 每页条数下拉（20 / 50 / 100）。
  Widget _pageSizeMenu(AppLocalizations l10n, DetailPageColors colors) {
    return PopupMenuButton<int>(
      initialValue: _pageSize,
      tooltip: l10n.detailMagnetPageSizeLabel('$_pageSize'),
      onSelected: _changePageSize,
      color: colors.card,
      itemBuilder: (context) {
        return [
          for (final size in DetailMagnetResultsPanel.pageSizeOptions)
            PopupMenuItem<int>(
              value: size,
              child: Row(
                children: [
                  if (size == _pageSize)
                    Icon(Icons.check, size: 16, color: colors.accent)
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Text(
                    l10n.detailMagnetPageSizeLabel('$size'),
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 13,
                      fontWeight: size == _pageSize
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.chipBackground,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.detailMagnetPageSizeLabel('$_pageSize'),
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 14, color: colors.muted),
          ],
        ),
      ),
    );
  }

  /// 底部翻页条（上一页 / 页码 / 下一页）。
  Widget _buildPageNav(
    AppLocalizations l10n,
    DetailPageColors colors, {
    required int pageCount,
    required int currentPage,
  }) {
    return Center(
      child: _navGroup(
        l10n,
        colors,
        pageCount: pageCount,
        currentPage: currentPage,
        compact: false,
      ),
    );
  }

  Widget _navGroup(
    AppLocalizations l10n,
    DetailPageColors colors, {
    required int pageCount,
    required int currentPage,
    required bool compact,
  }) {
    final canPrev = currentPage > 0;
    final canNext = currentPage < pageCount - 1;
    final size = compact ? 16.0 : 20.0;
    final pad = compact ? 4.0 : 8.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 6, vertical: 0),
      decoration: BoxDecoration(
        color: colors.chipBackground,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: canPrev ? () => _goToPage(currentPage - 1) : null,
            icon: Icon(Icons.chevron_left, size: size),
            color: colors.onSurface,
            disabledColor: colors.faint.withValues(alpha: 0.4),
            tooltip: l10n.detailMagnetPrevPage,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.all(pad),
            constraints: const BoxConstraints(),
          ),
          Text(
            '${currentPage + 1} / $pageCount',
            style: TextStyle(
              color: colors.onSurface,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            onPressed: canNext ? () => _goToPage(currentPage + 1) : null,
            icon: Icon(Icons.chevron_right, size: size),
            color: colors.onSurface,
            disabledColor: colors.faint.withValues(alpha: 0.4),
            tooltip: l10n.detailMagnetNextPage,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.all(pad),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
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
                // 用 Wrap 而不是 Row：中文片名可能很长（磁力详情页的片名就是
                // 原始资源标题），Row 里非弹性的 Container 拿到的是无界宽度，
                // 标签会一路画到屏幕外（2026-10-27 用户实测「名称超出屏幕」）。
                // Wrap 会给子项一个 maxWidth，文字因此能省略号收尾。
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
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
                    Text(
                      l10n.detailMagnetZhLabelHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.faint, fontSize: 11),
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
                MagnetSubtitleBadge(
                  title: torrent.name,
                  compact: true,
                  muted: colors.muted,
                  accent: colors.accent,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 用 Row + Expanded 平分三份，保证「播放 / 磁力详情 / 下载」
            // 恒在同一行；以前用 Wrap，窄屏上下载按钮会掉到第二行。
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => AppRoutes.toMagnetTorrentDetail(
                      context,
                      torrent,
                      enrichFrom: movie,
                      displayTitleHint: _magnetHintFromMovie(movie),
                    ),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Flexible(
                      child: Text(
                        l10n.detailMagnetPlay,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextButton(
                    onPressed: () => AppRoutes.toMagnetTorrentDetail(
                      context,
                      torrent,
                      enrichFrom: movie,
                      displayTitleHint: _magnetHintFromMovie(movie),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      l10n.detailMagnetOpenDetail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: MagnetDownloadButton(
                    magnetUri: torrent.magnetUri,
                    name: torrent.name,
                    foreground: colors.onSurface,
                    borderColor: colors.muted,
                    compact: true,
                  ),
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
        // 来源名可能很长，给 Text 一个可收缩的约束，宁可省略号也不要溢出。
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }

  // 「下载」改为直接触发 App 内 BT 下载（见 MagnetDownloadButton），
  // 不再只把磁力链接复制到剪贴板。
}
