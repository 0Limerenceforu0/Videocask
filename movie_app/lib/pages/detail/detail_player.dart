import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
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

import 'playback/playback_lifecycle.dart';
import 'playback/detail_playback_coordinator.dart';
import 'playback/playhead_authority.dart';
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

  /// 「距最近一次 open 媒体已等待秒数」轻量计时器；详情页缓冲 overlay 监听。
  late final OpenElapsedTicker _openElapsedTicker;

  DetailPlayer() {
    _openElapsedTicker = OpenElapsedTicker(openElapsedSeconds);
    playback.session.lifecycleNotifier.addListener(_onLifecycleChanged);
  }

  void _onLifecycleChanged() {
    if (playback.session.lifecycle == PlaybackLifecycle.opening) {
      _openElapsedTicker.start();
    } else {
      _openElapsedTicker.stop();
    }
    // 同步给 UI 用的 notifier
    playerLifecycleNotifier.value = playback.session.lifecycle;
  }

  void disposeLifecycleListener() {
    playback.session.lifecycleNotifier.removeListener(_onLifecycleChanged);
    _openElapsedTicker.stop();
  }

  // ========== 播放器状态 ==========

  /// 播放协调器：进度权威 + 生命周期 + open 策略（详情页唯一入口）。
  final DetailPlaybackCoordinator playback = DetailPlaybackCoordinator();

  /// 播放器生命周期变化通知（UI 可监听显示不同文案/进度）。
  final ValueNotifier<PlaybackLifecycle> playerLifecycleNotifier =
      ValueNotifier(PlaybackLifecycle.idle);

  /// 距最近一次「开始打开媒体」已等待秒数（用于缓冲 overlay 显示「已等待 Xs」）。
  final ValueNotifier<double> openElapsedSeconds = ValueNotifier(0.0);

  /// 是否正在缓冲
  bool isBuffering = false;

  /// 正在打开媒体（解析完成到 player.open 结束之间，避免「点了没反应」）
  bool get isOpeningMedia => playback.lifecycle == PlaybackLifecycle.opening;

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
  int videoRotate = 0;

  /// 当前播放位置（UI 展示；真相源为 [playback.authoritativePosition]）。
  Duration position = Duration.zero;

  /// 兼容旧引用：等同 [playback.authoritativePosition]。
  Duration get peakPlaybackPosition => playback.authoritativePosition;

  /// 视频总时长
  Duration duration = Duration.zero;

  /// 当前播放的URL
  String? currentPlayUrl;

  /// mpv 实际打开的媒体地址（解析后 / 磁力流 / 本地 file），供 DLNA 等使用。
  String? activeStreamUrl;

  /// mpv 实际 open 的地址（可能是本地去广告代理地址），重试/重播时优先使用。
  String? currentOpenUrl;

  /// 当前播放集数索引
  int currentEpisodeIndex = 0;

  /// 当前播放线路索引（写入历史）
  int currentRouteIndex = 0;

  /// 本集打开后待恢复进度（仅当与历史线路/集一致时生效）
  Duration? pendingResumePosition;

  /// 与 [pendingResumePosition] 对应的历史线路、集（用于判断是否续播）
  int? resumeTargetRouteIndex;
  int? resumeTargetEpisodeIndex;

  /// 续播 seek 进行中（避免 position=0 落盘覆盖历史）
  bool isApplyingResume = false;

  /// 本次 open 是否已在 [PlayerService.play] 中传入 startAt
  bool _resumeStartHandled = false;

  /// 避免 [onDurationChanged] 多次触发 [_applyPendingResume]。
  bool _pendingResumeConsumed = false;

  /// 续播目标（seek 完成前忽略 mpv 上报的 0 位置，防止 UI 跳回开头）
  Duration? _resumeSeekTarget;

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

  /// 片源分辨率就绪（用于竖屏布局与全屏方向）
  void Function(int width, int height)? onVideoDimensionsChanged;

  /// 当前集播放自然结束（非切集）
  VoidCallback? onPlaybackEnded;

  /// 缓冲状态变化（供详情页做自动线路回退等）
  void Function(bool buffering)? onBufferingChangedUi;

  /// 播放进度（用于下一集预加载等）
  void Function(Duration position, Duration duration)? onPlaybackProgress;

  int _lastUiNotifyMs = 0;

  static const int _uiNotifyMinIntervalMs = 200;

  /// 竖滑手势起始是否在左半屏（亮度）；由 [DetailPage] 在 dragStart 写入
  bool verticalGestureIsLeftSide = false;

  void _notifyUiThrottled() {
    if (_disposing) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastUiNotifyMs < _uiNotifyMinIntervalMs) return;
    _lastUiNotifyMs = now;
    onUiChanged?.call();
  }

  void _notifyUiImmediate() {
    if (_disposing) return;
    _lastUiNotifyMs = DateTime.now().millisecondsSinceEpoch;
    onUiChanged?.call();
  }

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

  /// 磁力当前播放的视频文件名（release 名），用于字幕精准匹配。
  ///
  /// 形如 `Show.S01E02.1080p.WEB-DL`，比片名更容易命中同名资源字幕。
  String currentMagnetFileName = '';

  /// 当前外挂字幕的时间轴偏移（秒），正数表示字幕延后出现。
  double subtitleDelaySeconds = 0;

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

  /// 锁屏时侧边解锁按钮是否显示（可自动隐藏）
  bool showLockChrome = true;

  /// 锁屏控件自动隐藏定时器
  Timer? lockChromeHideTimer;

  /// 自动连播开关
  bool isAutoPlayNext = true;

  // ========== 磁力缓存状态 ==========

  /// 磁力 P2P 边下边播准备中（解析元数据 / 缓冲等）
  bool magnetSourcePreparing = false;

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

  Future<void>? _initializeFuture;

  bool _disposing = false;

  Timer? _discontinuityRecoveryTimer;
  DateTime? _lastDiscontinuityRecoveryAt;
  bool _discontinuityRecoveryInFlight = false;

  /// 初始化播放器（并发安全，多次调用只会执行一次）
  Future<void> ensureInitialized() {
    return _initializeFuture ??= _setupPlayerCallbacks();
  }

  /// 初始化播放器
  Future<void> initialize() => ensureInitialized();

  Future<void> _setupPlayerCallbacks() async {
    await playerService.init();

    // 监听播放器状态
    playerService.onPositionChanged = (pos) {
      if (_shouldIgnoreResumePositionReport(pos)) return;
      final action = playback.ingestPlayerPosition(pos, duration: duration);
      switch (action) {
        case PlayheadTickAction.accept:
          position = pos;
        case PlayheadTickAction.ignoreBackward:
          break;
        case PlayheadTickAction.discontinuity:
          _scheduleDiscontinuityRecovery();
      }
      position = playback.authoritativePosition;
      final total = duration;
      if (total > Duration.zero) {
        onPlaybackProgress?.call(playback.authoritativePosition, total);
      }
      _notifyUiThrottled();
    };

    playerService.onDurationChanged = (duration) {
      this.duration = duration;
      if (duration > Duration.zero) {
        playback.onOpenSucceeded();
        _applyPendingResume(duration);
      }
      _notifyUiThrottled();
    };

    playerService.onPlayingChanged = (playing) {
      isPlaying = playing;
      if (playing) {
        playback.onOpenSucceeded();
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
      if (w == null || h == null || w <= 0 || h <= 0) return;
      videoWidth = w;
      videoHeight = h;
      videoRotate = playerService.videoRotate;
      onVideoDimensionsChanged?.call(w, h);
      _notifyUiThrottled();
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
      playback.onPlaybackError();
      _notifyUiImmediate();
    };

    playerService.onCompleted = () {
      if (playback.isPrematureComplete(duration)) {
        debugPrint(
          'Ignoring premature completed at '
          '${playback.authoritativePosition.inSeconds}s / ${duration.inSeconds}s',
        );
        unawaited(_recoverFromDiscontinuity(playback.authoritativePosition));
        return;
      }
      isPlaying = false;
      playback.onPlaybackEnded(duration: duration);
      if (duration > Duration.zero) {
        position = playback.authoritativePosition;
      }
      onPlaybackEnded?.call();
      _notifyUiImmediate();
    };

    unawaited(_syncBrightnessFromSystem());
  }

  /// 打开媒体前取走待恢复进度（与线路/集一致时）；返回 null 表示从 0 起播。
  Duration? takePendingResumeStart({
    required int routeIndex,
    required int episodeIndex,
  }) {
    _resumeStartHandled = false;
    _resumeSeekTarget = null;
    final pending = pendingResumePosition;
    if (pending == null || pending <= Duration.zero) return null;
    if (resumeTargetRouteIndex != routeIndex ||
        resumeTargetEpisodeIndex != episodeIndex) {
      return null;
    }
    _resumeStartHandled = true;
    isApplyingResume = true;
    _resumeSeekTarget = pending;
    pendingResumePosition = null;
    _pendingResumeConsumed = true;
    return pending;
  }

  /// 磁力单文件播放：可选校验 [episodeIndex] 与历史集一致后再续播。
  Duration? takeMagnetResumeStart({int? episodeIndex}) {
    _resumeStartHandled = false;
    _resumeSeekTarget = null;
    final pending = pendingResumePosition;
    if (pending == null || pending <= Duration.zero) return null;
    if (episodeIndex != null &&
        resumeTargetEpisodeIndex != null &&
        resumeTargetEpisodeIndex != episodeIndex) {
      return null;
    }
    _resumeStartHandled = true;
    isApplyingResume = true;
    _resumeSeekTarget = pending;
    pendingResumePosition = null;
    _pendingResumeConsumed = true;
    return pending;
  }

  void markResumeStartApplied(Duration target) {
    playback.confirmExplicitPosition(target, duration: duration);
    position = playback.authoritativePosition;
    _resumeSeekTarget = target;
    isApplyingResume = true;
    _pendingResumeConsumed = true;
    _notifyUiThrottled();
    unawaited(_confirmResumeStart(target));
  }

  Future<void> _confirmResumeStart(Duration target) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (_resumeSeekTarget == null) return;
    if ((position - target).inMilliseconds.abs() < 4000 ||
        position >= target - const Duration(seconds: 5)) {
      isApplyingResume = false;
      _resumeSeekTarget = null;
      _clearResumeState();
      _notifyUiThrottled();
      return;
    }
    await _seekToResumePosition(target);
  }

  /// 业务层应使用的播放位置（与落盘、换线一致）。
  Duration get effectivePlaybackPosition => playback.authoritativePosition;

  /// 换线/重试时应 seek 到的进度；接近片尾返回 null。
  Duration? playbackPositionToPreserve() {
    return playback.preserveForRouteSwitch(duration: duration);
  }

  void _scheduleDiscontinuityRecovery() {
    if (isApplyingResume || isOpeningMedia) return;
    final target = playback.authoritativePosition;
    if (target <= const Duration(seconds: 20)) return;

    final now = DateTime.now();
    final last = _lastDiscontinuityRecoveryAt;
    if (last != null && now.difference(last) < const Duration(seconds: 12)) {
      return;
    }

    _discontinuityRecoveryTimer?.cancel();
    _discontinuityRecoveryTimer = Timer(const Duration(milliseconds: 700), () {
      if (_disposing) return;
      if (playback.authoritativePosition > const Duration(seconds: 15) &&
          playback.lastPlayerReport > const Duration(seconds: 15)) {
        return;
      }
      unawaited(_recoverFromDiscontinuity(playback.authoritativePosition));
    });
  }

  Future<void> _recoverFromDiscontinuity(Duration target) async {
    if (_discontinuityRecoveryInFlight || _disposing) return;
    if (target <= const Duration(seconds: 20)) return;
    _discontinuityRecoveryInFlight = true;
    _lastDiscontinuityRecoveryAt = DateTime.now();
    try {
      playback.onSeekStarted();
      await playerService.seekPrecise(target);
      if (_disposing) return;
      playback.confirmExplicitPosition(target, duration: duration);
      position = playback.authoritativePosition;
      playback.onSeekFinished();
      if (!isPlaying) {
        await playerService.resume();
      }
      _notifyUiThrottled();
    } catch (e) {
      debugPrint('discontinuity recovery seek failed: $e');
      playback.onSeekFinished();
    } finally {
      _discontinuityRecoveryInFlight = false;
    }
  }

  bool _shouldIgnoreResumePositionReport(Duration pos) {
    final target = _resumeSeekTarget;
    if (!isApplyingResume || target == null) return false;
    if (target.inMilliseconds <= 5000) return false;
    if (pos.inMilliseconds >= target.inMilliseconds - 4000) {
      isApplyingResume = false;
      _resumeSeekTarget = null;
      _clearResumeState();
      return false;
    }
    if (pos.inMilliseconds < target.inMilliseconds - 5000) {
      return true;
    }
    return false;
  }

  void _applyPendingResume(Duration total) {
    if (_resumeStartHandled || _pendingResumeConsumed) return;
    final pending = pendingResumePosition;
    if (pending == null || total <= Duration.zero) return;
    if (pending >= total - const Duration(seconds: 2)) {
      _clearResumeState();
      _pendingResumeConsumed = true;
      return;
    }
    _pendingResumeConsumed = true;
    unawaited(_seekToResumePosition(pending));
  }

  /// 新开媒体前：由 [DetailPlaybackCoordinator.prepareOpen] 统一处理，此处仅清续播消费标记。
  void resetResumeConsumeForNewOpen({Duration? preservePeak}) {
    _pendingResumeConsumed = false;
    _resumeStartHandled = false;
    _resumeSeekTarget = null;
    if (preservePeak != null && preservePeak > Duration.zero) {
      playback.confirmExplicitPosition(preservePeak, duration: duration);
      position = playback.authoritativePosition;
    }
  }

  void _clearResumeState() {
    pendingResumePosition = null;
    resumeTargetRouteIndex = null;
    resumeTargetEpisodeIndex = null;
  }

  Future<void> _seekToResumePosition(Duration target) async {
    isApplyingResume = true;
    _resumeSeekTarget = target;
    pendingResumePosition = null;
    const maxAttempts = 6;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await playerService.seekPrecise(target);
      await Future<void>.delayed(Duration(milliseconds: 220 + attempt * 180));
      final delta = (position - target).inMilliseconds.abs();
      if (delta < 4000 || position >= target - const Duration(seconds: 5)) {
        playback.confirmExplicitPosition(target, duration: duration);
        position = playback.authoritativePosition;
        isApplyingResume = false;
        _resumeSeekTarget = null;
        _clearResumeState();
        _notifyUiThrottled();
        return;
      }
    }
    isApplyingResume = false;
    _resumeSeekTarget = null;
    _clearResumeState();
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
    activeStreamUrl = url;
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
    playback.onSeekStarted();
    playback.confirmExplicitPosition(position, duration: duration);
    this.position = playback.authoritativePosition;
    await playerService.seek(position);
    playback.onSeekFinished();
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
    if (pendingResumePosition != null || isApplyingResume) return;

    final historyProvider = context.read<HistoryProvider>();
    var episodeName = '第${currentEpisodeIndex + 1}集';
    if (movie.playRoutes.isNotEmpty) {
      final ri = (routeIndex ?? currentRouteIndex)
          .clamp(0, movie.playRoutes.length - 1);
      final eps = movie.playRoutes[ri].episodes;
      if (currentEpisodeIndex >= 0 && currentEpisodeIndex < eps.length) {
        final n = eps[currentEpisodeIndex].name.trim();
        if (n.isNotEmpty) episodeName = n;
      }
    }
    final progressPos = effectivePlaybackPosition;
    await historyProvider.saveOrUpdateHistory(
      movieId: movie.id,
      movieName: movie.name,
      movieCover: movie.cover,
      episodeIndex: currentEpisodeIndex,
      episodeName: episodeName,
      progress: progressPos.inMilliseconds,
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
    activeStreamUrl = null;
    activeStreamUrl = null;
    currentOpenUrl = null;
    isPlaying = false;
    currentEpisodeIndex = 0;
    currentRouteIndex = 0;
    pendingResumePosition = null;
    resumeTargetRouteIndex = null;
    resumeTargetEpisodeIndex = null;
    isApplyingResume = false;
    _resumeStartHandled = false;
    _resumeSeekTarget = null;
    _pendingResumeConsumed = false;
    showReplayOverlay = false;
    position = Duration.zero;
    duration = Duration.zero;
    playback.resetSession();
    isBuffering = false;
    cacheSpeed = 0;
    _throughputEstimator.reset();
    audioBitrateBps = null;
    videoWidth = null;
    videoHeight = null;
    videoRotate = 0;
    currentSubtitleText = '';
    playerErrorMessage = '';
    playbackErrorType = PlaybackErrorType.none;
    retryCount = 0;
    torrentStep = 0;
    torrentMessage = '';
    magnetSourcePreparing = false;
    lastMagnetUri = '';
  }

  /// 离开详情或切页面前停止出声（不释放 [Player] 实例）。
  Future<void> stopActivePlayback() async {
    if (_disposing) return;
    await playerService.stop();
    await torrentService.stop();
    isPlaying = false;
  }

  void _clearPlayerServiceCallbacks() {
    playerService.onPositionChanged = null;
    playerService.onDurationChanged = null;
    playerService.onPlayingChanged = null;
    playerService.onBufferingChanged = null;
    playerService.onBufferChanged = null;
    playerService.onRateChanged = null;
    playerService.onAudioBitrateChanged = null;
    playerService.onVideoSizeChanged = null;
    playerService.onSubtitle = null;
    playerService.onError = null;
    playerService.onCompleted = null;
  }

  /// 释放资源
  void dispose() {
    if (_disposing) return;
    _disposing = true;

    onUiChanged = null;
    onPlaybackEnded = null;
    onBufferingChangedUi = null;
    onPlaybackProgress = null;
    onVideoDimensionsChanged = null;

    hideTimer?.cancel();
    seekBubbleTimer?.cancel();
    gestureBarTimer?.cancel();
    gestureHintTimer?.cancel();
    progressPersistTimer?.cancel();
    lockChromeHideTimer?.cancel();
    _discontinuityRecoveryTimer?.cancel();

    _clearPlayerServiceCallbacks();
    unawaited(_releasePlayerResources());
  }

  Future<void> _releasePlayerResources() async {
    await playerService.stop();
    await torrentService.stop();
    await playerService.dispose();
    _initializeFuture = null;
  }
}

/// 「距最近一次 open 媒体已等待秒数」的轻量计时器。
/// 详情页缓冲 overlay 监听它来展示「已等待 Xs」避免出现「没反应」。
class OpenElapsedTicker {
  OpenElapsedTicker(this._notifier);

  final ValueNotifier<double> _notifier;
  DateTime? _startedAt;
  Timer? _timer;

  void start() {
    _startedAt = DateTime.now();
    _notifier.value = 0.0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final s = _startedAt;
      if (s == null) return;
      _notifier.value = DateTime.now().difference(s).inMilliseconds / 1000.0;
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _startedAt = null;
    _notifier.value = 0.0;
  }
}
