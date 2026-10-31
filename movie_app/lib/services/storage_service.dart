import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_env.dart';
import '../config/constants.dart';
import '../models/play_source.dart';
import '../models/user.dart';
import '../models/watch_history.dart';
import '../models/favorite.dart';
import '../models/cache_item.dart';
import '../models/playlist.dart';
import 'subtitle_ai_backend.dart' show SubtitleAiBackendKind;

/// 本地存储服务 - 基于Hive
class StorageService {
  StorageService._();
  static final StorageService _instance = StorageService._();
  factory StorageService() => _instance;

  /// 各类型Box缓存
  Box<String>? _historyBox;
  Box<String>? _favoriteBox;
  Box<String>? _cacheBox;
  Box<String>? _settingsBox;
  Box<String>? _sourceBox;
  Box<String>? _userBox;
  Box<String>? _playlistBox;

  /// 是否已初始化
  bool _initialized = false;

  /// 初始化Hive
  Future<void> init() async {
    if (_initialized) return;

    if (kIsWeb) {
      // Web 平台：Hive 后端为 IndexedDB，无需文件系统路径。
      // path_provider 不支持 Web（会抛 MissingPluginException），必须跳过。
      Hive.init(null);
      debugPrint('Hive 已初始化（Web / IndexedDB）');
    } else {
      // 使用临时目录来存储Hive数据，避免权限问题
      final tempDir = await getTemporaryDirectory();
      final hiveDir = '${tempDir.path}/movie_app/hive';
      debugPrint('Hive存储目录: $hiveDir');

      try {
        await Directory(hiveDir).create(recursive: true);
        debugPrint('成功创建Hive存储目录');
      } catch (e) {
        debugPrint('创建Hive存储目录失败: $e');
      }

      try {
        // 使用Hive.init方法而不是initFlutter方法，这样可以更直接地控制存储目录
        Hive.init(hiveDir);
        debugPrint('成功初始化Hive');
      } catch (e) {
        debugPrint('初始化Hive失败: $e');
      }
    }

    _historyBox = await Hive.openBox<String>(AppConstants.historyBox);
    _favoriteBox = await Hive.openBox<String>(AppConstants.favoriteBox);
    _cacheBox = await Hive.openBox<String>(AppConstants.cacheBox);
    _settingsBox = await Hive.openBox<String>(AppConstants.settingsBox);
    _sourceBox = await Hive.openBox<String>(AppConstants.sourceBox);
    _userBox = await Hive.openBox<String>(AppConstants.userBox);
    _playlistBox = await Hive.openBox<String>(AppConstants.playlistBox);

    _initialized = true;
  }

  /// 确保已初始化，未初始化时打印警告而非抛异常，避免UI崩溃
  void _ensureInitialized() {
    if (!_initialized && !AppEnv.isTestMode) {
      debugPrint('警告: StorageService 未初始化，请先调用 init()');
    }
  }

  // ==================== 观看历史 ====================

  /// 获取所有观看历史
  List<WatchHistory> getAllHistory() {
    _ensureInitialized();
    if (_historyBox == null) return [];
    final List<WatchHistory> histories = [];
    for (final key in _historyBox!.keys) {
      try {
        final jsonStr = _historyBox!.get(key);
        if (jsonStr != null) {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          histories.add(WatchHistory.fromJson(json));
        }
      } catch (e) {
        debugPrint('解析观看历史失败: $e');
      }
    }
    // 按最后观看时间倒序
    histories.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
    return histories;
  }

  /// 保存观看历史
  Future<void> saveHistory(WatchHistory history) async {
    _ensureInitialized();
    if (_historyBox == null) return;
    final key = '${history.sourceId}_${history.movieId}';
    await _historyBox!.put(key, jsonEncode(history.toJson()));
  }

  /// 删除观看历史
  Future<void> deleteHistory(String movieId, {String sourceId = ''}) async {
    _ensureInitialized();
    if (_historyBox == null) return;
    final key = '${sourceId}_$movieId';
    await _historyBox!.delete(key);
  }

  /// 清空观看历史
  Future<void> clearHistory() async {
    _ensureInitialized();
    if (_historyBox == null) return;
    await _historyBox!.clear();
  }

  /// 获取单个影片的观看历史
  WatchHistory? getHistory(String movieId, {String sourceId = ''}) {
    _ensureInitialized();
    if (_historyBox == null) return null;
    final key = '${sourceId}_$movieId';
    final jsonStr = _historyBox!.get(key);
    if (jsonStr == null) return null;
    try {
      return WatchHistory.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('解析观看历史失败: $e');
      return null;
    }
  }

  // ==================== 收藏 ====================

  /// 获取所有收藏
  List<Favorite> getAllFavorites() {
    _ensureInitialized();
    if (_favoriteBox == null) return [];
    final List<Favorite> favorites = [];
    for (final key in _favoriteBox!.keys) {
      try {
        final jsonStr = _favoriteBox!.get(key);
        if (jsonStr != null) {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          favorites.add(Favorite.fromJson(json));
        }
      } catch (e) {
        debugPrint('解析收藏失败: $e');
      }
    }
    // 按收藏时间倒序
    favorites.sort((a, b) => b.favoriteTime.compareTo(a.favoriteTime));
    return favorites;
  }

  /// 保存收藏
  Future<void> saveFavorite(Favorite favorite) async {
    _ensureInitialized();
    if (_favoriteBox == null) return;
    final key = '${favorite.sourceId}_${favorite.movieId}';
    await _favoriteBox!.put(key, jsonEncode(favorite.toJson()));
  }

  /// 删除收藏
  Future<void> deleteFavorite(String movieId, {String sourceId = ''}) async {
    _ensureInitialized();
    if (_favoriteBox == null) return;
    final key = '${sourceId}_$movieId';
    await _favoriteBox!.delete(key);
  }

  /// 检查是否已收藏
  bool isFavorite(String movieId, {String sourceId = ''}) {
    _ensureInitialized();
    if (_favoriteBox == null) return false;
    final key = '${sourceId}_$movieId';
    return _favoriteBox!.containsKey(key);
  }

  /// 清空收藏
  Future<void> clearFavorites() async {
    _ensureInitialized();
    if (_favoriteBox == null) return;
    await _favoriteBox!.clear();
  }

  // ==================== 缓存项 ====================

  /// 获取所有缓存项
  List<CacheItem> getAllCacheItems() {
    _ensureInitialized();
    if (_cacheBox == null) return [];
    final List<CacheItem> items = [];
    for (final key in _cacheBox!.keys) {
      try {
        final jsonStr = _cacheBox!.get(key);
        if (jsonStr != null) {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          items.add(CacheItem.fromJson(json));
        }
      } catch (e) {
        debugPrint('解析缓存项失败: $e');
      }
    }
    return items;
  }

  /// 保存缓存项
  Future<void> saveCacheItem(CacheItem item) async {
    _ensureInitialized();
    if (_cacheBox == null) return;
    await _cacheBox!.put(item.id, jsonEncode(item.toJson()));
  }

  /// 删除缓存项
  Future<void> deleteCacheItem(String id) async {
    _ensureInitialized();
    if (_cacheBox == null) return;
    await _cacheBox!.delete(id);
  }

  /// 清空缓存项
  Future<void> clearCacheItems() async {
    _ensureInitialized();
    if (_cacheBox == null) return;
    await _cacheBox!.clear();
  }

  // ==================== 播放源 ====================

  /// 获取所有播放源
  List<PlaySource> getAllSources() {
    _ensureInitialized();
    // 自动化测试模式或异常情况下，Box 可能尚未打开；此时返回空列表，避免空指针导致 UI/测试崩溃。
    if (_sourceBox == null) return [];
    final List<PlaySource> sources = [];
    for (final key in _sourceBox!.keys) {
      try {
        final jsonStr = _sourceBox!.get(key);
        if (jsonStr != null) {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          sources.add(PlaySource.fromJson(json));
        }
      } catch (e) {
        debugPrint('解析播放源失败: $e');
      }
    }
    // 按排序权重排序
    sources.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sources;
  }

  /// 保存播放源
  Future<void> saveSource(PlaySource source) async {
    _ensureInitialized();
    if (_sourceBox == null) return;
    await _sourceBox!.put(source.id, jsonEncode(source.toJson()));
  }

  /// 批量保存播放源
  Future<void> saveAllSources(List<PlaySource> sources) async {
    _ensureInitialized();
    if (_sourceBox == null) return;
    await _sourceBox!.clear();
    final Map<String, String> allEntries = {};
    for (final source in sources) {
      allEntries[source.id] = jsonEncode(source.toJson());
    }
    await _sourceBox!.putAll(allEntries);
  }

  /// 删除播放源
  Future<void> deleteSource(String id) async {
    _ensureInitialized();
    if (_sourceBox == null) return;
    await _sourceBox!.delete(id);
  }

  /// 清空播放源
  Future<void> clearSources() async {
    _ensureInitialized();
    if (_sourceBox == null) return;
    await _sourceBox!.clear();
  }

  // ==================== 用户信息 ====================

  /// 获取当前用户
  User? getCurrentUser() {
    _ensureInitialized();
    if (_userBox == null) return null;
    final jsonStr = _userBox!.get('current_user');
    if (jsonStr == null) return null;
    try {
      return User.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('解析用户信息失败: $e');
      return null;
    }
  }

  /// 保存当前用户
  Future<void> saveCurrentUser(User user) async {
    _ensureInitialized();
    if (_userBox == null) return;
    await _userBox!.put('current_user', jsonEncode(user.toJson()));
  }

  /// 清除用户信息
  Future<void> clearCurrentUser() async {
    _ensureInitialized();
    if (_userBox == null) return;
    await _userBox!.delete('current_user');
  }

  // ==================== 通用设置 ====================

  /// AI 字幕配置项
  String get subtitleAiApiUrl =>
      getSetting('subtitle_ai_api_url') ??
      'http://localhost:8000/v1/audio/transcriptions';
  Future<void> setSubtitleAiApiUrl(String v) =>
      saveSetting('subtitle_ai_api_url', v);

  String get subtitleAiApiKey => getSetting('subtitle_ai_api_key') ?? '';
  Future<void> setSubtitleAiApiKey(String v) =>
      saveSetting('subtitle_ai_api_key', v);

  String get subtitleAiModel => getSetting('subtitle_ai_model') ?? 'base';
  Future<void> setSubtitleAiModel(String v) =>
      saveSetting('subtitle_ai_model', v);

  String get subtitleAiLanguage => getSetting('subtitle_ai_language') ?? 'zh';
  Future<void> setSubtitleAiLanguage(String v) =>
      saveSetting('subtitle_ai_language', v);

  int get subtitleAiMaxMinutes =>
      getIntSetting('subtitle_ai_max_minutes', defaultValue: 10);
  Future<void> setSubtitleAiMaxMinutes(int v) =>
      saveIntSetting('subtitle_ai_max_minutes', v);

  bool get subtitleAiSendAsUrl =>
      getBoolSetting('subtitle_ai_send_as_url', defaultValue: false);
  Future<void> setSubtitleAiSendAsUrl(bool v) =>
      saveBoolSetting('subtitle_ai_send_as_url', v);

  String get subtitleAiInitialPrompt =>
      getSetting('subtitle_ai_initial_prompt') ?? '';
  Future<void> setSubtitleAiInitialPrompt(String v) =>
      saveSetting('subtitle_ai_initial_prompt', v);

  // ==================== 离线后端设置 ====================

  /// 字幕 AI 后端类型
  ///
  /// 默认走**离线本地识别**（符合「无需独立后端」）：
  /// - 非 Web：sherpa_onnx 本地模型
  /// - Web：transformers.js（浏览器内推理）
  /// 用户可在「设置 → AI 字幕生成」里切回在线 API。
  SubtitleAiBackendKind get subtitleAiBackend {
    final raw = getSetting('subtitle_ai_backend');
    final fallback = kIsWeb
        ? SubtitleAiBackendKind.transformersWeb
        : SubtitleAiBackendKind.sherpaNative;
    if (raw == null) return fallback;
    return SubtitleAiBackendKind.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => fallback,
    );
  }

  Future<void> setSubtitleAiBackend(SubtitleAiBackendKind v) =>
      saveSetting('subtitle_ai_backend', v.name);

  /// 选中的离线模型 ID
  String get subtitleAiOfflineModel =>
      getSetting('subtitle_ai_offline_model') ?? '';
  Future<void> setSubtitleAiOfflineModel(String v) =>
      saveSetting('subtitle_ai_offline_model', v);

  // ==================== 通用设置方法 ====================

  /// 获取设置值
  String? getSetting(String key) {
    _ensureInitialized();
    if (_settingsBox == null) return null;
    return _settingsBox!.get(key);
  }

  /// 保存设置值
  Future<void> saveSetting(String key, String value) async {
    _ensureInitialized();
    if (_settingsBox == null) return;
    await _settingsBox!.put(key, value);
  }

  /// 删除设置键（恢复到「未设置」= 代码默认值）。
  ///
  /// 用于矩阵测试 deeplink 的 `default` 重置：测试残留的 vo/hwdec/sp/gpuapi
  /// 覆盖键若一直留在 Hive 里，会让后续所有真机验证都跑在非默认配置上
  /// （2026-10-24 实测踩过：残留 `debug_gpu_api=opengl` + `vo=mediacodecEmbed`
  /// 导致磁力首播流程中途切后端、重建播放器）。
  Future<void> deleteSetting(String key) async {
    _ensureInitialized();
    if (_settingsBox == null) return;
    await _settingsBox!.delete(key);
  }

  /// 获取布尔设置值
  bool getBoolSetting(String key, {bool defaultValue = false}) {
    final value = getSetting(key);
    if (value == null) return defaultValue;
    return value.toLowerCase() == 'true';
  }

  /// 保存布尔设置值
  Future<void> saveBoolSetting(String key, bool value) async {
    await saveSetting(key, value.toString());
  }

  /// 获取整数设置值
  int getIntSetting(String key, {int defaultValue = 0}) {
    final value = getSetting(key);
    if (value == null) return defaultValue;
    return int.tryParse(value) ?? defaultValue;
  }

  /// 保存整数设置值
  Future<void> saveIntSetting(String key, int value) async {
    await saveSetting(key, value.toString());
  }

  /// 获取双精度设置值
  double getDoubleSetting(String key, {double defaultValue = 0.0}) {
    final value = getSetting(key);
    if (value == null) return defaultValue;
    return double.tryParse(value) ?? defaultValue;
  }

  /// 保存双精度设置值
  Future<void> saveDoubleSetting(String key, double value) async {
    await saveSetting(key, value.toString());
  }

  // ==================== 数据导出/导入 ====================

  /// 导出所有数据为JSON字符串
  String exportAllData() {
    _ensureInitialized();
    final data = <String, dynamic>{
      'history': getAllHistory().map((e) => e.toJson()).toList(),
      'favorites': getAllFavorites().map((e) => e.toJson()).toList(),
      'sources': getAllSources().map((e) => e.toJson()).toList(),
      'settings': _settingsBox?.toMap() ?? <dynamic, dynamic>{},
      'exportTime': DateTime.now().toIso8601String(),
    };
    return jsonEncode(data);
  }

  /// 导入数据
  /// 先将所有数据解析到内存，验证成功后再清空并写入，避免中途异常导致数据丢失
  Future<bool> importData(String jsonStr) async {
    try {
      _ensureInitialized();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // 先将所有数据解析到内存
      List<WatchHistory>? histories;
      if (data['history'] != null) {
        histories = (data['history'] as List)
            .map((e) => WatchHistory.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      List<Favorite>? favorites;
      if (data['favorites'] != null) {
        favorites = (data['favorites'] as List)
            .map((e) => Favorite.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      List<PlaySource>? sources;
      if (data['sources'] != null) {
        sources = (data['sources'] as List)
            .map((e) => PlaySource.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      Map<String, String>? settings;
      if (data['settings'] != null) {
        settings = <String, String>{};
        final rawSettings = data['settings'] as Map<String, dynamic>;
        for (final entry in rawSettings.entries) {
          if (entry.value is String) {
            settings[entry.key] = entry.value as String;
          }
        }
      }

      // 验证解析结果不为空
      if (histories == null &&
          favorites == null &&
          sources == null &&
          settings == null) {
        return false;
      }

      // 解析成功，开始写入数据
      if (histories != null) {
        if (_historyBox == null) return false;
        await _historyBox!.clear();
        for (final h in histories) {
          await _historyBox!.put(
            '${h.sourceId}_${h.movieId}',
            jsonEncode(h.toJson()),
          );
        }
      }

      if (favorites != null) {
        if (_favoriteBox == null) return false;
        await _favoriteBox!.clear();
        for (final f in favorites) {
          await _favoriteBox!.put(
            '${f.sourceId}_${f.movieId}',
            jsonEncode(f.toJson()),
          );
        }
      }

      if (sources != null) {
        if (_sourceBox == null) return false;
        await _sourceBox!.clear();
        for (final s in sources) {
          await _sourceBox!.put(s.id, jsonEncode(s.toJson()));
        }
      }

      if (settings != null) {
        if (_settingsBox == null) return false;
        await _settingsBox!.clear();
        for (final entry in settings.entries) {
          await _settingsBox!.put(entry.key, entry.value);
        }
      }

      return true;
    } catch (e) {
      debugPrint('导入数据失败: $e');
      return false;
    }
  }

  // ==================== 播放列表 ====================

  /// 获取所有播放列表
  List<Playlist> getAllPlaylists() {
    _ensureInitialized();
    if (_playlistBox == null) return [];
    final List<Playlist> playlists = [];
    for (final key in _playlistBox!.keys) {
      try {
        final jsonStr = _playlistBox!.get(key);
        if (jsonStr != null) {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          playlists.add(Playlist.fromMap(json));
        }
      } catch (e) {
        debugPrint('解析播放列表失败: $e');
      }
    }
    // 按更新时间倒序
    playlists.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return playlists;
  }

  /// 保存播放列表
  Future<void> savePlaylist(Playlist playlist) async {
    _ensureInitialized();
    if (_playlistBox == null) return;
    await _playlistBox!.put(playlist.id, jsonEncode(playlist.toMap()));
  }

  /// 删除播放列表
  Future<void> deletePlaylist(String id) async {
    _ensureInitialized();
    if (_playlistBox == null) return;
    await _playlistBox!.delete(id);
  }

  /// 关闭所有Box
  Future<void> close() async {
    await _historyBox?.close();
    await _favoriteBox?.close();
    await _cacheBox?.close();
    await _settingsBox?.close();
    await _sourceBox?.close();
    await _userBox?.close();
    await _playlistBox?.close();
    _initialized = false;
  }
}
