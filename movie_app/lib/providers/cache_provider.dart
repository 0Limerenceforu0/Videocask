import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../models/cache_episode_status.dart';
import '../models/cache_item.dart';
import '../services/cache_service.dart';

/// 缓存状态管理
class CacheProvider extends ChangeNotifier {
  final CacheService _cacheService = CacheService();

  /// 缓存项列表
  List<CacheItem> _cacheItems = [];

  /// 缓存项列表
  List<CacheItem> get cacheItems => _cacheItems;

  /// 正在下载的项
  List<CacheItem> get downloadingItems =>
      _cacheItems.where((i) => i.isDownloading).toList();

  /// 已完成的项
  List<CacheItem> get completedItems =>
      _cacheItems.where((i) => i.isCompleted).toList();

  /// 缓存总大小
  int _totalCacheSize = 0;

  /// 缓存总大小
  int get totalCacheSize => _totalCacheSize;

  /// 格式化的缓存总大小
  String get formattedTotalSize => CacheService.formatFileSize(_totalCacheSize);

  /// 缓存容量上限（格式化）
  String get formattedMaxCacheSize =>
      CacheService.formatFileSize(CacheService.maxCacheBytes);

  /// 已用空间占上限比例（0~1）
  double get storageUsageRatio {
    final max = CacheService.maxCacheBytes;
    if (max <= 0) return 0;
    return (_totalCacheSize / max).clamp(0.0, 1.0);
  }

  /// 是否正在加载
  bool _isLoading = false;

  /// 是否正在加载
  bool get isLoading => _isLoading;

  /// 初始化
  Future<void> init() async {
    _cacheService.cacheItemsChangedListener = _onCacheItemsChanged;
    await _cacheService.init();
    await loadCacheItems();
    await refreshTotalSize();
    await scheduleWaitingDownloads();
  }

  DateTime? _lastLiveRefreshAt;

  void _onCacheItemsChanged() {
    final now = DateTime.now();
    if (_lastLiveRefreshAt != null &&
        now.difference(_lastLiveRefreshAt!) <
            const Duration(milliseconds: 200)) {
      return;
    }
    _lastLiveRefreshAt = now;
    _cacheItems = _cacheService.getAllCacheItems();
    notifyListeners();
  }

  /// 加载缓存项
  Future<void> loadCacheItems() async {
    _isLoading = true;
    notifyListeners();

    _cacheItems = _cacheService.getAllCacheItems();
    _isLoading = false;
    notifyListeners();
  }

  /// 刷新缓存总大小
  Future<void> refreshTotalSize() async {
    _totalCacheSize = await _cacheService.getTotalCacheSize();
    notifyListeners();
  }

  /// 添加缓存任务
  Future<CacheItem> addCacheTask({
    required String movieId,
    required String movieName,
    required String movieCover,
    required int episodeIndex,
    required String episodeName,
    required String url,
    String pageUrl = '',
    String quality = '自动',
    String sourceId = '',
  }) async {
    final item = await _cacheService.addCacheTask(
      movieId: movieId,
      movieName: movieName,
      movieCover: movieCover,
      episodeIndex: episodeIndex,
      episodeName: episodeName,
      url: url,
      pageUrl: pageUrl,
      quality: quality,
      sourceId: sourceId,
    );

    _cacheItems.add(item);
    notifyListeners();
    return item;
  }

  /// 查找指定集数的最近缓存任务。
  CacheItem? findTaskForEpisode({
    required String movieId,
    required int episodeIndex,
    String sourceId = '',
  }) {
    return _cacheService.findTaskForEpisode(
      movieId: movieId,
      episodeIndex: episodeIndex,
      sourceId: sourceId,
    );
  }

  /// 本影片缓存任务（按创建时间倒序）。
  List<CacheItem> tasksForMovie({
    required String movieId,
    String sourceId = '',
  }) {
    final items = _cacheItems
        .where(
          (i) =>
              i.movieId == movieId &&
              (sourceId.isEmpty ||
                  i.sourceId.isEmpty ||
                  i.sourceId == sourceId),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// 当前集离线缓存状态（详情页展示）。
  CacheEpisodeStatus episodeCacheStatus({
    required String movieId,
    required int episodeIndex,
    String sourceId = '',
  }) {
    final task = findTaskForEpisode(
      movieId: movieId,
      episodeIndex: episodeIndex,
      sourceId: sourceId,
    );
    if (task == null) return CacheEpisodeStatus.none;
    if (task.isCompleted) return CacheEpisodeStatus.completed;
    if (task.isDownloading) return CacheEpisodeStatus.downloading;
    if (task.isWaiting) return CacheEpisodeStatus.waiting;
    if (task.isPaused || task.isFailed) return CacheEpisodeStatus.paused;
    return CacheEpisodeStatus.none;
  }

  /// 添加任务并调度 waiting 队列。
  Future<CacheItem> enqueueEpisodeDownload({
    required String movieId,
    required String movieName,
    required String movieCover,
    required int episodeIndex,
    required String episodeName,
    required String url,
    String pageUrl = '',
    String quality = '自动',
    String sourceId = '',
  }) async {
    final item = await addCacheTask(
      movieId: movieId,
      movieName: movieName,
      movieCover: movieCover,
      episodeIndex: episodeIndex,
      episodeName: episodeName,
      url: url,
      pageUrl: pageUrl,
      quality: quality,
      sourceId: sourceId,
    );
    await scheduleWaitingDownloads();
    return item;
  }

  /// 启动 waiting 队列中的下载任务。
  Future<void> scheduleWaitingDownloads() async {
    await _cacheService.scheduleWaitingDownloads();
    await loadCacheItems();
  }

  /// 开始下载
  Future<bool> startDownload(String cacheId) async {
    final success = await _cacheService.startDownload(cacheId);
    await loadCacheItems();
    return success;
  }

  /// 暂停下载
  void pauseDownload(String cacheId) {
    _cacheService.pauseDownload(cacheId);
    loadCacheItems();
  }

  /// 恢复下载
  Future<bool> resumeDownload(String cacheId) async {
    final success = await _cacheService.resumeDownload(cacheId);
    if (success) {
      await scheduleWaitingDownloads();
    } else {
      await loadCacheItems();
    }
    return success;
  }

  /// 删除缓存
  Future<void> deleteCache(String cacheId) async {
    await _cacheService.deleteCache(cacheId);
    await loadCacheItems();
    await refreshTotalSize();
  }

  /// 清理所有缓存
  Future<int> clearAllCache() async {
    final count = await _cacheService.clearAllCache();
    _cacheItems.clear();
    _totalCacheSize = 0;
    notifyListeners();
    return count;
  }

  /// 设置仅WiFi下载
  Future<void> setOnlyWifi(bool value) async {
    await _cacheService.setOnlyWifi(value);
    notifyListeners();
  }

  /// 是否仅WiFi下载
  bool get onlyWifi => _cacheService.onlyWifi;

  /// 正在下载的任务数
  int get activeDownloadCount => _cacheService.activeDownloadCount;

  /// 设置进度回调
  void setProgressCallback(
    String cacheId,
    void Function(int, int) callback,
  ) {
    _cacheService.setProgressCallback(cacheId, callback);
  }

  /// 移除进度回调
  void removeProgressCallback(String cacheId) {
    _cacheService.removeProgressCallback(cacheId);
  }

  /// 缓存数量
  int get count => _cacheItems.length;

  /// 已完成缓存数量
  int get completedCount => completedItems.length;

  /// 缓存容量上限 MB（与 [AppConstants.maxCacheSize] 一致）
  int get maxCacheSizeMb => AppConstants.maxCacheSize;
}
