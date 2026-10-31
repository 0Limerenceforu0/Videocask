import '../models/movie.dart';
import '../models/play_source.dart';

/// 换源候选：某个源里最像目标影片的那一条 + 匹配分。
class DetailSourceCandidate {
  const DetailSourceCandidate({
    required this.source,
    required this.movie,
    required this.score,
  });

  final PlaySource source;
  final Movie movie;

  /// 综合匹配分（见 [DetailSourceMatcher.score]）；越大越像同一部片。
  final int score;
}

/// 详情页「换源」时的跨源同名匹配策略（2026-10-21）。
///
/// 背景：各 CMS 的 `vod_id` 仅在**本站**唯一，换源绝不能复用同一个 id
/// （会打开完全错误的片子）。所以换源的正确姿势是：拿片名去其他源搜一遍，
/// 再按「片名 + 年份」挑出最像同一部片的那个结果。
///
/// 本文件全是纯函数（不碰网络、不碰状态），便于单测覆盖匹配口径。
class DetailSourceMatcher {
  const DetailSourceMatcher._();

  /// 片名规范化：小写、去空白与标点，便于跨站比对。
  ///
  /// 采集站片名常带后缀（「片名 高清」「片名·国语」），规范化后能命中包含关系。
  static String normalizeName(String name) {
    final lowered = name.toLowerCase().trim();
    final noSpace = lowered.replaceAll(RegExp(r'[\s\u3000]+'), '');
    // 只保留中英文与数字，其余（标点、符号、全角标点）一律丢弃。
    return noSpace.replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), '');
  }

  /// 名称匹配分（不含年份修正）。
  ///
  /// - 规范化后完全相同：100
  /// - 一方包含另一方：70（采集站的后缀/副标题差异）
  /// - 毫无关系：0
  static int nameScore(String candidateName, String targetName) {
    final a = normalizeName(candidateName);
    final b = normalizeName(targetName);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 100;
    if (a.contains(b) || b.contains(a)) return 70;
    return 0;
  }

  /// 年份修正分：都有年份时一致加分、不一致重罚；缺年份不奖不罚。
  static int yearScore(String candidateYear, String targetYear) {
    final a = candidateYear.trim();
    final b = targetYear.trim();
    if (a.isEmpty || b.isEmpty) return 0;
    return a == b ? 15 : -40;
  }

  /// 综合匹配分；≤ 0 视为「不是同一部片」，UI 应隐藏该候选。
  static int score({
    required String candidateName,
    required String targetName,
    String candidateYear = '',
    String targetYear = '',
  }) {
    final n = nameScore(candidateName, targetName);
    if (n == 0) return 0;
    return n + yearScore(candidateYear, targetYear);
  }

  /// 从某个源的搜索结果里挑出最像 [target] 的那一条。
  ///
  /// 同分时取**先出现**的（采集站通常把最相关的排前面），避免翻页抖动。
  static Movie? pickBest(
    List<Movie> candidates, {
    required String targetName,
    String targetYear = '',
  }) {
    Movie? best;
    var bestScore = 0;
    for (final m in candidates) {
      final s = score(
        candidateName: m.name,
        targetName: targetName,
        candidateYear: m.year,
        targetYear: targetYear,
      );
      if (s <= 0) continue;
      if (s > bestScore) {
        bestScore = s;
        best = m;
      }
    }
    return best;
  }
}
