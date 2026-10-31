import '../models/movie.dart';

/// 影片去重键的**唯一**口径。
///
/// 2026-10-31：之前这套逻辑散落三处、且口径不一致 ——
/// - `ApiService._dedupeKeyForMovie`：小写 + 去掉**所有**空白，年份 `'0'` 视为空；
/// - `MovieProvider._movieDedupeKey`：小写 + 仅 `.trim()`，年份 `'0'` 原样保留；
/// - `MovieProvider._appendCategoryDedup`：把 provider 口径又内联写了两遍。
///
/// 后果是跨层去重行为漂移：同一部片在「多源聚合」层被合并，却在「分类分页追加」
/// 层被当成两部（名字里多一个空格、年份是 `0` 就不相等），表现为列表里出现
/// 重复条目。这里统一成一套口径，三处都改为调用本类。
///
/// 口径：片名小写 + 去除所有空白字符；年份为空或 `'0'`（采集站常见的
/// 「未知年份」占位）一律视为「无年份」。
class MovieDedupe {
  const MovieDedupe._();

  /// 归一化年份：空字符串与 `'0'` 都视为「无年份」。
  static String normalizeYear(String year) {
    final y = year.trim();
    return (y.isEmpty || y == '0') ? '' : y;
  }

  /// 归一化片名：小写 + 去掉所有空白字符。
  static String normalizeName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  /// 统一去重键：`归一化片名|归一化年份`。
  static String key(Movie m) =>
      '${normalizeName(m.name)}|${normalizeYear(m.year)}';

  /// 两部片是否判定为同一部（同一去重键）。
  static bool same(Movie a, Movie b) => key(a) == key(b);
}
