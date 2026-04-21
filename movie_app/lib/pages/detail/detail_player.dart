import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../services/player_service.dart';
import '../../services/torrent_player_service.dart';
import '../../models/movie.dart';
import '../../providers/history_provider.dart';
import '../../utils/playback_throughput.dart';

import 'playback_error_type.dart';

/// 播放器相关逻辑
class DetailPlayer {
  /// 音量 UI 上限（可超过 100 以尝试 mpv 高音量）
  static const double maxVolumeUi = 200.0;

  /// 播放器服务
  final PlayerService playerService = PlayerService();

  /// 磁力播放服务（P2P边下边播）
  final TorrentPlayerService torrentService = TorrentPlayerService();

  /// 视频控制器（用于兼容旧代码）
  VideoController? get videoController => playerService.videoController;

  /// 播放器实例（用于兼容旧代码）
  Player? get player => playerService.player;

  // ========== 播放器状态 ==========

  /// 是否正在缓冲
  bool isBuffering = false;

  /// 正在打开媒体（解析完成到 player.open 结束之间，避免「点了没反应」）
  bool isOpeningMedia = false;

  /// 缓冲位置（用于进度条缓冲指示）
  Duration bufferedPosition = Duration.zero;

  /// 缓存速度（字节/秒）
  int cacheSpeed = 0;

  final PlaybackThroughputEstimator _throughputEstimator =
      PlaybackThroughputEstimator();

  /// mpv 报告的音频码率（bits/s），用于吞吐估算
  double? audioBitrateBps;

  /// 当前视频宽高（用于视频码率估算）
  int? videoWidth;
  int? videoHeight;

  /// 当前播放位置
  Duration position = Duration.zero;

  /// 视频总时长
  Duration duration = Duration.zero;

  /// 当前播放的URL
  String? currentPlayUrl;

  /// 当前播放集数索引
  int currentEpisodeIndex = 0;

  /// 当前播放线路索引（写入历史）
  int currentRouteIndex = 0;

  /// 本集打开后待恢复进度（仅当与历史线路/集一致时生效）
  Duration? pendingResumePosition;

  /// 与 [pendingResumePosition] 对应的历史线路、集（用于判断是否续播）
  int? resumeTargetRouteIndex;
  int? resumeTargetEpisodeIndex;

  /// 单集播放结束且未自动下一集时显示重播
  bool showReplayOverlay = false;

  /// 错误信息
  String playerErrorMessage = '';
  PlaybackErrorType playbackErrorType = PlaybackErrorType.none;

  /// 重试次数
  int retryCount = 0;

  /// 是否正在重试（防重入）
  bool isRetrying = false;

  /// 最大重试次数
  static const int maxRetryCount = 3;

  /// 是否正在播放
  bool isPlaying = false;

  /// 是否全屏
  bool isFullScreen = false;

  /// 当前音量（0–200，UI 与手势；>100 依赖 mpv 对高 volume 的支持）
  double volume = 100.0;
  double muteVolume = 100.0;

  /// 画面对比度（约 0.6–1.4，1.0 为默认）
  double videoContrast = 1.0;

  /// 是否静音
  bool isMuted = false;

  /// 是否显示控制栏
  bool showControls = true;

  /// 是否显示快捷键帮助面板
  bool showShortcutHelp = false;

  /// 点击音量图标时，在图标上方显示纵向滑块（B 站风格）
  bool showVolumePopover = false;

  /// 播放速度
  double playbackSpeed = 1.0;

  /// 控制栏自动隐藏定时器
  Timer? hideTimer;

  /// 详情页在播放/缓冲/进度变化时刷新 UI（由 [DetailPage] 赋值为 `setState`）
  VoidCallback? onUiChanged;

  /// 当前集播放自然结束（非切集）
  VoidCallback? onPlaybackEnded;

  /// 缓冲状态变化（供详情页做自动线路回退等）
  void Function(bool buffering)? onBufferingChangedUi;

  int _lastUiNotifyMs = 0;

  static const int _uiNotifyMinIntervalMs = 200;

  /// 竖滑手势起始是否在左半屏（亮度）；由 [DetailPage] 在 dragStart 写入
  bool verticalGestureIsLeftSide = false;

  void _notifyUiThrottled() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastUiNotifyMs < _uiNotifyMinIntervalMs) return;
    _lastUiNotifyMs = now;
    onUiChanged?.call();
  }

  void _notifyUiImmediate() {
    _lastUiNotifyMs = DateTime.now().millisecondsSinceEpoch;
    onUiChanged?.call();
  }

  // ========== 单击暂停/播放指示器 ==========

  /// 是否显示中央播放/暂停指示器
  bool showPlayPauseIndicator = false;

  /// 中央指示器图标
  IconData playPauseIndicatorIcon = Icons.play_arrow;

  /// 中央指示器自动隐藏定时器
  Timer? playPauseIndicatorTimer;

  // ========== 手势反馈可视化 ==========

  /// 快进/快退气泡文本（如 "+5s" / "-10s"）
  String seekBubbleText = '';

  /// 是否显示快进/快退气泡
  bool showSeekBubble = false;

  /// 快进/快退气泡自动隐藏定时器
  Timer? seekBubbleTimer;

  /// 手势进度条进度值（0.0-1.0）
  double gestureProgress = 0;

  /// 是否显示手势进度条
  bool showGestureBar = false;

  /// 是否为亮度手势（true=亮度，false=音量）
  bool isBrightnessGesture = true;

  /// 手势进度条自动隐藏定时器
  Timer? gestureBarTimer;

  // ========== 播放器高级功能记忆 ==========

  /// 画面比例记忆（movieId -> 比例值字符串）
  final Map<String, String> aspectRatioMemory = {};

  /// 上次使用的播放速度
  double lastUsedSpeed = 1.0;

  // ========== 手势亮度/音量调节相关 ==========

  /// 当前亮度值（0.0 ~ 1.0）
  double brightness = 0.5;

  /// 是否显示手势提示
  bool showGestureHint = false;

  /// 手势提示图标
  IconData gestureHintIcon = Icons.brightness_medium;

  /// 手势提示数值（0.0 ~ 1.0）
  double gestureHintValue = 0;

  /// 手势提示自动隐藏定时器
  Timer? gestureHintTimer;

  /// 手势节流：上次更新时间戳
  int lastGestureUpdateMs = 0;

  /// 手势节流：最小间隔（毫秒）
  static const gestureThrottleMs = 50;

  // ========== 字幕相关 ==========

  /// 解析后的字幕列表 [{start: ms, end: ms, text: 内容}]
  List<Map<String, String>> subtitles = [];

  /// 是否显示字幕
  bool showSubtitles = false;

  /// 当前字幕文本
  String currentSubtitleText = '';

  /// 字幕文件名称
  String subtitleFileName = '';

  /// 字幕字体大小
  double subtitleFontSize = 18.0;

  /// 字幕颜色
  Color subtitleColor = Colors.white;

  /// 字幕位置（0=底部, 1=顶部）
  int subtitlePosition = 0;

  // ========== 画面比例相关 ==========

  /// 当前画面比例（0 表示原始比例，999/999 表示填充）
  double aspectRatio = 16 / 9;

  /// 画面比例选项列表
  final List<MapEntry<String, double>> aspectRatios = [
    const MapEntry('自动', 16 / 9),
    const MapEntry('4:3', 4 / 3),
    const MapEntry('全屏裁剪', 999 / 999),
    const MapEntry('原始', 0),
  ];

  // ========== 长按加速相关 ==========

  /// 长按前的正常播放速度
  double normalSpeed = 1.0;

  /// 长按加速提示是否显示
  bool showSpeedHint = false;

  // ========== 锁屏相关 ==========

  /// 是否锁定屏幕
  bool isScreenLocked = false;

  /// 自动连播开关
  bool isAutoPlayNext = true;

  // ========== 磁力缓存状态 ==========

  /// 磁力缓存步骤：0=未开始, 1=解析元数据, 2=连接节点, 3=缓冲数据, 4=播放中, -1=失败
  int torrentStep = 0;
  String torrentMessage = '';

  // ========== AB循环播放相关 ==========

  /// AB循环起始点（A点）
  Duration? loopStart;

  /// AB循环结束点（B点）
  Duration? loopEnd;

  /// 是否正在AB循环中
  bool isABLooping = false;

  // ========== 磁力链接相关 ==========

  /// 当前/最近一次播放的磁力链接（写入观看历史）
  String lastMagnetUri = '';

  // ========== 位置更新节流时间戳 ==========

  int lastPositionUpdateMs = 0;

  /// 位置更新节流间隔（毫秒）
  static const positionThrottleMs = 200;

  // ========== 播放进度恢复相关 ==========

  /// 是否有观看历史记录（用于「上次看到」提示）
  bool hasHistory = false;

  /// 上次播放进度（毫秒）
  int lastPlayProgress = 0;

  /// 上次播放时长（毫秒）
  int lastPlayDuration = 0;

  /// 上次播放进度百分比（0.0 ~ 1.0）
  double get progressPercent {
    if (lastPlayDuration <= 0) return 0.0;
    return (lastPlayProgress / lastPlayDuration).clamp(0.0, 1.0);
  }

  /// 周期性落盘播放进度（避免仅靠 dispose 导致「继续观看」恒为 0%）
  Timer? progressPersistTimer;

  /// 初始化播放器
  Future<void> initialize() async {
    // 初始化播放器服务
    await playerService.init();

    // 监听播放器状态
    playerService.onPositionChanged = (position) {
      this.position = position;
      _notifyUiThrottled();
    };

    playerService.onDurationChanged = (duration) {
      this.duration = duration;
      if (duration > Duration.zero) {
        isOpeningMedia = false;
        _applyPendingResume(duration);
      }
      _notifyUiThrottled();
    };

    playerService.onPlayingChanged = (playing) {
      isPlaying = playing;
      if (playing) {
        isOpeningMedia = false;
      }
      _notifyUiImmediate();
    };

    playerService.onBufferingChanged = (buffering) {
      isBuffering = buffering;
      onBufferingChangedUi?.call(buffering);
      _notifyUiImmediate();
    };

    playerService.onBufferChanged = (buffer) {
      bufferedPosition = buffer;
      final now = DateTime.now().millisecondsSinceEpoch;
      cacheSpeed = _throughputEstimator.update(
        buffer: buffer,
        wallMs: now,
        audioBitrateBps: audioBitrateBps,
        videoWidth: videoWidth,
        videoHeight: videoHeight,
      );
      _notifyUiThrottled();
    };

    playerService.onRateChanged = (rate) {
      playbackSpeed = rate;
      _notifyUiThrottled();
    };

    playerService.onAudioBitrateChanged = (bps) {
      audioBitrateBps = bps;
    };

    playerService.onVideoSizeChanged = (w, h) {
      videoWidth = w;
      videoHeight = h;
    };

    playerService.onSubtitle = (lines) {
      currentSubtitleText =
          lines.map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n');
      if (showSubtitles) {
        _notifyUiThrottled();
      }
    };

    // 监听播放器错误
    playerService.onError = (error) {
      playerErrorMessage = error;
      playbackErrorType = PlaybackErrorType.networkOrPlayer;
      isOpeningMedia = false;
      _notifyUiImmediate();
    };

    playerService.onCompleted = () {
      isPlaying = false;
      onPlaybackEnded?.call();
      _notifyUiImmediate();
    };

    unawaited(_syncBrightnessFromSystem());
  }

  void _applyPendingResume(Duration total) {
    final pending = pendingResumePosition;
    if (pending == null || total <= Duration.zero) return;
    if (pending >= total - const Duration(seconds: 2)) {
      pendingResumePosition = null;
      resumeTargetRouteIndex = null;
      resumeTargetEpisodeIndex = null;
      return;
    }
    pendingResumePosition = null;
    resumeTargetRouteIndex = null;
    resumeTargetEpisodeIndex = null;
    unawaited(playerService.seek(pending));
    position = pending;
    _notifyUiThrottled();
  }

  Future<void> _syncBrightnessFromSystem() async {
    if (kIsWeb) return;
    try {
      final b = await ScreenBrightness().application;
      brightness = b.clamp(0.0, 1.0);
      _notifyUiThrottled();
    } catch (_) {}
  }

  /// 播放视频
  Future<void> play(String url) async {
    currentPlayUrl = url;
    await playerService.play(url);
  }

  /// 暂停播放
  Future<void> pause() async {
    await playerService.pause();
  }

  /// 恢复播放
  Future<void> resume() async {
    await playerService.resume();
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    await playerService.seek(position);
  }

  /// 调整音量
  Future<void> setVolume(double volume) async {
    this.volume = volume.clamp(0.0, maxVolumeUi);
    await playerService.setVolume(this.volume);
  }

  /// 切换静音
  Future<void> toggleMute() async {
    isMuted = !isMuted;
    if (isMuted) {
      muteVolume = volume;
      await playerService.setVolume(0);
    } else {
      await playerService.setVolume(muteVolume);
    }
  }

  /// 调整播放速度
  Future<void> setPlaybackSpeed(double speed) async {
    playbackSpeed = speed;
    await playerService.setRate(speed);
  }

  /// 切换全屏（实际系统栏与布局由 [DetailPage] 统一处理）
  Future<void> toggleFullScreen(BuildContext context) async {
    isFullScreen = !isFullScreen;
  }

  /// 保存播放进度
  Future<void> saveProgress(
    BuildContext context,
    Movie movie, {
    String? sourceId,
    int? routeIndex,
  }) async {
    if (currentPlayUrl == null) return;

    final historyProvider = context.read<HistoryProvider>();
    await historyProvider.saveOrUpdateHistory(
      movieId: movie.id,
      movieName: movie.name,
      movieCover: movie.cover,
      episodeIndex: currentEpisodeIndex,
      episodeName: '第${currentEpisodeIndex + 1}集',
      progress: position.inMilliseconds,
      duration: duration.inMilliseconds,
      sourceId: sourceId ?? movie.sourceId,
      routeIndex: routeIndex ?? currentRouteIndex,
      magnetUri: lastMagnetUri.isNotEmpty ? lastMagnetUri : null,
    );
  }

  /// 切换详情（同一 [State] 复用时）停止播放并清空当前集，避免上一部片子残留。
  Future<void> resetPlaybackForNewDetail() async {
    await playerService.stop();
    await torrentService.stop();
    currentPlayUrl = null;
    isPlaying = false;
    currentEpisodeIndex = 0;
    currentRouteIndex = 0;
    pendingResumePosition = null;
    resumeTargetRouteIndex = null;
    resumeTargetEpisodeIndex = null;
    showReplayOverlay = false;
    position = Duration.zero;
    duration = Duration.zero;
    isBuffering = false;
    isOpeningMedia = false;
    cacheSpeed = 0;
    _throughputEstimator.reset();
    audioBitrateBps = null;
    videoWidth = null;
    videoHeight = null;
    currentSubtitleText = '';
    playerErrorMessage = '';
    playbackErrorType = PlaybackErrorType.none;
    retryCount = 0;
    torrentStep = 0;
    torrentMessage = '';
    lastMagnetUri = '';
  }

  /// 释放资源
  void dispose() {
    // 取消定时器
    hideTimer?.cancel();
    playPauseIndicatorTimer?.cancel();
    seekBubbleTimer?.cancel();
    gestureBarTimer?.cancel();
    gestureHintTimer?.cancel();
    progressPersistTimer?.cancel();

    // 停止磁力流服务
    torrentService.stop();

    // 释放播放器
    playerService.dispose();
  }
}
