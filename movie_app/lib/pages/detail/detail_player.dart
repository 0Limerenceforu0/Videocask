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
import '../../utils/magnet_episode_parser.dart';
import '../../services/debug_log.dart';
import 'dart:io';
import 'package:flutter/services.dart';

import 'playback/playback_lifecycle.dart';
import 'playback/detail_playback_coordinator.dart';
import 'playback/playhead_authority.dart';
import 'playback/stall_detection.dart';
import 'playback/discontinuity_recovery_policy.dart';
import 'playback_error_type.dart';

/// 纠偏（discontinuity 恢复 seek）连续失败上限：达到即放弃本次 open 的纠偏。
///
/// 断网时 mpv 会把读不到的 HLS 流报成「提前播完」，触发纠偏；而纠偏 seek 在
/// 死流上必然落空，形成每 30s 一次的无效循环（2026-10-21 模拟器实测）。
const int kMaxDiscontinuityRecoveryAttempts = 3;

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

  /// 磁力准备的**细粒度阶段**（2026-10-28 用户要求「告诉我走到哪一步」）。
  ///
  /// 与 [torrentStep] 的分工：[torrentStep] 是给旧逻辑看的粗粒度开关，
  /// 这里是要**逐条打勾显示给用户**的清单，共 6 步：
  /// 1 启动 P2P 引擎 / 2 解析种子元数据 / 3 连接节点 /
  /// 4 选定视频文件 / 5 缓冲首段数据 / 6 交给播放器起播
  ///
  /// 0=未开始，-1=失败。
  int torrentStage = 0;

  /// 当前是第几次尝试（1=首次，2=首次失败后的自动二次尝试）。
  ///
  /// 磁力「连不上直接断开」的观感来自：首次失败后我们只留一句错误，
  /// 用户不知道能不能再等一等。现在首轮失败会自动重来一轮（重新 addMagnet，
  /// 换端口/tracker 重新打洞），并把这个轮次显示出来。
  int torrentAttempt = 1;

  /// 是否正处于「自动二次尝试」窗口（UI 明说第 2 次尝试，而不是继续转圈）。
  bool magnetRetrying = false;

  /// 已把流交给播放器、正在等它出第一帧画面（看门狗窗口）。
  ///
  /// 2026-10-28 真机反馈：「磁力资源这个没有时长的黑屏，一直黑屏，换一个
  /// 资源能播放」。表现是 mpv 已经 open 了流，但既没有时长也没有画面
  /// （0:00 / 0:00），我们这边因为「缓冲 > 0 就算成功」而彻底放手，
  /// 于是永远黑着。这里标记等待窗口，让 UI 明说在等画面，超时则由
  /// [DetailMagnetPlayback] 转成一次失败并自动重试。
  bool magnetWaitingFirstFrame = false;

  /// 上一次磁力失败的原因是「播放器读不出画面」（而不是连不上节点）。
  ///
  /// 错误卡片据此换一句更准确的建议：连不上 → 建议换资源；
  /// 读不出画面 → 可能是封装/编码不被支持，同样建议换资源。
  bool magnetNoFrameFailure = false;

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

  /// 纠偏失败计数与放弃判定（连续失败达上限即停止纠偏，见策略类注释）。
  final DiscontinuityRecoveryPolicy _discontinuityRecovery =
      DiscontinuityRecoveryPolicy(maxAttempts: kMaxDiscontinuityRecoveryAttempts);

  /// 最近一次用户主动 seek 的时刻；刚拖过进度条的一小段时间内禁止「采纳
  /// 实际上报」，否则 mpv 迟到的旧位置报告会把用户刚拖到的进度拽回去。
  DateTime? _lastExplicitSeekAt;

  /// 用户主动 seek 后禁止采纳上报的保护窗口。
  static const Duration kAdoptGuardAfterExplicitSeek = Duration(seconds: 10);
  Timer? _heartbeatTimer;

  /// 初始化播放器（并发安全，多次调用只会执行一次）
  Future<void> ensureInitialized() {
    return _initializeFuture ??= _setupPlayerCallbacks();
  }

  /// 初始化播放器
  Future<void> initialize() => ensureInitialized();

  Future<void> _setupPlayerCallbacks() async {
    await playerService.init();

    // 播放器后端（media_kit/libmpv）原生库已在 Player() 构造时加载，可能注册了它自己的
    // 信号处理器覆盖掉我们的。播放器就绪后重新断言原生崩溃处理器，抢回注册权。
    await _reassertCrashHandler();

    // 监听播放器状态。
    //
    // 订阅的是 **PlayerService 的事件通道**（多播），不是某个 Player 实例的
    // stream —— 播放器实例被回收重建时通道不失效，本页无需重新订阅，
    // 也就不会出现「回收一次，进度永久冻结」。
    playerService.positionChanged.add(_handlePositionChanged);
    playerService.durationChanged.add(_handleDurationChanged);
    playerService.playingChanged.add(_handlePlayingChanged);
    playerService.bufferingChanged.add(_handleBufferingChanged);
    playerService.bufferChanged.add(_handleBufferChanged);
    playerService.rateChanged.add(_handleRateChanged);
    playerService.audioBitrateChanged.add(_handleAudioBitrateChanged);
    playerService.videoSizeChanged.add(_handleVideoSizeChanged);
    playerService.subtitle.add(_handleSubtitleChanged);
    playerService.error.add(_handlePlayerError);
    playerService.completed.add(_handleCompleted);

    playerService.onPlayerRecreated = () {
      _notifyUiImmediate();
    };

    unawaited(_syncBrightnessFromSystem());

    // 心跳：稳态播放不打日志，崩在无 [Crash] 的原生崩溃时无法判断「活了多久」。
    // 每 30s 记一次位置/时长/缓冲，下次崩溃日志末尾的时间戳即可定位存活时长与崩溃点。
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) => _heartbeat());
  }

  void _handlePositionChanged(Duration pos) {
    if (_shouldIgnoreResumePositionReport(pos)) return;
    // seek 期间 mpv 可能报告 seek 前的旧位置，此时若更新 authoritative
    // 会导致 seek 完成后被误判为 discontinuity。因此 seeking 期间直接忽略。
    if (playback.lifecycle == PlaybackLifecycle.seeking) return;
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
  }

  void _handleDurationChanged(Duration duration) {
    this.duration = duration;
    if (duration > Duration.zero) {
      playback.onOpenSucceeded();
      _applyPendingResume(duration);
    }
    _notifyUiThrottled();
  }

  void _handlePlayingChanged(bool playing) {
    isPlaying = playing;
    if (playing) {
      playback.onOpenSucceeded();
    }
    _notifyUiImmediate();
  }

  void _handleBufferingChanged(bool buffering) {
    isBuffering = buffering;
    onBufferingChangedUi?.call(buffering);
    _notifyUiImmediate();
  }

  void _handleBufferChanged(Duration buffer) {
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
  }

  void _handleRateChanged(double rate) {
    playbackSpeed = rate;
    _notifyUiThrottled();
  }

  void _handleAudioBitrateChanged(double? bps) {
    audioBitrateBps = bps;
  }

  void _handleVideoSizeChanged((int?, int?) size) {
    final (w, h) = size;
    if (w == null || h == null || w <= 0 || h <= 0) return;
    videoWidth = w;
    videoHeight = h;
    videoRotate = playerService.videoRotate;
    onVideoDimensionsChanged?.call(w, h);
    _notifyUiThrottled();
  }

  void _handleSubtitleChanged(List<String> lines) {
    currentSubtitleText =
        lines.map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n');
    if (showSubtitles) {
      _notifyUiThrottled();
    }
  }

  /// HLS 开播期 mpv 常报「Cannot seek in this stream」（服务端未声明可 seek）。
  /// 这类错误随后仍会正常起播，标记为致命错误会让生命周期进 error、心跳停摆。
  static bool _isNonFatalSeekError(String error) {
    final e = error.toLowerCase();
    return e.contains('cannot seek') ||
        e.contains('force-seekable') ||
        e.contains('failed to seek');
  }

  void _handlePlayerError(String error) {
    if (_isNonFatalSeekError(error)) {
      // 续播 seek 失败已有 PlaybackStartSeekException 重试路径兜底，这里只记录。
      DebugLog.log('Play', 'player seek 提示(非致命): $error');
      return;
    }
    DebugLog.log('Play', 'player error: $error', flush: true);
    playerErrorMessage = error;
    // 磁力流（currentPlayUrl 是 `magnet-file://<index>`）中途断源时，
    // mpv 只会抛一句底层错误。归类成 magnetFailed，UI 才会给
    // 「自动重试结论 + 建议换源」的磁力卡片，而不是静默黑屏/直接断开。
    final magnetStream = currentPlayUrl != null &&
        MagnetEpisodeParser.isMagnetFileUrl(currentPlayUrl!);
    playbackErrorType = magnetStream
        ? PlaybackErrorType.magnetFailed
        : PlaybackErrorType.networkOrPlayer;
    // mpv 报错后 buffering 流事件可能停留在 true，缓冲遮罩会永久卡在
    // 「Buffering… 已等待 0s」。错误即停止缓冲态，让错误 UI 露出。
    isBuffering = false;
    playback.onPlaybackError();
    _notifyUiImmediate();
  }

  void _handleCompleted(int _) {
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
  }

  void _heartbeat() {
    if (_disposing) return;
    final lc = playback.lifecycle;
    if (lc != PlaybackLifecycle.playing && lc != PlaybackLifecycle.paused) return;
    if (duration <= Duration.zero) return;
    DebugLog.log(
      'Play',
      'heartbeat pos=${position.inSeconds}s dur=${duration.inSeconds}s '
          'buffered=${bufferedPosition.inSeconds}s playing=$isPlaying',
    );
    // 内存诊断：记录进程 RSS 与系统可用内存，崩溃日志可据此判断是否被系统低内存(LMK)杀死。
    _logMemory();
    // 记录**实际生效**的渲染后端 / 硬解档位。
    // 2026-10-22 教训：删掉「自动换后端」机制时把这条记录也一起删没了，
    // 于是出事时根本看不出当时用的哪个 vo —— 现在接回 probeVideoOutput()，
    // 它会写日志 + 刷新 `last_vo.txt`（原生崩溃文件会附带）。
    unawaited(playerService.probeVideoOutput());
    // 帧率：与 [Res] 采样同一心跳，便于比对「泄漏 fd/s ≈ 送显帧率」
    // （验证每送显一帧是否漏一个 fd，2026-10-23 fd 泄漏排查）。
    unawaited(playerService.probeFrameRate());
    // 存活标记：每次心跳刷新时间戳，供下次启动推断「是否正常退出」。
    _writeAliveMarker();
  }

  static const MethodChannel _crashChannel = MethodChannel('guanzi/crash');
  bool _crashHandlerReasserted = false;

  /// 播放器后端（media_kit/libmpv）初始化后重新断言原生崩溃处理器，抢回注册权。
  Future<void> _reassertCrashHandler() async {
    if (_crashHandlerReasserted) return;
    _crashHandlerReasserted = true;
    try {
      await _crashChannel.invokeMethod<void>('reassert');
      DebugLog.log('Crash', 'native crash handler re-asserted after player init', flush: true);
    } catch (_) {
      // 通道未就绪时忽略，下次不再尝试
    }
  }

  /// 内存/fd 诊断采样：每次心跳（30s）记一行，长时间播放后日志即构成
  /// 「RSS 曲线 + fd 曲线」，可用于判断崩溃前是内存增长（LMK/原生 OOM）
  /// 还是 fd 泄漏（epoll 撑满 SIGABRT）。
  ///
  /// - rss：[ProcessInfo.currentRss] 全平台可用（Web 除外）；
  /// - fd：仅 Linux/Android 有 `/proc/self/fd`；
  /// - memAvail：系统可用内存（LMK 判据），同为 /proc 平台。
  void _logMemory() {
    if (kIsWeb) return; // dart:io 在 Web 为抛桩，禁止触达
    try {
      final rssMb = ProcessInfo.currentRss / 1024 / 1024;
      var extra = '';
      try {
        final fdCount = Directory('/proc/self/fd').listSync().length - 2;
        extra += ' fd=$fdCount';
      } catch (_) {}
      try {
        final mi = File('/proc/meminfo').readAsStringSync();
        final avail = mi
            .split('\n')
            .where((l) => l.startsWith('MemAvailable'))
            .join(' ')
            .trim();
        if (avail.isNotEmpty) extra += ' $avail';
      } catch (_) {}
      DebugLog.log('Mem', 'rss=${rssMb.toStringAsFixed(1)}MB$extra');
    } catch (_) {}
  }

  void _writeAliveMarker() {
    try {
      final f = File('${DebugLog.directoryPath}${Platform.pathSeparator}alive_marker.txt');
      f.writeAsStringSync('${DateTime.now().millisecondsSinceEpoch}\n');
    } catch (_) {}
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
    // 用户已主动 seek 到别处时 seek() 会清掉 _resumeSeekTarget：不再纠偏，
    // 避免把用户拖回旧续播点（27→36 分弹回的根因）。
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
    _syncDiscontinuityRecoveryGeneration();
    if (_discontinuityRecovery.disabled) return;
    if (isApplyingResume || isOpeningMedia) {
      DebugLog.log(
        'Playhead',
        'discontinuity 跳过: isApplyingResume=$isApplyingResume '
            'isOpeningMedia=$isOpeningMedia',
      );
      return;
    }
    // 开播 settle 窗口：play(startAt:) 已负责把位置 seek 到续播点，开播前若干秒位置
    // 从 0 爬升是正常现象，误判成 discontinuity 会补发精确 seek，在代理 HLS 上易引发
    // mpv 原生崩溃（实测 v1.0.28 13:09 续播 1758s 崩在此）。窗口内直接跳过纠偏。
    final openedAt = playback.session.openedAt;
    if (openedAt != null &&
        DateTime.now().difference(openedAt) < const Duration(seconds: 20)) {
      DebugLog.log(
        'Playhead',
        'discontinuity 跳过(开播 settle 窗口 20s): '
            'openedAt=${openedAt.toIso8601String()}',
      );
      return;
    }
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
        // 纠偏早退条件：两边都已在有效区间，说明播放器在「正常播放」。
        // 但若两者严重脱节（实测续播点失效：权威 2944s、实际从头 20s），
        // 就不能再纠偏（seek 落空），必须承认播放器实际上报，否则进度条
        // 会永远停在失效的旧续播点上（画面在开头、进度条显示 49:04）。
        final lastSeek = _lastExplicitSeekAt;
        final recentlySought = lastSeek != null &&
            DateTime.now().difference(lastSeek) <
                kAdoptGuardAfterExplicitSeek;
        if (!recentlySought &&
            playback.adoptPlayerPosition(
              playback.lastPlayerReport,
              tolerance: kAuthoritativeDriftTolerance,
            )) {
          DebugLog.log(
            'Playhead',
            '进度权威值与实际上报脱节，已对齐 '
            '权威→${playback.authoritativePosition.inSeconds}s',
            flush: true,
          );
          position = playback.authoritativePosition;
          _notifyUiImmediate();
        }
        return;
      }
      DebugLog.log(
        'Playhead',
        'discontinuity 触发恢复 seek -> target=${target.inSeconds}s',
        flush: true,
      );
      unawaited(_recoverFromDiscontinuity(playback.authoritativePosition));
    });
  }

  Future<void> _recoverFromDiscontinuity(Duration target) async {
    _syncDiscontinuityRecoveryGeneration();
    if (_discontinuityRecovery.disabled) return;
    if (_discontinuityRecoveryInFlight || _disposing) return;
    if (target <= const Duration(seconds: 20)) return;
    // 防抖：任何触发路径（discontinuity tick / premature complete）都受此约束，
    // 避免解码报错等引发「报错→纠偏 seek→再报错」死循环（实测 1 秒内反复 12 次，
    // 拖垮播放器原生层导致闪退）。根因修复见 hls_ad_filter 的 DISCONTINUITY 重建。
    final now = DateTime.now();
    final lastRecovery = _lastDiscontinuityRecoveryAt;
    if (lastRecovery != null &&
        now.difference(lastRecovery) < const Duration(seconds: 8)) {
      return;
    }
    _discontinuityRecoveryInFlight = true;
    _lastDiscontinuityRecoveryAt = DateTime.now();
    DebugLog.log(
      'Playhead',
      'recover seek 执行 target=${target.inSeconds}s',
      flush: true,
    );
    try {
      playback.onSeekStarted();
      await playerService.seekPrecise(target);
      if (_disposing) return;
      // 落位校验：断网时 seek 不抛异常也不生效（流已死），必须等一小段看
      // mpv 实际上报是否真的到了目标附近，否则会一直空转纠偏。
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (_disposing) return;
      final landed = playback.lastPlayerReport;
      if ((landed - target).abs() > const Duration(seconds: 10)) {
        _registerDiscontinuityRecoveryFailure(
          'seek 未落位 target=${target.inSeconds}s 实际=${landed.inSeconds}s',
        );
        playback.onSeekFinished();
        return;
      }
      _discontinuityRecovery.recordSuccess();
      playback.confirmExplicitPosition(target, duration: duration);
      position = playback.authoritativePosition;
      playback.onSeekFinished();
      if (!isPlaying) {
        await playerService.resume();
      }
      _notifyUiThrottled();
    } catch (e) {
      debugPrint('discontinuity recovery seek failed: $e');
      DebugLog.log('Playhead', 'recover seek 失败: $e', flush: true);
      _registerDiscontinuityRecoveryFailure('seek 异常 $e');
      playback.onSeekFinished();
    } finally {
      _discontinuityRecoveryInFlight = false;
    }
  }

  /// 纠偏失败计数；达到上限则放弃纠偏，并把权威进度对齐到播放器实际上报，
  /// 避免进度条永远停在纠偏不过去的位置。
  void _registerDiscontinuityRecoveryFailure(String reason) {
    final giveUp = _discontinuityRecovery.recordFailure();
    DebugLog.log(
      'Playhead',
      '纠偏失败 ${_discontinuityRecovery.failures}/'
      '$kMaxDiscontinuityRecoveryAttempts: $reason',
      flush: true,
    );
    if (!giveUp) return;
    final adopted = playback.adoptPlayerPosition(
      playback.lastPlayerReport,
      tolerance: const Duration(seconds: 10),
    );
    DebugLog.log(
      'Playhead',
      '纠偏连续失败达上限，停止纠偏并对齐实际位置'
      '(adopted=$adopted 实际=${playback.lastPlayerReport.inSeconds}s)',
      flush: true,
    );
  }

  /// 换集/重开媒体后复位纠偏状态（新的一次 open 值得重新尝试纠偏）。
  void _syncDiscontinuityRecoveryGeneration() {
    _discontinuityRecovery.syncGeneration(playback.openGeneration);
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
      // 纠偏期间用户已主动 seek 到别处（seek() 清了 target）：立即停止，
      // 否则会把用户反复拽回旧续播点。
      if (_resumeSeekTarget != target) return;
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

  /// 恢复播放。
  ///
  /// 若处于「缓冲耗尽停滞」（断网耗尽缓冲后 mpv 放弃读流，见 [isStalledExhausted]），
  /// 单纯 `player.play()` 唤不醒——必须按当前进度重新 open 媒体流。
  /// 否则用户表现为「网络恢复后怎么点播放都没反应」。
  Future<void> resume() async {
    if (shouldReloadInsteadOfResume(
      stalled: isStalledExhausted,
      lifecycle: playback.lifecycle,
    )) {
      await reloadStalled();
      return;
    }
    await playerService.resume();
  }

  /// 缓冲耗尽且已停止推进：缓存前沿与播放头贴合、又没有在缓冲中。
  ///
  /// 与「用户主动暂停」的区别：暂停时通常还有未播完的缓存（差值远大于 1.5s）；
  /// 停滞时缓存已用尽且 mpv 不再拉流（`playing=false`、位置不动）。
  bool get isStalledExhausted => isBufferExhaustedStall(
        duration: duration,
        position: playback.lastPlayerReport,
        bufferedPosition: bufferedPosition,
        isPlaying: isPlaying,
        isBuffering: isBuffering,
      );

  /// 停滞软重载：按当前权威进度重新拉流（不跳片头、不丢进度）。
  Future<void> reloadStalled() async {
    final url = currentOpenUrl ?? activeStreamUrl;
    if (url == null || url.isEmpty) {
      await playerService.resume();
      return;
    }
    final at = resolveReloadStartAt(
      authoritative: playback.authoritativePosition,
      reported: playback.lastPlayerReport,
    );
    final plan = playback.prepareOpen(
      isNewEpisode: false,
      explicitPreserve: at,
      knownDuration: duration,
    );
    final generation = plan.generation;
    DebugLog.log(
      'Play',
      '缓冲耗尽停滞 → 软重载 startAt=${at.inSeconds}s',
      flush: true,
    );
    try {
      await playerService.play(url, startAt: plan.startAt);
    } catch (e) {
      if (playback.openGeneration != generation) return;
      DebugLog.log('Play', '软重载 seek 失败，回退从头: $e', flush: true);
      // 续播点拉流失败不能就此卡死：退化为从 0 重开，至少把画面救回来。
      await playerService.play(url);
    }
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    // 用户主动 seek（进度条拖动 / 滑动手势 / 续播自身）：先取消「续播点待确认」
    // 纠偏。否则 900ms 后的 _confirmResumeStart 会把用户的移动误判成「续播未
    // 生效」，反复 seek 回旧续播点——表现为拖回前段立刻被弹回续播点
    // （2026-10-18《爱情公寓》S1E1 27→36 分用户反馈）。
    _cancelPendingResumeConfirm();
    _lastExplicitSeekAt = DateTime.now();
    playback.onSeekStarted();
    playback.confirmExplicitPosition(position, duration: duration);
    this.position = playback.authoritativePosition;
    await playerService.seek(position);
    playback.onSeekFinished();
  }

  /// 取消续播点的延迟确认/纠偏（用户已主动 seek 时调用）。
  void _cancelPendingResumeConfirm() {
    isApplyingResume = false;
    _resumeSeekTarget = null;
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
    torrentStage = 0;
    torrentAttempt = 1;
    magnetRetrying = false;
    magnetSourcePreparing = false;
    magnetWaitingFirstFrame = false;
    magnetNoFrameFailure = false;
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
    // 事件通道是多播：只摘掉本页注册的监听，不影响其它消费者。
    playerService.positionChanged.remove(_handlePositionChanged);
    playerService.durationChanged.remove(_handleDurationChanged);
    playerService.playingChanged.remove(_handlePlayingChanged);
    playerService.bufferingChanged.remove(_handleBufferingChanged);
    playerService.bufferChanged.remove(_handleBufferChanged);
    playerService.rateChanged.remove(_handleRateChanged);
    playerService.audioBitrateChanged.remove(_handleAudioBitrateChanged);
    playerService.videoSizeChanged.remove(_handleVideoSizeChanged);
    playerService.subtitle.remove(_handleSubtitleChanged);
    playerService.error.remove(_handlePlayerError);
    playerService.completed.remove(_handleCompleted);
    playerService.onPlayerRecreated = null;
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
    _heartbeatTimer?.cancel();

    // 必须摘掉 lifecycleNotifier 的监听：监听闭包捕获了本对象，
    // 不摘会让整个详情页对象图（含 coordinator / authority）被 ValueNotifier 持有，
    // 每次进出详情页泄漏一份；若离开时正处于 opening 状态，
    // _openElapsedTicker 的 200ms 定时器还会继续跑。
    disposeLifecycleListener();

    _clearPlayerServiceCallbacks();

    // 释放 notifier 本身（UI 侧通过 ValueListenableBuilder 绑定过）。
    playerLifecycleNotifier.dispose();
    openElapsedSeconds.dispose();
    playback.dispose();

    unawaited(_releasePlayerResources());
  }

  Future<void> _releasePlayerResources() async {
    await playerService.stop();
    await torrentService.stop();
    // 只释放播放器**实例**（mpv 内存/fd）；PlayerService 是单例，
    // 严禁在此 dispose——_disposed 无复位路径，会令后续播放全部静默失败。
    await playerService.releasePlayerInstance();
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
