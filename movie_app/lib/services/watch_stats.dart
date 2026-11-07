import '../models/watch_history.dart';

/// 单部影片的聚合结果。
class MovieWatchAggregate {
  const MovieWatchAggregate({
    required this.key,
    required this.title,
    required this.cover,
    required this.watchedMs,
    required this.progressRatio,
    required this.lastWatchTime,
  });

  final String key;
  final String title;
  final String cover;

  /// 累计观看时长（毫秒）。同片多源取最大值，避免重复相加虚增。
  final int watchedMs;

  /// 观看进度比例（0~1），同片多源取最大值。
  final double progressRatio;

  final DateTime lastWatchTime;
}

/// 观影统计的纯计算逻辑（不依赖 Flutter，可单测）。
///
/// 历史记录是「一条 = 一个源下的一部片」，同一部片换了源就会出现多条。
/// 旧版统计直接拿条数当时长来源，还用 `watchCount * 1.5` 编小时数，
/// 这里全部换成可核实的数据：去重后的影片数 + 真实累计播放时长。
class WatchStats {
  const WatchStats._();

  /// 同一部影片的归并键。
  ///
  /// 优先用归一化片名——不同采集源的 movieId 完全不同，用 `sourceId_movieId`
  /// 会把《嫁金钗》这种多源影片算成好几部。片名为空时退回 id 组合。
  static String movieKeyFor(WatchHistory h) {
    final normalized = normalizeTitle(h.movieName);
    if (normalized.isNotEmpty) return normalized;
    return '${h.sourceId}_${h.movieId}';
  }

  /// 片名归一化：去空白、去季集后缀、去常见画质/格式标签。
  static String normalizeTitle(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    // 全角空格 / 间隔符统一
    s = s.replaceAll(RegExp(r'[\s\u3000]+'), '');
    // 「第1季」「第二季」「第 3 集」
    s = s.replaceAll(RegExp(r'第[0-9一二三四五六七八九十百]+[季集部]'), '');
    // 结尾的 (2024) / 【国语】 / [HD] 等
    s = s.replaceAll(RegExp(r'[\(\[【（].*?[\)\]】）]'), '');
    return s;
  }

  /// 按影片去重聚合，按时长降序（时长相同再按最近观看时间）。
  static List<MovieWatchAggregate> aggregate(List<WatchHistory> histories) {
    final map = <String, MovieWatchAggregate>{};
    for (final h in histories) {
      final key = movieKeyFor(h);
      final prev = map[key];
      final ratio = h.progressPercent;
      if (prev == null) {
        map[key] = MovieWatchAggregate(
          key: key,
          title: h.movieName,
          cover: h.movieCover,
          watchedMs: h.watchedMs,
          progressRatio: ratio,
          lastWatchTime: h.lastWatchTime,
        );
        continue;
      }
      map[key] = MovieWatchAggregate(
        key: key,
        title: prev.title.isNotEmpty ? prev.title : h.movieName,
        cover: prev.cover.isNotEmpty ? prev.cover : h.movieCover,
        watchedMs:
            prev.watchedMs > h.watchedMs ? prev.watchedMs : h.watchedMs,
        progressRatio:
            prev.progressRatio > ratio ? prev.progressRatio : ratio,
        lastWatchTime: h.lastWatchTime.isAfter(prev.lastWatchTime)
            ? h.lastWatchTime
            : prev.lastWatchTime,
      );
    }
    final list = map.values.toList()
      ..sort((a, b) {
        final byTime = b.watchedMs.compareTo(a.watchedMs);
        if (byTime != 0) return byTime;
        final byProgress = b.progressRatio.compareTo(a.progressRatio);
        if (byProgress != 0) return byProgress;
        return b.lastWatchTime.compareTo(a.lastWatchTime);
      });
    return list;
  }

  /// 去重后的影片总数。
  static int totalMovies(List<WatchHistory> histories) =>
      aggregate(histories).length;

  /// 累计观看时长（毫秒）。同片多源取最大值，不做重复相加。
  static int totalWatchedMs(List<WatchHistory> histories) {
    var sum = 0;
    for (final item in aggregate(histories)) {
      sum += item.watchedMs;
    }
    return sum;
  }

  /// 最近 [days] 天内每天观看的不同影片数。
  ///
  /// 同一部片换了源、或同一天反复播放，都只算一次，避免条形图虚高。
  static Map<String, int> dailyMovieCounts(
    List<WatchHistory> histories, {
    int days = 30,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final from = today.subtract(Duration(days: days - 1));
    final fromDay = DateTime(from.year, from.month, from.day);
    final seen = <String, Set<String>>{};
    for (final h in histories) {
      final day = DateTime(
        h.lastWatchTime.year,
        h.lastWatchTime.month,
        h.lastWatchTime.day,
      );
      if (day.isBefore(fromDay)) continue;
      final dayKey = '${h.lastWatchTime.month}-${h.lastWatchTime.day}';
      seen.putIfAbsent(dayKey, () => <String>{}).add(movieKeyFor(h));
    }
    return seen.map((k, v) => MapEntry(k, v.length));
  }

  /// 最近 [days] 天内看过的不同影片数。
  static int recentMovieCount(
    List<WatchHistory> histories, {
    int days = 30,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final from = today.subtract(Duration(days: days));
    final keys = <String>{};
    for (final h in histories) {
      if (h.lastWatchTime.isAfter(from)) keys.add(movieKeyFor(h));
    }
    return keys.length;
  }

  /// 累计时长展示：不足 1 分钟按秒，不足 1 小时按分钟。
  ///
  /// 没有数据时返回占位符，绝不回退成某个估算值——刚看几十秒却显示
  /// 「0 分钟」也会让人以为没记录上。
  static ({String value, String unit}) formatDuration(int ms) {
    if (ms <= 0) return (value: '—', unit: '观看时长');
    if (ms < 60000) {
      final seconds = (ms / 1000).round();
      return (value: '${seconds < 1 ? 1 : seconds}', unit: '秒');
    }
    final minutes = ms ~/ 60000;
    if (minutes < 60) return (value: '$minutes', unit: '分钟');
    return (value: (ms / 3600000).toStringAsFixed(1), unit: '小时');
  }

  /// TOP 列表右侧角标：有时长显示时长，否则退回真实观看进度。
  static String badgeText(int watchedMs, double progressRatio) {
    if (watchedMs > 0) {
      if (watchedMs < 60000) {
        final seconds = (watchedMs / 1000).round();
        return '${seconds < 1 ? 1 : seconds} 秒';
      }
      final minutes = watchedMs ~/ 60000;
      if (minutes < 60) return '$minutes 分钟';
      return '${(watchedMs / 3600000).toStringAsFixed(1)} 小时';
    }
    final percent = (progressRatio * 100).round();
    if (percent > 0) return '已看 $percent%';
    return '—';
  }
}
