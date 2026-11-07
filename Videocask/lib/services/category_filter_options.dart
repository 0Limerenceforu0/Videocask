import '../models/movie.dart';

/// 分类页「类型 / 地区」候选词的动态聚合（纯函数）。
///
/// ## 为什么需要它
///
/// 筛选词原本是本地写死的（`CategoryFilterCatalog`），但**采集站自己标注的
/// `vod_class` 粒度与词表对不上**。实测（2026-10-21，lzi 源 `ac=detail&t=29`）：
///
/// ```
/// 本页 20 条的 vod_class 分布：
///   动画 9 | 动作,动画,奇幻 3 | (空) 2 | 剧情,动画,奇幻 1 | 喜剧,动作,动画,奇幻,古装 1 ...
/// ```
///
/// 词表里写的是「热血/校园/百合/泡面」这类二次元细分词，而站点只标到
/// 「动画/动作/奇幻/剧情」这一层 —— 于是选「热血」必然 0 命中，用户看到的是
/// 「筛选后只剩零星几条」，但真实原因是**那个词站里根本不存在**。
///
/// ## 做法
///
/// 从**已加载的该类目条目**里聚合真实出现过的 `vod_class` / `vod_area` 值，
/// 按出现频次降序生成候选词。这样：
/// - 用户选到的每个词，源里一定真的有 → 筛选必然有效；
/// - 不再依赖本地词表与源站标注对齐；
/// - 零额外网络请求（复用已经拉回来的数据）。
///
/// ## 词表来源的层级
///
/// 1. **动态词表**（本模块）：源实际有的词 —— 优先展示；
/// 2. **静态词表**（`CategoryFilterCatalog`）：本地兜底 —— 当源完全没返回
///    类型信息（`genreTags` 全空）时，至少还给出可选项。
///
/// 动态词表为空时退回静态词表；非空时取「动态 ∪ 静态中源也有的」，保证
/// 用户之前选中的词不会因为翻页而突然消失。
class CategoryFilterOptions {
  const CategoryFilterOptions({
    this.genres = const [],
    this.regions = const [],
  });

  /// 类型候选词（不含「全部」，由调用方补）。
  final List<String> genres;

  /// 地区候选词（不含「全部」，由调用方补）。
  final List<String> regions;

  /// 是否拿到了真实元数据（可用于决定要不要提示「筛选不生效」）。
  bool get hasMetadata => genres.isNotEmpty || regions.isNotEmpty;

  static const CategoryFilterOptions empty = CategoryFilterOptions();
}

/// 从一批影片聚合出动态候选词。
///
/// [maxItems] 限制单侧词条数量，避免极端情况下词条爆炸把筛选栏撑爆。
/// 排序：按出现次数降序；次数相同时按词条字典序，保证结果稳定可预期。
CategoryFilterOptions aggregateFilterOptions(
  Iterable<Movie> movies, {
  int maxItems = 12,
}) {
  final genreCount = <String, int>{};
  final regionCount = <String, int>{};

  for (final m in movies) {
    // 类型：只统计 `vod_class` 里的真实类型标签（不含分类名）。
    for (final tag in m.genreTags) {
      final t = tag.trim();
      if (t.isEmpty) continue;
      genreCount[t] = (genreCount[t] ?? 0) + 1;
    }
    // 地区：源里常见「中国大陆 / 大陆」两种写法，先归一再计数。
    final region = normalizeRegionLabel(m.region);
    if (region.isNotEmpty) {
      regionCount[region] = (regionCount[region] ?? 0) + 1;
    }
  }

  return CategoryFilterOptions(
    genres: _topByCount(genreCount, maxItems),
    regions: _topByCount(regionCount, maxItems),
  );
}

/// 归一地区写法：「大陆」→「中国大陆」，「香港」→「中国香港」等。
///
/// 采集站的 `vod_area` 写法不统一（实测 lzi 同时存在「中国大陆」和「大陆」），
/// 不归一会让同一个地区在筛选栏里裂成两个词。
String normalizeRegionLabel(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return '';
  // 已经是规范写法，直接返回。
  const known = {
    '中国大陆',
    '中国香港',
    '中国台湾',
    '中国澳门',
  };
  if (known.contains(v)) return v;
  switch (v) {
    case '大陆':
      return '中国大陆';
    case '香港':
      return '中国香港';
    case '台湾':
      return '中国台湾';
    case '澳门':
      return '中国澳门';
  }
  return v;
}

List<String> _topByCount(Map<String, int> counts, int maxItems) {
  if (counts.isEmpty) return const [];
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      if (c != 0) return c;
      // 频次相同时按码点升序（Dart `String.compareTo`）。中文码点序不等于拼音序，
      // 但词条先后对用户没有语义 —— 关键是**稳定**：同样的数据每次刷新顺序一致，
      // 不会因为翻页导致 chip 位置跳动。
      return a.key.compareTo(b.key);
    });
  return entries.take(maxItems).map((e) => e.key).toList(growable: false);
}