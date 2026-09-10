import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/constants.dart';
import '../models/play_source.dart';
import '../models/watch_history.dart';
import '../models/favorite.dart';
import 'storage_service.dart';
import 'webdav_service.dart';

/// 同步结果
class SyncResult {
  final bool success;
  final String message;
  final DateTime syncTime;
  final int uploadedCount;
  final int downloadedCount;
  final int conflictCount;

  SyncResult({
    required this.success,
    required this.message,
    required this.syncTime,
    this.uploadedCount = 0,
    this.downloadedCount = 0,
    this.conflictCount = 0,
  });
}

/// 数据同步引擎
class SyncService {
  SyncService._();
  static final SyncService _instance = SyncService._();
  factory SyncService() => _instance;

  final StorageService _storage = StorageService();
  final WebDavService _webdav = WebDavService();

  /// 是否正在同步
  bool _isSyncing = false;

  /// 是否正在同步
  bool get isSyncing => _isSyncing;

  /// 上次同步时间
  DateTime? _lastSyncTime;

  /// 获取上次同步时间
  DateTime? get lastSyncTime => _lastSyncTime;

  /// 同步冲突解决策略
  String _conflictStrategy = 'local_win'; // local_win, remote_win, newest_win

  /// 设置冲突解决策略
  void setConflictStrategy(String strategy) {
    _conflictStrategy = strategy;
  }

  /// 初始化同步服务
  Future<void> init() async {
    // 从本地存储加载上次同步时间
    final lastSyncStr = _storage.getSetting(AppConstants.keyLastSyncTime);
    if (lastSyncStr != null) {
      _lastSyncTime = DateTime.tryParse(lastSyncStr);
    }

    // 尝试自动连接WebDAV
    final configStr = _storage.getSetting(AppConstants.keyWebdavConfig);
    if (configStr != null) {
      try {
        final config = WebDavConfig.fromJson(
          jsonDecode(configStr) as Map<String, dynamic>,
        );
        if (config.isValid) {
          await _webdav.connect(config);
        }
      } catch (e) {
        debugPrint('自动连接WebDAV失败: $e');
      }
    }
  }

  /// 配置WebDAV
  Future<bool> configureWebDav(WebDavConfig config) async {
    final success = await _webdav.connect(config);
    if (success) {
      await _storage.saveSetting(
        AppConstants.keyWebdavConfig,
        jsonEncode(config.toJson()),
      );
    }
    return success;
  }

  /// 断开WebDAV连接
  void disconnectWebDav() {
    _webdav.disconnect();
    _storage.saveSetting(AppConstants.keyWebdavConfig, '');
  }

  /// 获取WebDAV配置
  WebDavConfig? getWebDavConfig() {
    final configStr = _storage.getSetting(AppConstants.keyWebdavConfig);
    if (configStr == null) return null;
    try {
      return WebDavConfig.fromJson(
        jsonDecode(configStr) as Map<String, dynamic>,
      );
    } catch (e) {
      return null;
    }
  }

  /// 执行全量同步（上传）
  Future<SyncResult> uploadAll() async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: '正在同步中，请稍后',
        syncTime: DateTime.now(),
      );
    }

    if (!_webdav.isConnected) {
      return SyncResult(
        success: false,
        message: 'WebDAV未连接',
        syncTime: DateTime.now(),
      );
    }

    _isSyncing = true;
    try {
      // 收集所有本地数据
      final syncData = <String, dynamic>{
        'version': AppConstants.appVersion,
        'syncTime': DateTime.now().toIso8601String(),
        'sources': _storage.getAllSources().map((e) => e.toJson()).toList(),
        'favorites': _storage.getAllFavorites().map((e) => e.toJson()).toList(),
        'history': _storage.getAllHistory().map((e) => e.toJson()).toList(),
        'settings': _exportSettings(),
      };

      // 上传到WebDAV
      final success = await _webdav.uploadSyncData(syncData);

      if (success) {
        _lastSyncTime = DateTime.now();
        await _storage.saveSetting(
          AppConstants.keyLastSyncTime,
          _lastSyncTime!.toIso8601String(),
        );
      }

      return SyncResult(
        success: success,
        message: success ? '上传成功' : '上传失败',
        syncTime: DateTime.now(),
        uploadedCount: success
            ? (syncData['sources'] as List).length +
                (syncData['favorites'] as List).length +
                (syncData['history'] as List).length
            : 0,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: '同步失败: $e',
        syncTime: DateTime.now(),
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// 执行全量同步（下载）
  Future<SyncResult> downloadAll() async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: '正在同步中，请稍后',
        syncTime: DateTime.now(),
      );
    }

    if (!_webdav.isConnected) {
      return SyncResult(
        success: false,
        message: 'WebDAV未连接',
        syncTime: DateTime.now(),
      );
    }

    _isSyncing = true;
    try {
      // 从WebDAV下载数据
      final remoteData = await _webdav.downloadSyncData();
      if (remoteData == null) {
        return SyncResult(
          success: false,
          message: '远程没有同步数据',
          syncTime: DateTime.now(),
        );
      }

      int downloadedCount = 0;
      int conflictCount = 0;

      // 合并播放源
      if (remoteData['sources'] != null) {
        final remoteSources = (remoteData['sources'] as List)
            .map((e) => PlaySource.fromJson(e as Map<String, dynamic>))
            .toList();
        final localSources = _storage.getAllSources();

        for (final remote in remoteSources) {
          final localIndex = localSources.indexWhere((l) => l.id == remote.id);
          if (localIndex >= 0) {
            // 冲突处理
            conflictCount++;
            if (_conflictStrategy == 'remote_win') {
              await _storage.saveSource(remote);
            }
          } else {
            await _storage.saveSource(remote);
            downloadedCount++;
          }
        }
      }

      // 合并收藏
      if (remoteData['favorites'] != null) {
        final remoteFavs = (remoteData['favorites'] as List)
            .map((e) => Favorite.fromJson(e as Map<String, dynamic>))
            .toList();
        final localFavs = _storage.getAllFavorites();

        for (final remote in remoteFavs) {
          final localIndex = localFavs.indexWhere(
            (l) => l.movieId == remote.movieId && l.sourceId == remote.sourceId,
          );
          if (localIndex < 0) {
            await _storage.saveFavorite(remote);
            downloadedCount++;
          }
        }
      }

      // 合并观看历史（取最新进度）
      if (remoteData['history'] != null) {
        final remoteHistory = (remoteData['history'] as List)
            .map((e) => WatchHistory.fromJson(e as Map<String, dynamic>))
            .toList();

        for (final remote in remoteHistory) {
          final local = _storage.getHistory(
            remote.movieId,
            sourceId: remote.sourceId,
          );
          if (local == null) {
            await _storage.saveHistory(remote);
            downloadedCount++;
          } else if (_conflictStrategy == 'newest_win') {
            if (remote.lastWatchTime.isAfter(local.lastWatchTime)) {
              await _storage.saveHistory(remote);
              conflictCount++;
            }
          } else if (_conflictStrategy == 'remote_win') {
            await _storage.saveHistory(remote);
            conflictCount++;
          }
        }
      }

      // 合并设置
      if (remoteData['settings'] != null) {
        await _importSettings(remoteData['settings'] as Map<String, dynamic>);
      }

      _lastSyncTime = DateTime.now();
      await _storage.saveSetting(
        AppConstants.keyLastSyncTime,
        _lastSyncTime!.toIso8601String(),
      );

      return SyncResult(
        success: true,
        message: '下载成功',
        syncTime: DateTime.now(),
        downloadedCount: downloadedCount,
        conflictCount: conflictCount,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: '同步失败: $e',
        syncTime: DateTime.now(),
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// 双向同步
  Future<SyncResult> syncBoth() async {
    // 先上传，再下载
    final uploadResult = await uploadAll();
    if (!uploadResult.success) return uploadResult;
    return downloadAll();
  }

  /// 导出设置
  Map<String, dynamic> _exportSettings() {
    return {
      'themeIndex': _storage.getIntSetting(AppConstants.keyThemeIndex),
      'defaultSpeed': _storage.getDoubleSetting(
        AppConstants.keyDefaultSpeed,
        defaultValue: 1.0,
      ),
      'defaultQuality':
          _storage.getSetting(AppConstants.keyDefaultQuality) ?? '自动',
      'hardwareDecode': _storage.getBoolSetting(AppConstants.keyHardwareDecode),
      'autoPlayNext': _storage.getBoolSetting(
        AppConstants.keyAutoPlayNext,
        defaultValue: true,
      ),
      'autoPlayOnDetailEnter': _storage.getBoolSetting(
        AppConstants.keyAutoPlayOnDetailEnter,
        defaultValue: true,
      ),
      'onlyWifiCache': _storage.getBoolSetting(
        AppConstants.keyOnlyWifiCache,
        defaultValue: true,
      ),
      'playbackStrategy':
          _storage.getSetting(AppConstants.keyPlaybackStrategy) ?? 'balanced',
      'preloadNextEpisode': _storage.getBoolSetting(
        AppConstants.keyPreloadNextEpisode,
        defaultValue: true,
      ),
      'playbackPrefetch': _storage.getSetting(
                AppConstants.keyPlaybackPrefetch,
              ) !=
              null
          ? _storage.getBoolSetting(
              AppConstants.keyPlaybackPrefetch,
              defaultValue: true,
            )
          : _storage.getBoolSetting(
              AppConstants.keyWifiPlaybackPrefetch,
              defaultValue: true,
            ),
    };
  }

  /// 导入设置
  Future<void> _importSettings(Map<String, dynamic> settings) async {
    if (settings['themeIndex'] != null) {
      await _storage.saveIntSetting(
        AppConstants.keyThemeIndex,
        settings['themeIndex'] as int,
      );
    }
    if (settings['defaultSpeed'] != null) {
      await _storage.saveDoubleSetting(
        AppConstants.keyDefaultSpeed,
        (settings['defaultSpeed'] as num).toDouble(),
      );
    }
    if (settings['defaultQuality'] != null) {
      await _storage.saveSetting(
        AppConstants.keyDefaultQuality,
        settings['defaultQuality'] as String,
      );
    }
    if (settings['hardwareDecode'] != null) {
      await _storage.saveBoolSetting(
        AppConstants.keyHardwareDecode,
        settings['hardwareDecode'] as bool,
      );
    }
    if (settings['autoPlayNext'] != null) {
      await _storage.saveBoolSetting(
        AppConstants.keyAutoPlayNext,
        settings['autoPlayNext'] as bool,
      );
    }
    if (settings['autoPlayOnDetailEnter'] != null) {
      await _storage.saveBoolSetting(
        AppConstants.keyAutoPlayOnDetailEnter,
        settings['autoPlayOnDetailEnter'] as bool,
      );
    }
    if (settings['onlyWifiCache'] != null) {
      await _storage.saveBoolSetting(
        AppConstants.keyOnlyWifiCache,
        settings['onlyWifiCache'] as bool,
      );
    }
    if (settings['playbackStrategy'] != null) {
      await _storage.saveSetting(
        AppConstants.keyPlaybackStrategy,
        settings['playbackStrategy'] as String,
      );
    }
    if (settings['preloadNextEpisode'] != null) {
      await _storage.saveBoolSetting(
        AppConstants.keyPreloadNextEpisode,
        settings['preloadNextEpisode'] as bool,
      );
    }
    if (settings['playbackPrefetch'] != null) {
      await _storage.saveBoolSetting(
        AppConstants.keyPlaybackPrefetch,
        settings['playbackPrefetch'] as bool,
      );
    } else if (settings['wifiPlaybackPrefetch'] != null) {
      await _storage.saveBoolSetting(
        AppConstants.keyPlaybackPrefetch,
        settings['wifiPlaybackPrefetch'] as bool,
      );
    }
  }

  /// 清除同步状态
  Future<void> clearSyncState() async {
    _lastSyncTime = null;
    await _storage.saveSetting(AppConstants.keyLastSyncTime, '');
  }
}
