import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../config/constants.dart';
import '../models/cache_item.dart';
import 'network/dio_factory.dart';
import 'storage_service.dart';

/// 缓存服务
class CacheService {
  CacheService._();
  static final CacheService _instance = CacheService._();
  factory CacheService() => _instance;

  final StorageService _storage = StorageService();
  Dio? _dio;

  /// 初始化Dio实例
  Future<Dio> _getDio() async {
    _dio ??= await DioFactory.plainText();
    return _dio!;
  }

  /// 缓存目录
  String? _cacheDir;

  /// 活跃下载任务
  final Map<String, CancelToken> _activeDownloads = {};

  /// 下载进度回调
  final Map<String, void Function(int, int)> _progressCallbacks = {};

  /// 连接状态订阅
  StreamSubscription<ConnectivityResult>? _connectivitySub;

  bool _onlyWifi = true;

  /// 是否仅 WiFi 下载
  bool get onlyWifi => _onlyWifi;

  /// 最大并发下载数
  static const int maxConcurrentDownloads = 3;

  /// 初始化
  Future<void> init() async {
    if (kIsWeb) {
      // Web端不支持文件缓存，跳过目录创建
      _onlyWifi = _storage.getBoolSetting(
        AppConstants.keyOnlyWifiCache,
        defaultValue: true,
      );
      return;
    }

    // 使用临时目录来存储缓存数据，避免权限问题
    final tempDir = await getTemporaryDirectory();
    _cacheDir = '${tempDir.path}/movie_app/cache';
    await Directory(_cacheDir!).create(recursive: true);

    _onlyWifi = _storage.getBoolSetting(
      AppConstants.keyOnlyWifiCache,
      defaultValue: true,
    );

    // 监听网络状态
    await _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (_onlyWifi && result != ConnectivityResult.wifi) {
        // 非WiFi环境下暂停所有下载
        pauseAllDownloads();
      }
    });
  }

  /// 获取缓存目录
  Future<String> getCacheDirectory() async {
    if (_cacheDir != null) return _cacheDir!;
    // 使用临时目录来存储缓存数据，避免权限问题
    final tempDir = await getTemporaryDirectory();
    _cacheDir = '${tempDir.path}/movie_app/cache';
    await Directory(_cacheDir!).create(recursive: true);
    return _cacheDir!;
  }

  /// 获取缓存总大小（字节）
  Future<int> getTotalCacheSize() async {
    final dir = Directory(await getCacheDirectory());
    int totalSize = 0;
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
    } catch (e) {
      debugPrint('计算缓存大小失败: $e');
    }
    return totalSize;
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
    final id =
        'cache_${movieId}_${episodeIndex}_${DateTime.now().millisecondsSinceEpoch}';
    final cacheDir = await getCacheDirectory();
    final fileName = '${movieId}_$episodeIndex.mp4';
    final localPath = '$cacheDir/$fileName';

    final item = CacheItem(
      id: id,
      movieId: movieId,
      sourceId: sourceId,
      movieName: movieName,
      movieCover: movieCover,
      episodeIndex: episodeIndex,
      episodeName: episodeName,
      url: url,
      quality: quality,
      localPath: localPath,
      status: 'waiting',
    );

    await _storage.saveCacheItem(item);
    return item;
  }

  /// 开始下载
  Future<bool> startDownload(String cacheId) async {
    // 防止重复下载
    if (_activeDownloads.containsKey(cacheId)) return true;

    // 检查并发数
    if (_activeDownloads.length >= maxConcurrentDownloads) {
      debugPrint('已达到最大并发下载数: $maxConcurrentDownloads');
      return false;
    }

    // 检查WiFi
    if (_onlyWifi) {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity != ConnectivityResult.wifi) {
        debugPrint('非WiFi环境，暂停下载');
        return false;
      }
    }

    // 获取缓存项
    final items = _storage.getAllCacheItems();
    final item = items.where((i) => i.id == cacheId).firstOrNull;
    if (item == null) return false;

    // 验证 URL 非空
    if (item.url.isEmpty) {
      debugPrint('下载失败: URL为空');
      await _storage.saveCacheItem(item.copyWith(status: 'failed'));
      return false;
    }

    // 根据URL类型选择下载方式
    if (item.url.contains('.m3u8')) {
      return _downloadM3u8(cacheId, item);
    } else {
      return _downloadDirect(cacheId, item);
    }
  }

  /// 直链文件下载
  Future<bool> _downloadDirect(
    String cacheId,
    CacheItem item, {
    int resumeFrom = 0,
  }) async {
    // 创建目录
    final dir =
        Directory(item.localPath.substring(0, item.localPath.lastIndexOf('/')));
    await dir.create(recursive: true);

    // 创建取消令牌
    final cancelToken = CancelToken();
    _activeDownloads[cacheId] = cancelToken;

    // 更新状态
    await _storage.saveCacheItem(item.copyWith(status: 'downloading'));

    // 记录下载开始时间，用于计算速度
    final startTime = DateTime.now();

    try {
      final dio = await _getDio();
      final options = Options(
        responseType: ResponseType.bytes,
        headers: resumeFrom > 0 ? {'Range': 'bytes=$resumeFrom-'} : null,
      );

      await dio.download(
        item.url,
        item.localPath,
        cancelToken: cancelToken,
        options: options,
        onReceiveProgress: (received, total) {
          final actualReceived = resumeFrom + received;
          final actualTotal =
              resumeFrom > 0 && total > 0 ? resumeFrom + total : total;
          if (actualTotal > 0) {
            final elapsedSeconds =
                DateTime.now().difference(startTime).inSeconds + 1;
            // 更新进度
            _storage.saveCacheItem(
              item.copyWith(
                downloadedSize: actualReceived,
                fileSize: actualTotal,
                speed: received ~/ elapsedSeconds,
              ),
            );

            // 回调进度
            final callback = _progressCallbacks[cacheId];
            if (callback != null) {
              callback(actualReceived, actualTotal);
            }
          }
        },
      );

      // 下载完成
      final file = File(item.localPath);
      final fileSize = await file.length();
      await _storage.saveCacheItem(
        item.copyWith(
          status: 'completed',
          fileSize: fileSize,
          downloadedSize: fileSize,
          completedAt: DateTime.now(),
        ),
      );

      _activeDownloads.remove(cacheId);
      _progressCallbacks.remove(cacheId);
      return true;
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        // 用户取消
        await _storage.saveCacheItem(item.copyWith(status: 'paused'));
      } else {
        // 下载失败
        await _storage.saveCacheItem(item.copyWith(status: 'failed'));
        debugPrint('下载失败: $e');
      }
      _activeDownloads.remove(cacheId);
      _progressCallbacks.remove(cacheId);
      return false;
    }
  }

  /// m3u8分片下载
  Future<bool> _downloadM3u8(
    String cacheId,
    CacheItem item, {
    bool startFrom = false,
  }) async {
    // 创建目录
    final dir =
        Directory(item.localPath.substring(0, item.localPath.lastIndexOf('/')));
    await dir.create(recursive: true);

    // 创建取消令牌
    final cancelToken = CancelToken();
    _activeDownloads[cacheId] = cancelToken;

    // 更新状态
    await _storage.saveCacheItem(item.copyWith(status: 'downloading'));

    try {
      final dio = await _getDio();
      // 1. 下载m3u8文件内容
      final m3u8Content = await dio
          .get(
            item.url,
            options: Options(responseType: ResponseType.plain),
          )
          .then((r) => r.data.toString());

      // 2. 解析ts分片URL列表
      final tsUrls = _parseM3u8(m3u8Content, item.url);
      if (tsUrls.isEmpty) {
        await _storage.saveCacheItem(item.copyWith(status: 'failed'));
        _activeDownloads.remove(cacheId);
        _progressCallbacks.remove(cacheId);
        return false;
      }

      // 3. 创建临时目录
      final tempDir = '${item.localPath}_temp';
      await Directory(tempDir).create(recursive: true);

      // 4. 确定起始分片索引
      int startSegment = 0;
      if (startFrom) {
        // 按顺序检查每个分片是否存在，从第一个缺失的分片开始下载
        for (int i = 0; i < tsUrls.length; i++) {
          final tsPath = '$tempDir/segment_$i.ts';
          if (!await File(tsPath).exists()) {
            startSegment = i;
            break;
          }
          // 所有分片都存在，无需下载
          if (i == tsUrls.length - 1) {
            startSegment = tsUrls.length;
          }
        }
      }

      // 5. 逐个下载ts分片
      for (int i = startSegment; i < tsUrls.length; i++) {
        if (cancelToken.isCancelled) break;

        final tsPath = '$tempDir/segment_$i.ts';
        await dio.download(
          tsUrls[i],
          tsPath,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            // 计算总体进度
            final segmentProgress = total > 0 ? received / total : 0;
            final totalProgress = (i + segmentProgress) / tsUrls.length;
            final callback = _progressCallbacks[cacheId];
            if (callback != null) {
              callback((totalProgress * 100).toInt(), 100);
            }
          },
        );
      }

      // 检查是否被取消
      if (cancelToken.isCancelled) {
        await _storage.saveCacheItem(item.copyWith(status: 'paused'));
        _activeDownloads.remove(cacheId);
        _progressCallbacks.remove(cacheId);
        return false;
      }

      // 6. 合并ts为mp4（直接拼接文件）
      final outFile = File(item.localPath);
      final sink = outFile.openWrite();
      for (int i = 0; i < tsUrls.length; i++) {
        final tsFile = File('$tempDir/segment_$i.ts');
        if (await tsFile.exists()) {
          final bytes = await tsFile.readAsBytes();
          sink.add(bytes);
        }
      }
      await sink.close();

      // 7. 清理临时文件
      await Directory(tempDir).delete(recursive: true);

      // 8. 更新状态
      final fileSize = await outFile.length();
      await _storage.saveCacheItem(
        item.copyWith(
          status: 'completed',
          fileSize: fileSize,
          downloadedSize: fileSize,
          completedAt: DateTime.now(),
        ),
      );

      _activeDownloads.remove(cacheId);
      _progressCallbacks.remove(cacheId);
      return true;
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        await _storage.saveCacheItem(item.copyWith(status: 'paused'));
      } else {
        await _storage.saveCacheItem(item.copyWith(status: 'failed'));
        debugPrint('m3u8下载失败: $e');
      }
      _activeDownloads.remove(cacheId);
      _progressCallbacks.remove(cacheId);
      return false;
    }
  }

  /// 解析m3u8文件内容，提取ts分片URL列表
  List<String> _parseM3u8(String content, String baseUrl) {
    final lines = content.split('\n');
    final tsUrls = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      // 处理相对路径和绝对路径
      if (trimmed.startsWith('http')) {
        tsUrls.add(trimmed);
      } else {
        final baseUri = Uri.parse(baseUrl);
        tsUrls.add(baseUri.resolve(trimmed).toString());
      }
    }
    return tsUrls;
  }

  /// 暂停下载
  void pauseDownload(String cacheId) {
    final cancelToken = _activeDownloads[cacheId];
    if (cancelToken != null) {
      cancelToken.cancel('用户暂停');
      _activeDownloads.remove(cacheId);
    }
  }

  /// 暂停所有下载
  void pauseAllDownloads() {
    for (final id in _activeDownloads.keys.toList()) {
      pauseDownload(id);
    }
  }

  /// 恢复下载（支持断点续传）
  Future<bool> resumeDownload(String cacheId) async {
    // 防止重复下载
    if (_activeDownloads.containsKey(cacheId)) return true;

    // 检查并发数
    if (_activeDownloads.length >= maxConcurrentDownloads) {
      debugPrint('已达到最大并发下载数: $maxConcurrentDownloads');
      return false;
    }

    // 检查WiFi
    if (_onlyWifi) {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity != ConnectivityResult.wifi) {
        debugPrint('非WiFi环境，暂停下载');
        return false;
      }
    }

    // 获取缓存项
    final items = _storage.getAllCacheItems();
    final item = items.where((i) => i.id == cacheId).firstOrNull;
    if (item == null) return false;

    // 验证 URL 非空
    if (item.url.isEmpty) {
      debugPrint('下载失败: URL为空');
      await _storage.saveCacheItem(item.copyWith(status: 'failed'));
      return false;
    }

    if (item.url.contains('.m3u8')) {
      // m3u8：检查已下载的分片，跳过已完成的
      return _downloadM3u8(cacheId, item, startFrom: true);
    } else {
      // 直链：使用Range header续传
      return _downloadDirect(cacheId, item, resumeFrom: item.downloadedSize);
    }
  }

  /// 删除缓存
  Future<bool> deleteCache(String cacheId) async {
    // 暂停下载
    pauseDownload(cacheId);

    // 删除文件
    final items = _storage.getAllCacheItems();
    final item = items.where((i) => i.id == cacheId).firstOrNull;
    if (item != null && item.localPath.isNotEmpty) {
      try {
        final file = File(item.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('删除缓存文件失败: $e');
      }
    }

    // 删除记录
    await _storage.deleteCacheItem(cacheId);
    return true;
  }

  /// 清理所有缓存
  Future<int> clearAllCache() async {
    pauseAllDownloads();

    int deletedCount = 0;
    final items = _storage.getAllCacheItems();

    for (final item in items) {
      try {
        if (item.localPath.isNotEmpty) {
          final file = File(item.localPath);
          if (await file.exists()) {
            await file.delete();
          }
        }
        deletedCount++;
      } catch (e) {
        debugPrint('删除缓存文件失败: $e');
      }
    }

    await _storage.clearCacheItems();
    return deletedCount;
  }

  /// 设置进度回调
  void setProgressCallback(String cacheId, void Function(int, int) callback) {
    _progressCallbacks[cacheId] = callback;
  }

  /// 移除进度回调
  void removeProgressCallback(String cacheId) {
    _progressCallbacks.remove(cacheId);
  }

  /// 设置仅WiFi下载
  Future<void> setOnlyWifi(bool value) async {
    _onlyWifi = value;
    await _storage.saveBoolSetting(AppConstants.keyOnlyWifiCache, value);
  }

  /// 获取所有缓存项
  List<CacheItem> getAllCacheItems() {
    return _storage.getAllCacheItems();
  }

  /// 获取正在下载的任务数
  int get activeDownloadCount => _activeDownloads.length;

  /// 格式化文件大小
  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int unitIndex = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }
}
