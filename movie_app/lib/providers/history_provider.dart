import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../models/watch_history.dart';
import '../services/storage_service.dart';

/// 观看历史状态管理
class HistoryProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();

  /// 观看历史列表
  List<WatchHistory> _histories = [];

  /// 观看历史列表
  List<WatchHistory> get histories => _histories;

  /// 是否正在加载
  bool _isLoading = false;

  /// 是否正在加载
  bool get isLoading => _isLoading;

  /// 初始化
  Future<void> init() async {
    await loadHistories();
  }

  /// 加载观看历史
  Future<void> loadHistories() async {
    _isLoading = true;
    notifyListeners();

    _histories = _storage.getAllHistory();
    _isLoading = false;
    notifyListeners();
  }

  /// 保存/更新观看历史
  Future<void> saveOrUpdateHistory({
    required String movieId,
    required String movieName,
    required String movieCover,
    required int episodeIndex,
    required String episodeName,
    required int progress,
    required int duration,
    String sourceId = '',
    int routeIndex = 0,
    String? magnetUri,
  }) async {
    var existing = _storage.getHistory(movieId, sourceId: sourceId);
    existing ??= _histories
        .where((h) => h.movieId == movieId && h.sourceId == sourceId)
        .firstOrNull;

    String resolvedMagnet = '';
    if (sourceId == AppConstants.magnetDetailSourceId) {
      if (magnetUri != null && magnetUri.isNotEmpty) {
        resolvedMagnet = magnetUri;
      } else if (existing != null && existing.magnetUri.isNotEmpty) {
        resolvedMagnet = existing.magnetUri;
      }
    }

    // 起播/续播 seek 完成前 position 常为 0，勿用 0 覆盖同集同线路的有效进度
    var effectiveProgress = progress;
    var effectiveDuration = duration;
    if (progress == 0 &&
        existing != null &&
        existing.episodeIndex == episodeIndex &&
        existing.routeIndex == routeIndex &&
        existing.progress > 0) {
      final nearEnd = existing.duration > 0 &&
          existing.progress >= existing.duration - 2000;
      if (!nearEnd && (duration == 0 || progress < duration * 0.05)) {
        effectiveProgress = existing.progress;
        if (duration == 0 && existing.duration > 0) {
          effectiveDuration = existing.duration;
        }
      }
    }

    final isNew = existing == null;
    final episodeChanged = existing != null &&
        (existing.episodeIndex != episodeIndex ||
            existing.routeIndex != routeIndex);
    final nextWatchCount = isNew
        ? 1
        : (episodeChanged ? existing.watchCount + 1 : existing.watchCount);

    final history = WatchHistory(
      id: '${sourceId}_$movieId',
      movieId: movieId,
      sourceId: sourceId,
      movieName: movieName,
      movieCover: movieCover,
      episodeIndex: episodeIndex,
      episodeName: episodeName,
      progress: effectiveProgress,
      duration: effectiveDuration,
      routeIndex: routeIndex,
      lastWatchTime: DateTime.now(),
      watchCount: nextWatchCount,
      magnetUri: resolvedMagnet,
    );

    await _storage.saveHistory(history);

    // 更新列表
    final index = _histories
        .indexWhere((h) => h.movieId == movieId && h.sourceId == sourceId);
    if (index >= 0) {
      _histories[index] = history;
      // 移到最前面
      _histories.removeAt(index);
      _histories.insert(0, history);
    } else {
      _histories.insert(0, history);
    }

    notifyListeners();
  }

  /// 删除观看历史
  Future<void> deleteHistory(String movieId, {String sourceId = ''}) async {
    await _storage.deleteHistory(movieId, sourceId: sourceId);
    _histories
        .removeWhere((h) => h.movieId == movieId && h.sourceId == sourceId);
    notifyListeners();
  }

  /// 清空观看历史
  Future<void> clearAll() async {
    await _storage.clearHistory();
    _histories.clear();
    notifyListeners();
  }

  /// 获取指定影片的观看历史
  WatchHistory? getHistory(
    String movieId, {
    String sourceId = '',
    String magnetUri = '',
  }) {
    // 如果提供了磁力链接，优先根据movieId和magnetUri查找
    if (magnetUri.isNotEmpty) {
      return _histories
          .where((h) => h.movieId == movieId && h.magnetUri == magnetUri)
          .firstOrNull;
    }
    // 否则根据movieId和sourceId查找
    return _histories
        .where((h) => h.movieId == movieId && h.sourceId == sourceId)
        .firstOrNull;
  }

  /// 进入详情页时解析应恢复的观看记录（优先精确匹配，否则取该片最近一条）。
  WatchHistory? findHistoryForDetail({
    required String movieId,
    String sourceId = '',
    String magnetUri = '',
  }) {
    if (magnetUri.isNotEmpty) {
      final byMagnet = getHistory(movieId, magnetUri: magnetUri);
      if (byMagnet != null) return byMagnet;
    }
    if (sourceId.isNotEmpty) {
      final bySource = getHistory(movieId, sourceId: sourceId);
      if (bySource != null) return bySource;
    }
    for (final h in _histories) {
      if (h.movieId == movieId) return h;
    }
    return null;
  }

  /// 获取已看集数列表
  List<int> getWatchedEpisodes(String movieId, {String sourceId = ''}) {
    return _histories
        .where((h) => h.movieId == movieId && h.sourceId == sourceId)
        .map((h) => h.episodeIndex)
        .toList();
  }

  /// 历史数量
  int get count => _histories.length;

  /// 按日期分组
  Map<String, List<WatchHistory>> get groupedByDate {
    final Map<String, List<WatchHistory>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    for (final history in _histories) {
      final watchDate = DateTime(
        history.lastWatchTime.year,
        history.lastWatchTime.month,
        history.lastWatchTime.day,
      );

      String groupKey;
      if (watchDate == today || watchDate.isAfter(today)) {
        groupKey = '今天';
      } else if (watchDate == yesterday ||
          (watchDate.isAfter(yesterday) && watchDate.isBefore(today))) {
        groupKey = '昨天';
      } else if (watchDate.isAfter(weekAgo)) {
        groupKey = '最近7天';
      } else {
        groupKey =
            '${history.lastWatchTime.month}月${history.lastWatchTime.day}日';
      }

      grouped.putIfAbsent(groupKey, () => []);
      grouped[groupKey]!.add(history);
    }

    return grouped;
  }
}
