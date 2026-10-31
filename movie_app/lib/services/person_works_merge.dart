import '../models/movie.dart';

/// 人名搜索结果合并（2026-10-28）。
///
/// 「周星驰」这类人名有两条数据通道，现在是**并行**的：
/// * 关键词通道：`wd=周星驰` —— 快（实测 2~3s），支持演员匹配的源（量子资源）
///   能直接给 20 部，但顺序按源站热度；
/// * 代表作通道：豆瓣人物 → 6~8 部代表作逐部按片名查 —— 慢（实测跑满 20s
///   超时），但更准、按作品维度来。
///
/// 代表作回来后用本函数**合并**而不是覆盖：实测代表作只有 7~8 部，覆盖会
/// 把关键词那轮的 20 部砍成 8 部，用户看到的是「越搜越少」。
///
/// 排序：代表作在前（精确命中优先），关键词结果按 (片名, 年份) 去重后补后。
List<Movie> mergePersonWorks(
  List<Movie> works,
  List<Movie> keywordResults,
) {
  if (works.isEmpty) return keywordResults;
  if (keywordResults.isEmpty) return works;
  final seen = <String>{};
  final merged = <Movie>[];
  for (final m in <Movie>[...works, ...keywordResults]) {
    // 源站同一部片在不同线路下 `id` 不同，只能用片名+年份做身份。
    if (seen.add('${m.name}|${m.year}')) merged.add(m);
  }
  return merged;
}
