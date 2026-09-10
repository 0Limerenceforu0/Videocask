import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/magnet_source_catalog.dart';
import '../models/magnet_source_config.dart';
import '../services/storage_service.dart';
import '../services/cache_service.dart';
import '../services/subtitle_service.dart';
import '../services/sync_service.dart';
import '../services/webdav_service.dart';

/// 设置状态管理
class SettingsProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final SyncService _syncService = SyncService();

  /// 默认播放速度
  double _defaultSpeed = 1.0;

  /// 默认播放速度
  double get defaultSpeed => _defaultSpeed;

  /// 默认清晰度
  String _defaultQuality = '自动';

  /// 默认清晰度
  String get defaultQuality => _defaultQuality;

  /// 硬件解码
  bool _hardwareDecode = true;

  /// 硬件解码
  bool get hardwareDecode => _hardwareDecode;

  /// 自动连播
  bool _autoPlayNext = true;

  /// 自动连播
  bool get autoPlayNext => _autoPlayNext;

  /// 进入详情页自动播放
  bool _autoPlayOnDetailEnter = true;

  bool get autoPlayOnDetailEnter => _autoPlayOnDetailEnter;

  /// 播放策略：smooth / balanced / quality
  String _playbackStrategy = 'balanced';

  /// 播放策略
  String get playbackStrategy => _playbackStrategy;

  /// 播放到 80% 时预解析下一集
  bool _preloadNextEpisode = true;

  bool get preloadNextEpisode => _preloadNextEpisode;

  /// 预拉下一集前几 MB（全网络，可关）
  bool _playbackPrefetch = true;

  bool get playbackPrefetch => _playbackPrefetch;

  /// 仅WiFi缓存
  bool _onlyWifiCache = false;

  /// 仅WiFi缓存
  bool get onlyWifiCache => _onlyWifiCache;

  /// WebDAV是否已连接
  bool _webdavConnected = false;

  /// WebDAV是否已连接
  bool get webdavConnected => _webdavConnected;

  /// WebDAV配置
  WebDavConfig? _webdavConfig;

  /// WebDAV配置
  WebDavConfig? get webdavConfig => _webdavConfig;

  /// 上次同步时间
  DateTime? _lastSyncTime;

  /// 上次同步时间
  DateTime? get lastSyncTime => _lastSyncTime;

  /// 是否正在同步
  bool _isSyncing = false;

  /// 是否正在同步
  bool get isSyncing => _isSyncing;

  /// 冲突解决策略
  String _conflictStrategy = 'local_win';

  /// 冲突解决策略
  String get conflictStrategy => _conflictStrategy;

  /// OpenSubtitles API Key（存于 Hive settings）
  String _opensubtitlesApiKey = '';

  String get opensubtitlesApiKey => _opensubtitlesApiKey;

  bool get opensubtitlesApiKeyConfigured =>
      _opensubtitlesApiKey.trim().isNotEmpty;

  /// TMDB API Key（中文片名解析为 IMDb / 英文名，提升磁力命中率）
  String _tmdbApiKey = '';

  String get tmdbApiKey => _tmdbApiKey;

  bool get tmdbApiKeyConfigured => _tmdbApiKey.trim().isNotEmpty;

  /// 磁力搜索源（含内置与自定义）
  List<MagnetSourceConfig> _magnetSources = [];

  List<MagnetSourceConfig> get magnetSources =>
      List.unmodifiable(_magnetSources);

  int get enabledMagnetSourceCount =>
      _magnetSources.where((c) => c.enabled).length;

  void _loadMagnetSources() {
    final raw = _storage.getSetting(AppConstants.keyMagnetSources);
    if (raw == null || raw.isEmpty) {
      _magnetSources = List.from(MagnetSourceCatalog.builtInDefaults);
      return;
    }
    try {
      _magnetSources = MagnetSourceCatalog.decodeList(raw);
      if (_magnetSources.isEmpty) {
        _magnetSources = List.from(MagnetSourceCatalog.builtInDefaults);
      }
    } catch (_) {
      _magnetSources = List.from(MagnetSourceCatalog.builtInDefaults);
    }
  }

  Future<void> _persistMagnetSources() async {
    await _storage.saveSetting(
      AppConstants.keyMagnetSources,
      MagnetSourceCatalog.encodeList(_magnetSources),
    );
    notifyListeners();
  }

  Future<void> setMagnetSourceEnabled(String id, bool enabled) async {
    final i = _magnetSources.indexWhere((c) => c.id == id);
    if (i < 0) return;
    _magnetSources[i] = _magnetSources[i].copyWith(enabled: enabled);
    await _persistMagnetSources();
  }

  Future<void> resetMagnetSourcesToDefaults() async {
    _magnetSources = List.from(MagnetSourceCatalog.builtInDefaults);
    await _persistMagnetSources();
  }

  Future<void> addCustomMagnetSource(MagnetSourceConfig config) async {
    _magnetSources.add(config);
    await _persistMagnetSources();
  }

  Future<void> removeMagnetSource(String id) async {
    _magnetSources.removeWhere((c) => c.id == id && !c.isBuiltin);
    await _persistMagnetSources();
  }

  /// 初始化
  Future<void> init() async {
    _defaultSpeed = _storage.getDoubleSetting(
      AppConstants.keyDefaultSpeed,
      defaultValue: 1.0,
    );
    _defaultQuality =
        _storage.getSetting(AppConstants.keyDefaultQuality) ?? '自动';
    _hardwareDecode = _storage.getBoolSetting(
      AppConstants.keyHardwareDecode,
      defaultValue: true,
    );
    _autoPlayNext = _storage.getBoolSetting(
      AppConstants.keyAutoPlayNext,
      defaultValue: true,
    );
    _autoPlayOnDetailEnter = _storage.getBoolSetting(
      AppConstants.keyAutoPlayOnDetailEnter,
      defaultValue: true,
    );
    _onlyWifiCache = _storage.getBoolSetting(
      AppConstants.keyOnlyWifiCache,
      defaultValue: false,
    );
    _playbackStrategy =
        _storage.getSetting(AppConstants.keyPlaybackStrategy) ?? 'balanced';
    _preloadNextEpisode = _storage.getBoolSetting(
      AppConstants.keyPreloadNextEpisode,
      defaultValue: true,
    );
    _playbackPrefetch = _loadPlaybackPrefetchSetting();
    _opensubtitlesApiKey =
        _storage.getSetting(AppConstants.keyOpensubtitlesApiKey) ?? '';
    _tmdbApiKey = _storage.getSetting(AppConstants.keyTmdbApiKey) ?? '';

    // 初始化同步服务
    await _syncService.init();
    _webdavConfig = _syncService.getWebDavConfig();
    _webdavConnected = _webdavConfig != null && _webdavConfig!.isValid;
    _lastSyncTime = _syncService.lastSyncTime;

    _loadMagnetSources();

    notifyListeners();
  }

  /// 设置默认播放速度
  Future<void> setDefaultSpeed(double speed) async {
    _defaultSpeed = speed;
    await _storage.saveDoubleSetting(AppConstants.keyDefaultSpeed, speed);
    notifyListeners();
  }

  /// 设置默认清晰度
  Future<void> setDefaultQuality(String quality) async {
    _defaultQuality = quality;
    await _storage.saveSetting(AppConstants.keyDefaultQuality, quality);
    notifyListeners();
  }

  /// 设置硬件解码
  Future<void> setHardwareDecode(bool value) async {
    _hardwareDecode = value;
    await _storage.saveBoolSetting(AppConstants.keyHardwareDecode, value);
    notifyListeners();
  }

  /// 设置自动连播
  Future<void> setAutoPlayNext(bool value) async {
    _autoPlayNext = value;
    await _storage.saveBoolSetting(AppConstants.keyAutoPlayNext, value);
    notifyListeners();
  }

  /// 设置进入详情页自动播放
  Future<void> setAutoPlayOnDetailEnter(bool value) async {
    _autoPlayOnDetailEnter = value;
    await _storage.saveBoolSetting(
      AppConstants.keyAutoPlayOnDetailEnter,
      value,
    );
    notifyListeners();
  }

  /// 设置播放策略
  Future<void> setPlaybackStrategy(String strategy) async {
    const allowed = {'smooth', 'balanced', 'quality'};
    _playbackStrategy = allowed.contains(strategy) ? strategy : 'balanced';
    await _storage.saveSetting(
      AppConstants.keyPlaybackStrategy,
      _playbackStrategy,
    );
    notifyListeners();
  }

  Future<void> setPreloadNextEpisode(bool value) async {
    _preloadNextEpisode = value;
    await _storage.saveBoolSetting(AppConstants.keyPreloadNextEpisode, value);
    notifyListeners();
  }

  Future<void> setPlaybackPrefetch(bool value) async {
    _playbackPrefetch = value;
    await _storage.saveBoolSetting(AppConstants.keyPlaybackPrefetch, value);
    notifyListeners();
  }

  bool _loadPlaybackPrefetchSetting() {
    if (_storage.getSetting(AppConstants.keyPlaybackPrefetch) != null) {
      return _storage.getBoolSetting(
        AppConstants.keyPlaybackPrefetch,
        defaultValue: true,
      );
    }
    return _storage.getBoolSetting(
      AppConstants.keyWifiPlaybackPrefetch,
      defaultValue: true,
    );
  }

  /// 设置仅WiFi缓存
  Future<void> setOnlyWifiCache(bool value) async {
    _onlyWifiCache = value;
    await _storage.saveBoolSetting(AppConstants.keyOnlyWifiCache, value);
    await CacheService().setOnlyWifi(value);
    notifyListeners();
  }

  /// OpenSubtitles API Key（留空则关闭在线字幕搜索）
  Future<void> setOpensubtitlesApiKey(String value) async {
    _opensubtitlesApiKey = value.trim();
    await _storage.saveSetting(
      AppConstants.keyOpensubtitlesApiKey,
      _opensubtitlesApiKey,
    );
    SubtitleService().invalidateAuth();
    notifyListeners();
  }

  /// TMDB API Key（留空则仅用豆瓣 + IMDb 解析中文片名）
  Future<void> setTmdbApiKey(String value) async {
    _tmdbApiKey = value.trim();
    await _storage.saveSetting(AppConstants.keyTmdbApiKey, _tmdbApiKey);
    notifyListeners();
  }

  /// 配置WebDAV
  Future<bool> configureWebDav({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
    required String presetName,
  }) async {
    final config = WebDavConfig(
      serverUrl: serverUrl,
      username: username,
      password: password,
      remotePath: remotePath,
      presetName: presetName,
    );

    final success = await _syncService.configureWebDav(config);
    if (success) {
      _webdavConfig = config;
      _webdavConnected = true;
      notifyListeners();
    }
    return success;
  }

  /// 断开WebDAV
  void disconnectWebDav() {
    _syncService.disconnectWebDav();
    _webdavConfig = null;
    _webdavConnected = false;
    _lastSyncTime = null;
    notifyListeners();
  }

  /// 设置冲突解决策略
  void setConflictStrategy(String strategy) {
    _conflictStrategy = strategy;
    _syncService.setConflictStrategy(strategy);
    notifyListeners();
  }

  /// 上传同步
  Future<String> uploadSync() async {
    _isSyncing = true;
    notifyListeners();

    final result = await _syncService.uploadAll();
    _isSyncing = false;

    if (result.success) {
      _lastSyncTime = result.syncTime;
    }

    notifyListeners();
    return result.message;
  }

  /// 下载同步
  Future<String> downloadSync() async {
    _isSyncing = true;
    notifyListeners();

    final result = await _syncService.downloadAll();
    _isSyncing = false;

    if (result.success) {
      _lastSyncTime = result.syncTime;
    }

    notifyListeners();
    return result.message;
  }

  /// 双向同步
  Future<String> syncBoth() async {
    _isSyncing = true;
    notifyListeners();

    final result = await _syncService.syncBoth();
    _isSyncing = false;

    if (result.success) {
      _lastSyncTime = result.syncTime;
    }

    notifyListeners();
    return result.message;
  }

  /// 导出数据
  Future<String> exportData() async {
    return _storage.exportAllData();
  }

  /// 导入数据
  Future<bool> importData(String jsonStr) async {
    final success = await _storage.importData(jsonStr);
    notifyListeners();
    return success;
  }

  /// 获取速度选项
  List<double> get speedOptions => AppConstants.speedOptions;

  /// 获取清晰度选项
  List<String> get qualityOptions => AppConstants.qualityOptions;

  /// 获取WebDAV预置服务商
  List<Map<String, String>> get webdavPresets => AppConstants.webdavPresets;
}
