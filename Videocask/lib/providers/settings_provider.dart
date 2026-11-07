import 'dart:async';

import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/magnet_source_catalog.dart';
import '../models/magnet_source_config.dart';
import '../services/storage_service.dart';
import '../services/buffer_tier.dart';
import '../services/device_memory_probe.dart';
import '../services/video_output_policy.dart';
import '../services/cache_service.dart';
import '../services/m3u8_playlist_resolver.dart';
import '../services/sync_service.dart';
import '../services/webdav_service.dart';
import '../services/hw_decode_policy.dart';
import '../services/hw_decode_migration.dart';
import '../services/hw_decode_platform.dart';
import '../services/debug_log.dart';

/// 实测长期不可达的内置磁力源 id。
///
/// 常量与配置数据都保留（以后源恢复了改这里即可），只是不再出现在 UI、
/// 也不再参与聚合搜索。2026-10-27 真机 5G + 本机直连双重实测：
/// 这四个源全部 connection timeout，留着只会让每次搜索白等一轮。
const Set<String> kUnreachableBuiltinMagnetSources = {
  'yts_mx',
  '1337x',
  'bt4g',
  'nyaa',
};

/// 设置状态管理
class SettingsProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final SyncService _syncService = SyncService();

  /// 默认清晰度
  String _defaultQuality = '自动';

  /// 默认清晰度
  String get defaultQuality => _defaultQuality;

  /// 硬件解码总开关
  ///
  /// 默认**开启**：硬解是移动端省电与流畅度的关键，默认关闭等于让所有用户
  /// 都在用 CPU 软解 1080p/4K。是否真的生效由用户根据机型自行决定，
  /// App 不再自动改档。
  bool _hardwareDecode = true;

  /// 硬件解码总开关
  bool get hardwareDecode => _hardwareDecode;

  /// 硬件解码档位键（空串 = 跟随平台默认）。
  String _hwDecodeModeKey = '';

  /// 实际生效的硬件解码档位。
  ///
  /// 只认「档位键」这一个真相。旧的布尔总开关已在 [init] 里迁移成
  /// `disabled` 档位后清理，避免两个控件互相打架。
  HwDecodeMode get effectiveHwDecodeMode {
    final platform = detectHwDecodePlatform();
    return _hwDecodeModeKey.isEmpty
        ? defaultHwDecodeMode(platform)
        : hwDecodeModeFromKey(_hwDecodeModeKey, platform: platform);
  }

  /// 硬件解码档位键（空串 = 跟随平台默认）。
  String get hwDecodeModeKey => _hwDecodeModeKey;

  /// 视频输出后端键（空串 = 跟随默认档位）。
  String _videoOutputModeKey = '';

  /// 实际生效的视频输出后端。
  ///
  /// 默认 `gpu-next`（新版渲染）。fd 泄漏已在引擎层通过「SurfaceTexture 桥接」统一
  /// 修复，与 `--vo` 无关——三种后端都不漏句柄。App **不做任何自动切换**：
  /// 个别 GPU（如 Adreno）下 `gpu-next` 可能短暂黑屏，此时由用户手动改档。
  VideoOutputMode get effectiveVideoOutputMode => _videoOutputModeKey.isEmpty
      ? defaultVideoOutputMode
      : videoOutputModeFromKey(_videoOutputModeKey);

  /// 视频输出后端键（空串 = 跟随默认档位）。
  String get videoOutputModeKey => _videoOutputModeKey;

  /// 设置视频输出后端（仅手动切换；App 不做自动回退）。
  Future<void> setVideoOutputMode(VideoOutputMode mode) async {
    _videoOutputModeKey = encodeVideoOutputMode(mode);
    await _storage.saveSetting(
      AppConstants.keyVideoOutputMode,
      _videoOutputModeKey,
    );
    notifyListeners();
  }

  /// 自动连播
  bool _autoPlayNext = true;

  /// 自动连播
  bool get autoPlayNext => _autoPlayNext;

  /// 进入详情页自动播放
  bool _autoPlayOnDetailEnter = true;

  bool get autoPlayOnDetailEnter => _autoPlayOnDetailEnter;

  /// 播放策略：内部仍保留 smooth/balanced/quality（影响换线超时、预拉字节数），
  /// 但不再给用户三档旋钮——三档的缓冲参数已被自动挡位统一覆盖，留着只会误导。
  String _playbackStrategy = 'balanced';

  String get playbackStrategy => _playbackStrategy;

  /// 拖动精度（mpv hr-seek）：'' = 跟随默认 / 'yes' = 精确 / 'no' = 快速。
  String _hrSeekMode = '';

  String get hrSeekMode => _hrSeekMode;

  /// 播放到 80% 时提前解析 + 预拉下一集。
  ///
  /// 旧版拆成「预加载下一集」和「播放预缓冲」两个开关，但预加载会先解析
  /// URL 再看第二个开关，关掉后者照样预热。现在合并为一个开关，两个旧键
  /// 都继续读写（旧备份/云同步不会丢设置），语义取「两者都为真」。
  bool _preloadNextEpisode = true;

  bool get preloadNextEpisode => _preloadNextEpisode && _playbackPrefetch;

  /// 预拉下一集前几 MB（全网络，可关）
  bool _playbackPrefetch = true;

  bool get playbackPrefetch => _playbackPrefetch;

  /// HLS 去广告总开关（默认开）
  ///
  /// 个别片源被误判删片（跳剧情）时，用户可整个关掉过滤回退直连。
  bool _hlsAdFilter = true;

  bool get hlsAdFilter => _hlsAdFilter;

  /// 后台播放：返回桌面/切到其它应用时继续保持播放（默认开）。
  ///
  /// 关闭后：进入后台即自动暂停，回到前台自动恢复。
  bool _backgroundPlayback = true;

  bool get backgroundPlayback => _backgroundPlayback;

  /// demuxer 缓冲挡位。
  ///
  /// `auto` = 按设备物理内存自动选（见 [BufferTier]）；
  /// 其余为固定 MB：128 / 192 / 256 / 384 / 512。
  String _bufferTier = BufferTier.autoKey;

  String get bufferTier => _bufferTier;

  /// 自动挡**当前**实际生效的字节数（按物理内存定天花板，再按可用内存升降档）。
  ///
  /// 0 = 还没算过，回落到按物理内存推算的固定值。
  int _autoBufferBytes = 0;

  int get autoBufferBytes => _autoBufferBytes > 0
      ? _autoBufferBytes
      : BufferTier.autoBytesFor(_deviceTotalMemoryBytes);

  /// 最近一次探测到的系统可用内存（字节）；0 = 未知。
  int _availableMemoryBytes = 0;

  int get availableMemoryBytes => _availableMemoryBytes;

  /// 自动挡动态评估定时器（只在播放期间存在）。
  Timer? _bufferAutoTuneTimer;

  bool _bufferAutoTuneProbing = false;

  /// 实际生效的缓冲字节数。
  ///
  /// 手动挡位直接用；auto 用 [_autoBufferBytes]（随可用内存动态变）。
  /// **字节与秒数必须同步**：调用方一律拿这个值交给
  /// `PlaybackStrategyConfig.fromKey(bufferBytes:)`，由 [BufferTier] 之外的那层
  /// 再按 [secsForBytes] 换算出 readahead-secs，不要只改字节上限。
  int get effectiveBufferBytes => _bufferTier == BufferTier.autoKey
      ? autoBufferBytes
      : BufferTier.resolveBytes(
          tier: _bufferTier,
          totalMemoryBytes: _deviceTotalMemoryBytes,
        );

  /// 设备物理内存（字节）；未探测到时为 0。
  int _deviceTotalMemoryBytes = 0;

  int get deviceTotalMemoryBytes => _deviceTotalMemoryBytes;

  /// 写入设备内存探测结果（由 [DeviceMemoryProbe] 在启动后调用）。
  void applyDeviceTotalMemory(int bytes) {
    if (bytes <= 0 || bytes == _deviceTotalMemoryBytes) return;
    _deviceTotalMemoryBytes = bytes;
    _autoBufferBytes = BufferTier.autoBytesFor(bytes);
    notifyListeners();
  }

  // ========== 自动缓冲挡位（动态） ==========

  /// 开始自动挡动态评估（**播放开始时**调用）。
  ///
  /// 立即先评估一次，之后每 [BufferTier.autoTuneInterval]（10 分钟）一次。
  /// 手动挡位也照样挂定时器（回调里直接早退），这样用户播放中切回「自动」
  /// 不需要重新进出播放页。
  Future<void> startBufferAutoTune() async {
    _bufferAutoTuneTimer ??= Timer.periodic(
      BufferTier.autoTuneInterval,
      (_) => unawaited(evaluateBufferAutoTier()),
    );
    await evaluateBufferAutoTier();
  }

  /// 停止评估（离开播放页 / 播放结束时调用）。
  void stopBufferAutoTune() {
    _bufferAutoTuneTimer?.cancel();
    _bufferAutoTuneTimer = null;
  }

  /// 探测一次可用内存，必要时升/降档。
  ///
  /// 只用「可用内存」调整自动挡，**不改用户手动选的挡位**。
  Future<void> evaluateBufferAutoTier() async {
    if (_bufferTier != BufferTier.autoKey) return;
    if (_bufferAutoTuneProbing) return;
    _bufferAutoTuneProbing = true;
    try {
      final avail = await DeviceMemoryProbe.readAvailableMemoryBytes();
      // 探测是 async 的：期间 provider 可能已被 dispose（退出应用），
      // 之后再 notifyListeners 会命中 ChangeNotifier 的 disposed 断言。
      if (_disposed) return;
      // 探测失败（桌面/Web/通道异常）→ 保持现状，绝不因为一次失败降档。
      if (avail <= 0) return;
      _availableMemoryBytes = avail;

      final current = autoBufferBytes;
      final next = BufferTier.adaptiveBytesFor(
        totalMemoryBytes: _deviceTotalMemoryBytes,
        availableMemoryBytes: avail,
        currentBytes: current,
      );
      if (next == current) {
        // 数值没变也要通知：设置页要显示最新的「当前可用」。
        notifyListeners();
        return;
      }
      const mb = 1024 * 1024;
      _autoBufferBytes = next;
      DebugLog.log(
        'Play',
        '自动缓冲挡位 ${current ~/ mb}MB → ${next ~/ mb}MB'
            '（可用 ${avail ~/ mb}MB）',
        flush: true,
      );
      notifyListeners();
    } finally {
      _bufferAutoTuneProbing = false;
    }
  }

  /// 是否已 dispose（async 回调用它挡掉 dispose 之后的 notifyListeners）。
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _bufferAutoTuneTimer?.cancel();
    _bufferAutoTuneTimer = null;
    super.dispose();
  }

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

  /// TMDB API Key（中文片名解析为 IMDb / 英文名，提升磁力命中率）
  String _tmdbApiKey = '';

  String get tmdbApiKey => _tmdbApiKey;

  bool get tmdbApiKeyConfigured => _tmdbApiKey.trim().isNotEmpty;

  /// 磁力搜索源（含内置与自定义）
  List<MagnetSourceConfig> _magnetSources = [];

  List<MagnetSourceConfig> get magnetSources =>
      List.unmodifiable(_magnetSources);

  /// 设置页「磁力搜索源」实际渲染/可操作的内置+自定义源。
  /// 实测死源不删数据，只是不出现在列表里。
  List<MagnetSourceConfig> get visibleMagnetSources => List.unmodifiable(
        _magnetSources
            .where(
              (c) =>
                  !c.isBuiltin ||
                  !kUnreachableBuiltinMagnetSources.contains(c.id),
            )
            .toList(),
      );

  int get enabledMagnetSourceCount =>
      visibleMagnetSources.where((c) => c.enabled).length;

  /// 本次启动自动关掉了几个曾经启用的死源（>0 时 UI 给一次提示）。
  int _deadSourcesAutoDisabled = 0;

  int get deadSourcesAutoDisabled => _deadSourcesAutoDisabled;

  void acknowledgeDeadSourcesNotice() {
    if (_deadSourcesAutoDisabled == 0) return;
    _deadSourcesAutoDisabled = 0;
    notifyListeners();
  }

  /// 老版本用户可能手动开过死源：升级后自动关掉，避免每次聚合搜索白等超时。
  Future<void> _migrateUnreachableMagnetSources() async {
    var changed = false;
    for (var i = 0; i < _magnetSources.length; i++) {
      final c = _magnetSources[i];
      if (c.isBuiltin &&
          kUnreachableBuiltinMagnetSources.contains(c.id) &&
          c.enabled) {
        _magnetSources[i] = c.copyWith(enabled: false);
        _deadSourcesAutoDisabled++;
        changed = true;
      }
    }
    if (changed) await _persistMagnetSources();
  }

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
    // 物理内存决定「自动」缓冲挡位的天花板（安装后首次启动就能定档），
    // 可用内存用来在播放中每 10 分钟做一次升降档评估。
    // 通道调用很快，但桌面/Web 没有实现，加超时兜底，
    // 探测失败按 BufferTier.fallbackBytes 处理。
    try {
      final mem = await DeviceMemoryProbe.readTotalMemoryBytes()
          .timeout(const Duration(milliseconds: 800), onTimeout: () => 0);
      if (mem > 0) {
        _deviceTotalMemoryBytes = mem;
        _autoBufferBytes = BufferTier.autoBytesFor(mem);
      }
      final avail = await DeviceMemoryProbe.readAvailableMemoryBytes()
          .timeout(const Duration(milliseconds: 800), onTimeout: () => 0);
      if (avail > 0) _availableMemoryBytes = avail;
      if (mem > 0 || avail > 0) {
        const mb = 1024 * 1024;
        DebugLog.log(
          'Play',
          '设备内存 total=${mem ~/ mb}MB 可用=${avail ~/ mb}MB → '
              '自动缓冲天花板 ${BufferTier.autoBytesFor(mem) ~/ mb}MB',
          flush: true,
        );
      }
    } catch (_) {
      // 忽略：自动挡位会退回保守值
    }
    _defaultQuality =
        _storage.getSetting(AppConstants.keyDefaultQuality) ?? '自动';
    // HLS master playlist 的变体选择读的是静态值，启动时就要同步。
    M3u8PlaylistResolver.preferredQuality = _defaultQuality;
    // 旧版有「硬件解码」布尔总开关 + 「硬解档位」两套控件，语义冲突。
    // 启动时合并成一个档位键：旧开关=false 等价于「关闭（软件解码）」，
    // 迁移完立刻清掉旧键，保证老用户的软解行为不变。
    final legacyHwRaw = _storage.getSetting(AppConstants.keyHardwareDecode);
    final legacyHw = legacyHwRaw == null
        ? null
        : legacyHwRaw.toLowerCase() == 'true';
    final hwMigration = resolveHwDecodeMigration(
      legacyHardwareDecode: legacyHw,
      savedModeKey: _storage.getSetting(AppConstants.keyHwDecodeMode) ?? '',
    );
    _hardwareDecode = legacyHw ?? true;
    _hwDecodeModeKey = hwMigration.modeKey;
    if (hwMigration.modeKey.isNotEmpty) {
      await _storage.saveSetting(
        AppConstants.keyHwDecodeMode,
        hwMigration.modeKey,
      );
    }
    if (hwMigration.clearLegacyKey) {
      await _storage.deleteSetting(AppConstants.keyHardwareDecode);
    }
    _videoOutputModeKey =
        _storage.getSetting(AppConstants.keyVideoOutputMode) ?? '';
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
    // 拖动精度独立成项后，从旧三档里还原用户原本实际吃到的 hr-seek，
    // 避免升级后突然从「快速」变「精确」（或反过来）。
    final savedHrSeek = _storage.getSetting(AppConstants.keyHrSeekMode);
    if (savedHrSeek != null) {
      _hrSeekMode = savedHrSeek == 'yes' || savedHrSeek == 'no'
          ? savedHrSeek
          : '';
    } else {
      _hrSeekMode = _playbackStrategy == 'smooth'
          ? 'no'
          : (_playbackStrategy == 'quality' ? 'yes' : '');
      await _storage.saveSetting(AppConstants.keyHrSeekMode, _hrSeekMode);
    }
    _preloadNextEpisode = _storage.getBoolSetting(
      AppConstants.keyPreloadNextEpisode,
      defaultValue: true,
    );
    _playbackPrefetch = _loadPlaybackPrefetchSetting();
    _hlsAdFilter = _storage.getBoolSetting(
      AppConstants.keyHlsAdFilter,
      defaultValue: true,
    );
    // 推送到解析器静态开关：本地代理与缓存下载共用同一条过滤链路。
    M3u8PlaylistResolver.adFilterEnabled = _hlsAdFilter;
    _backgroundPlayback = _storage.getBoolSetting(
      AppConstants.keyBackgroundPlayback,
      defaultValue: true,
    );
    final savedTier =
        _storage.getSetting(AppConstants.keyBufferTier) ?? BufferTier.autoKey;
    _bufferTier =
        BufferTier.allKeys.contains(savedTier) ? savedTier : BufferTier.autoKey;
    _tmdbApiKey = _storage.getSetting(AppConstants.keyTmdbApiKey) ?? '';

    // 初始化同步服务
    await _syncService.init();
    _webdavConfig = _syncService.getWebDavConfig();
    _webdavConnected = _webdavConfig != null && _webdavConfig!.isValid;
    _lastSyncTime = _syncService.lastSyncTime;

    _loadMagnetSources();
    await _migrateUnreachableMagnetSources();

    notifyListeners();
  }

  /// 设置默认清晰度
  Future<void> setDefaultQuality(String quality) async {
    _defaultQuality = quality;
    // 立即生效：下一次 open 媒体时按新档位挑变体。
    M3u8PlaylistResolver.preferredQuality = quality;
    await _storage.saveSetting(AppConstants.keyDefaultQuality, quality);
    notifyListeners();
  }

  /// 兼容旧调用：现在只改档位，不再单独维护布尔总开关。
  Future<void> setHardwareDecode(bool value) async {
    await setHwDecodeMode(
      value
          ? defaultHwDecodeMode(detectHwDecodePlatform())
          : HwDecodeMode.disabled,
    );
  }

  /// 设置硬件解码档位（唯一的硬解真相）。
  Future<void> setHwDecodeMode(HwDecodeMode mode) async {
    _hwDecodeModeKey = encodeHwDecodeMode(mode);
    _hardwareDecode = mode != HwDecodeMode.disabled;
    await _storage.saveSetting(
      AppConstants.keyHwDecodeMode,
      _hwDecodeModeKey,
    );
    notifyListeners();
  }

  /// 设置拖动精度（mpv hr-seek）。
  Future<void> setHrSeekMode(String mode) async {
    final normalized = mode == 'yes' || mode == 'no' ? mode : '';
    if (_hrSeekMode == normalized) return;
    _hrSeekMode = normalized;
    await _storage.saveSetting(AppConstants.keyHrSeekMode, normalized);
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
    _playbackPrefetch = value;
    // 两个旧键一起写，保证旧备份/云同步读到的语义与界面上的单一开关一致。
    await _storage.saveBoolSetting(AppConstants.keyPreloadNextEpisode, value);
    await _storage.saveBoolSetting(AppConstants.keyPlaybackPrefetch, value);
    notifyListeners();
  }

  Future<void> setPlaybackPrefetch(bool value) async {
    _playbackPrefetch = value;
    await _storage.saveBoolSetting(AppConstants.keyPlaybackPrefetch, value);
    notifyListeners();
  }

  /// 设置 HLS 去广告开关
  ///
  /// 关闭后重新解析的播放列表不再剔除任何分片（已在播放的会话不受影响，
  /// 换集/重进详情页后生效）。用于规避个别片源的误删。
  Future<void> setHlsAdFilter(bool value) async {
    _hlsAdFilter = value;
    M3u8PlaylistResolver.adFilterEnabled = value;
    await _storage.saveBoolSetting(AppConstants.keyHlsAdFilter, value);
    notifyListeners();
  }

  /// 设置后台播放开关。
  ///
  /// 只影响「切到后台」的行为：开 → 继续播（需要前台服务保活）；
  /// 关 → 进入后台立即暂停，回到前台自动恢复。
  Future<void> setBackgroundPlayback(bool value) async {
    if (_backgroundPlayback == value) return;
    _backgroundPlayback = value;
    await _storage.saveBoolSetting(AppConstants.keyBackgroundPlayback, value);
    notifyListeners();
  }

  /// 设置缓冲挡位（[BufferTier.autoKey] 或 '128'/'192'/'256'/'384'/'512'）。
  ///
  /// 自动挡会按物理内存重算天花板，并立刻按当前可用内存校一次；
  /// 播放中改挡位由详情页监听 provider 变化后热设 mpv 属性（字节+秒数一起变）。
  Future<void> setBufferTier(String tier) async {
    final normalized =
        BufferTier.allKeys.contains(tier) ? tier : BufferTier.autoKey;
    if (_bufferTier == normalized) return;
    _bufferTier = normalized;
    if (normalized == BufferTier.autoKey) {
      _autoBufferBytes = BufferTier.autoBytesFor(_deviceTotalMemoryBytes);
    }
    await _storage.saveSetting(AppConstants.keyBufferTier, normalized);
    notifyListeners();
    if (normalized == BufferTier.autoKey) {
      await evaluateBufferAutoTier();
    }
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
