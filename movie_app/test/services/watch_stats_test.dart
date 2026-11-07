import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/watch_history.dart';
import 'package:movie_app/services/watch_stats.dart';

WatchHistory _h({
  required String name,
  String movieId = 'm1',
  String sourceId = 's1',
  int watchedMs = 0,
  int progress = 0,
  int duration = 0,
  DateTime? at,
}) {
  return WatchHistory(
    id: '${sourceId}_$movieId',
    movieId: movieId,
    sourceId: sourceId,
    movieName: name,
    progress: progress,
    duration: duration,
    watchedMs: watchedMs,
    lastWatchTime: at ?? DateTime(2026, 11, 5, 12),
  );
}

void main() {
  group('WatchStats.movieKeyFor', () {
    test('同片不同源归并成同一个键', () {
      final a = _h(name: '嫁金钗', movieId: '100', sourceId: 'a');
      final b = _h(name: '嫁金钗', movieId: '900', sourceId: 'b');
      expect(WatchStats.movieKeyFor(a), WatchStats.movieKeyFor(b));
    });

    test('片名归一化：去季集、去括号标签、忽略大小写与空格', () {
      expect(WatchStats.normalizeTitle('  Running Man 第二季 '), 'runningman');
      expect(WatchStats.normalizeTitle('庆余年 (2019)'), '庆余年');
      expect(WatchStats.normalizeTitle('流浪地球【国语】'), '流浪地球');
    });

    test('片名为空时退回 id 组合，不能全并成一条', () {
      final a = _h(name: '', movieId: '1', sourceId: 'a');
      final b = _h(name: '', movieId: '2', sourceId: 'b');
      expect(WatchStats.movieKeyFor(a), isNot(WatchStats.movieKeyFor(b)));
    });
  });

  group('WatchStats.aggregate', () {
    test('同片多源算 1 部，时长取最大值而不是相加', () {
      final list = [
        _h(name: '嫁金钗', sourceId: 'a', movieId: '1', watchedMs: 3600000),
        _h(name: '嫁金钗', sourceId: 'b', movieId: '2', watchedMs: 1800000),
        _h(name: '嫁金钗', sourceId: 'c', movieId: '3', watchedMs: 600000),
      ];
      final agg = WatchStats.aggregate(list);
      expect(agg.length, 1);
      expect(agg.first.watchedMs, 3600000);
      expect(WatchStats.totalWatchedMs(list), 3600000);
    });

    test('不同影片时长累加', () {
      final list = [
        _h(name: 'A', movieId: '1', watchedMs: 3600000),
        _h(name: 'B', movieId: '2', watchedMs: 1800000),
      ];
      expect(WatchStats.totalWatchedMs(list), 5400000);
      expect(WatchStats.totalMovies(list), 2);
    });

    test('无时长数据时总时长为 0（页面显示占位符，不编数字）', () {
      final list = [_h(name: 'A', progress: 60000, duration: 7200000)];
      expect(WatchStats.totalWatchedMs(list), 0);
    });

    test('排序：时长优先，其次进度，再其次最近观看', () {
      final old = DateTime(2026, 10, 1);
      final fresh = DateTime(2026, 11, 5);
      final list = [
        _h(name: '低时长', movieId: '1', watchedMs: 1000, at: fresh),
        _h(name: '高时长', movieId: '2', watchedMs: 9000, at: old),
        _h(
          name: '无时长高进度',
          movieId: '3',
          progress: 900,
          duration: 1000,
          at: old,
        ),
      ];
      final agg = WatchStats.aggregate(list);
      expect(
        agg.map((e) => e.title).toList(),
        ['高时长', '低时长', '无时长高进度'],
      );
    });
  });

  group('WatchStats 活跃度', () {
    test('同一天同片多源只算一次', () {
      final day = DateTime(2026, 11, 5, 10);
      final list = [
        _h(name: 'A', sourceId: 's1', movieId: '1', at: day),
        _h(name: 'A', sourceId: 's2', movieId: '2', at: day),
        _h(name: 'B', movieId: '3', at: day),
      ];
      final counts = WatchStats.dailyMovieCounts(
        list,
        now: DateTime(2026, 11, 5, 20),
      );
      expect(counts['11-5'], 2);
      expect(
        WatchStats.recentMovieCount(list, now: DateTime(2026, 11, 5, 20)),
        2,
      );
    });

    test('超出窗口的记录不计入活跃度', () {
      final list = [
        _h(name: 'A', at: DateTime(2026, 1, 1)),
      ];
      final counts = WatchStats.dailyMovieCounts(
        list,
        now: DateTime(2026, 11, 5),
      );
      expect(counts, isEmpty);
      expect(
        WatchStats.recentMovieCount(list, now: DateTime(2026, 11, 5)),
        0,
      );
    });
  });

  group('WatchStats 展示文案', () {
    test('时长格式化：秒 / 分钟 / 小时 / 无数据占位', () {
      expect(WatchStats.formatDuration(0).value, '—');
      expect(WatchStats.formatDuration(0).unit, '观看时长');
      expect(WatchStats.formatDuration(45000).value, '45');
      expect(WatchStats.formatDuration(45000).unit, '秒');
      expect(WatchStats.formatDuration(120000).value, '2');
      expect(WatchStats.formatDuration(120000).unit, '分钟');
      expect(WatchStats.formatDuration(5400000).value, '1.5');
      expect(WatchStats.formatDuration(5400000).unit, '小时');
    });

    test('角标：有时长显示时长，没有则显示进度', () {
      expect(WatchStats.badgeText(30000, 0.9), '30 秒');
      expect(WatchStats.badgeText(300000, 0.9), '5 分钟');
      expect(WatchStats.badgeText(0, 0.12), '已看 12%');
      expect(WatchStats.badgeText(0, 0), '—');
    });
  });

  group('WatchHistory.watchedMs 持久化', () {
    test('toJson / fromJson 往返保留累计时长', () {
      final h = _h(name: 'A', watchedMs: 123456);
      final restored = WatchHistory.fromJson(h.toJson());
      expect(restored.watchedMs, 123456);
    });

    test('老存档缺少 watchedMs 时兜底为 0', () {
      final json = _h(name: 'A').toJson()..remove('watchedMs');
      expect(WatchHistory.fromJson(json).watchedMs, 0);
    });

    test('copyWith 可单独更新累计时长', () {
      final h = _h(name: 'A', watchedMs: 1000);
      expect(h.copyWith(watchedMs: 5000).watchedMs, 5000);
      expect(h.copyWith(watchedMs: 5000).movieName, 'A');
    });
  });
}
