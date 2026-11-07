import '../models/movie.dart';
import 'cms_category_resolver.dart';

/// 轮播条目挑选（纯函数，无IO）。
///
/// 背景（2026-10-21 修复）：
/// 1. 首页轮播原本直接取「最近更新第 1 页前 5 条」，且**全站无分类筛选**，
///    于是切「电影/剧集/动漫…」Tab 时 banner 完全不变 —— 用户看到每个类目
///    轮播图都一样；且 banner 内容与所选类目无关。
/// 2. 多条无封面条目在轮播里视觉上都是同一张空白块，同样表现为「都一样」。
/// 3. 多源合并的类目列表里会混进异类条目（实测 lzi「海外动漫」里有印度
///    真人剧、某源「连续剧」里有动画电影），按评分降序挑选时异类直接
///    霸占 banner —— 表现为「动漫 Tab 顶部是剧集简介」。
///
/// 契约：
/// - 输入必须已按评分降序（调用方用同一份排序结果，避免重复排序）；
/// - 优先「有封面 + 有评分 + 属于该类目」的条目，评分高的在前；
/// - 不足 [limit] 条时用剩余条目补齐，宁可条目信息不全也不要空轮播；
/// - [category] 为空（推荐页全站数据）时不做类目过滤；
/// - 不修改入参列表，不重复同一条目。
List<Movie> pickBannerMovies(
  List<Movie> sorted, {
  int limit = 5,
  String category = '',
}) {
  if (limit <= 0 || sorted.isEmpty) return const <Movie>[];
  final pool = _categoryPool(sorted, category);
  final picked = <Movie>[];
  final seen = <String>{};
  // 第一轮：可用条目（有封面 + 有评分）
  for (final m in pool) {
    if (picked.length >= limit) break;
    if (m.cover.trim().isEmpty || m.rating <= 0) continue;
    if (seen.add(m.id)) picked.add(m);
  }
  if (picked.length >= limit) return picked;
  // 第二轮：补齐（保留其余条目，避免类目数据稀疏时轮播整块消失）
  for (final m in pool) {
    if (picked.length >= limit) break;
    if (!seen.add(m.id)) continue;
    picked.add(m);
  }
  return picked;
}

/// 轮播候选池：只保留「源站分类名属于该类目」的条目。
///
/// - 全被滤掉（该类目数据一条都没有 type_name 匹配）时退回全量 —— 轮播
///   消失比展示异类更糟；
/// - type_name 为空的条目保留（见 [CmsCategoryResolver.typeNameBelongsTo]）。
List<Movie> _categoryPool(List<Movie> sorted, String category) {
  if (category.isEmpty) return sorted;
  final filtered = sorted
      .where((m) => CmsCategoryResolver.typeNameBelongsTo(category, m.typeName))
      .toList(growable: false);
  return filtered.isEmpty ? sorted : filtered;
}
