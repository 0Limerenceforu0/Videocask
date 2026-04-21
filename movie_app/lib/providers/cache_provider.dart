import 'package:flutter/material.dart';
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

  /// 是否正在加载
  bool _isLoading = false;

  /// 是否正在加载
  bool get isLoading => _isLoading;

  /// 初始化
  Future<void> init() async {
    await _cacheService.init();
    await loadCacheItems();
    await refreshTotalSize();
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
      quality: quality,
      sourceId: sourceId,
    );

    _cacheItems.add(item);
    notifyListeners();
    return item;
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
    await loadCacheItems();
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
}
