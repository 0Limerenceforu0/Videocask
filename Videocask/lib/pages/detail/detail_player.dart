import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../services/player_service.dart';
import '../../services/subtitle_render_policy.dart';
import '../../services/subtitle_style_policy.dart';
import '../../services/torrent_player_service.dart';
import '../../models/movie.dart';
import '../../providers/history_provider.dart';
import '../../utils/playback_throughput.dart';
import 'playback/magnet_stream_policy.dart';
import '../../services/debug_log.dart';
import 'dart:io';
import 'package:flutter/services.dart';

import 'playback/playback_lifecycle.dart';
import 'playback/detail_playback_coordinator.dart';
import 'playback/playhead_authority.dart';
import 'playback/stall_detection.dart';
import 'playback/seek_landing_policy.dart';
import 'playback/discontinuity_recovery_policy.dart';
import 'playback/completion_policy.dart';
import 'playback/magnet_failure_dismiss_policy.dart';
import 'playback/magnet_seek_visual_policy.dart';
import 'playback_error_type.dart';
import '../../services/system_volume.dart';
import '../../config/constants.dart';
import '../../services/storage_service.dart';

/// 纠偏（discontinuity 恢复 seek）连续失败上限：达到即放弃本次 open 的纠偏。
///
/// 断网时 mpv 会把读不到的 HLS 流报成「提前播完」，触发纠偏；而纠偏 seek 在
/// 死流上必然落空，形成每 30s 一次的无效循环（2026-10-21 模拟器实测）。
const int kMaxDiscontinuityRecoveryAttempts = 3;

/// 播放器相关逻辑
class DetailPlayer {
  /// 音量 UI 上限：系统音量归一化（0.0–1.0），与系统音量统一。
  static const double maxVolumeUi = 1.0;

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
    _seekWaitTicker = OpenElapsedTicker(seekWaitSeconds);
    playback.session.lifecycleNotifier.addListener(_onLifecycleChanged);
    // 读取上次选择的画面比例模式（铺满/原始），默认原始。
    fitCover = StorageService().getBoolSetting(AppConstants.keyPlayerFitCover);
  }

  void _onLifecycleChanged() {
    if (playback.session.lifecycle == PlaybackLifecycle.opening) {
      _openElapsedTicker.start();
    } else {
      _openElapsedTicker.stop();
    }
    // 同步给 UI 用的 notifier
    playerLifecycleNotifier.value = playback.session.lifecycle;
    _notifyPlaybackActiveChanged();
  }

  /// 播放是否处于「有媒体在跑」的状态（决定自动缓冲挡位要不要每 10 分钟评估）。
  ///
  /// [PlaybackLifecycle.isActive] 已包含 paused：暂停时 demuxer 缓存仍然占着
  /// 内存，此时降档不会伤到体验，反而正是内存最该回收的时候。
  bool get _playbackActive => playback.session.lifecycle.isActive;

  bool _lastPlaybackActive = false;

  void _notifyPlaybackActiveChanged() {
    final active = _playbackActive;
    if (active == _lastPlaybackActive) return;
    _lastPlaybackActive = active;
    onPlaybackActiveChanged?.call(active);
  }

  /// 播放活跃状态变化回调：由详情页接到 SettingsProvider 的自动缓冲挡位定时器。
  void Function(bool active)? onPlaybackActiveChanged;

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
  ///
  /// 写入会同步到 [positionListenable]，并按 [_uiNotifyMinIntervalMs] 节流。
  /// 进度条/时间文本只监听这个 notifier，从而不再因为每 200ms 的位置回调
  /// 重建整个详情页（这是详情页最热的重建源）。
  Duration get position => _position;
  set position(Duration value) {
    _position = value;
    _publishPositionThrottled();
  }

  Duration _position = Duration.zero;

  /// 高频播放位置通知（仅进度条与时间文本消费）。
  final ValueNotifier<Duration> positionListenable =
      ValueNotifier(Duration.zero);

  int _lastPositionPublishMs = 0;

  void _publishPositionThrottled() {
    if (_disposing) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPositionPublishMs < _uiNotifyMinIntervalMs) return;
    _lastPositionPublishMs = now;
    positionListenable.value = _position;
  }

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

  /// 磁力失败态下「连续推进量」与上一次位置回调的位置。
  ///
  /// 见 [MagnetFailureDismissPolicy]：失败判定是看门狗拍的快照，慢种子可能在
  /// 快照之后才真正出画面。只要位置在连续往前推，就说明这次判定是误报。
  Duration _magnetErrorProgress = Duration.zero;
  Duration? _lastMagnetErrorTick;

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

  /// 当前音量（0.0–1.0，系统音量归一化；UI 与手势统一走系统音量）
  double volume = 1.0;

  /// 是否静音（静音走播放器自身增益 0/100，不影响系统音量）
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

  /// 节流窗口内累积的竖向位移（像素）。
  ///
  /// 🔴 之前 [DetailPlayer.gestureThrottleMs] 到期前直接 `return`，把被跳过事件的
  /// `details.delta` 一起丢掉了。真实手指事件 60–120Hz，50ms 窗口只能放行 1/3，
  /// 相当于满程距离从 110px 变成 ~330px，手势明显发木。改为无条件累计、窗口到期
  /// 一次性应用，节流只影响刷新频率、不再吃掉位移。
  double pendingGestureDy = 0;

  /// 竖滑手势进行中（用于避免异步回读系统音量覆盖用户拖动结果）。
  bool verticalGestureActive = false;

  /// 系统音量变化订阅（硬件音量键 / 系统音量面板 → App 内 volume）。
  StreamSubscription<double>? _systemVolumeSub;

  /// 竖滑满程距离（像素）。拖这么远恰好走完 0→1。
  static const double gesturePixelsFullRange = 110;

  void _notifyUiThrottled() {
    if (_disposing) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastUiNotifyMs < _uiNotifyMinIntervalMs) return;
    _lastUiNotifyMs = now;
    // 非位置事件（暂停/缓冲/时长变化）后也要把进度条对齐到最新位置，
    // 否则节流窗口内最后一次位置更新可能被丢掉。
    positionListenable.value = _position;
    onUiChanged?.call();
  }

  void _notifyUiImmediate() {
    if (_disposing) return;
    _lastUiNotifyMs = DateTime.now().millisecondsSinceEpoch;
    positionListenable.value = _position;
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

  /// 是否显示字幕。
  ///
  /// 🔴 收口点。单一渲染源是 mpv（见 `services/subtitle_render_policy.dart`），
  /// 所以开关必须真的写到 mpv 的 `sub-visibility`。历史上这里只是普通字段，
  /// 快捷键和「关闭字幕」弹窗只改了 Flutter 浮层的显示条件 —— mpv 画在视频帧
  /// 里的那一份永远关不掉，也会和浮层叠成两份字幕。
  bool get showSubtitles => _showSubtitles;

  set showSubtitles(bool value) {
    if (_showSubtitles == value) return;
    _showSubtitles = value;
    // 属性写入是异步的，UI 不必等；写失败只影响可见性，不致命。
    unawaited(playerService.syncSubtitleVisibility(value));
  }

  bool _showSubtitles = false;

  /// 字幕由谁渲染：mpv（常态）/ Flutter 浮层（mediacodec_embed、Web 兜底）。
  SubtitleRenderer get subtitleRenderer => resolveSubtitleRenderer(
        mpvCanRenderSubtitle: playerService.mpvCanRenderSubtitle,
      );

  /// 当前字幕文本
  String currentSubtitleText = '';

  /// 字幕文件名称
  String subtitleFileName = '';

  /// 字幕字体大小（浮层兜底路径的历史字段，mpv 路径由样式策略裁决）。
  double subtitleFontSize = 22.0;

  /// 字幕视觉档位：片源同款（默认）/ 放大易读。
  ///
  /// 收口到 [PlayerService.syncSubtitleStyle]，切换后立刻重发 mpv 属性；
  /// 浮层兜底路径读同一个值，保证两条渲染路径观感一致。
  SubtitleStylePreset get subtitleStylePreset =>
      playerService.subtitleStylePreset;

  set subtitleStylePreset(SubtitleStylePreset value) {
    if (playerService.subtitleStylePreset == value) return;
    unawaited(playerService.syncSubtitleStyle(value));
  }

  // 字幕面板只需要这些「无类型泄漏」的入口：detail_page.dart 是宿主库，
  // 不必为了显示档位名再把策略类型 import 进来。
  bool get isBurnedInSubtitleStyle =>
      playerService.subtitleStylePreset == SubtitleStylePreset.burnedIn;

  String get subtitleStyleLabel =>
      subtitleStylePresetLabel(playerService.subtitleStylePreset);

  String get subtitleStyleHint =>
      subtitleStylePresetHint(playerService.subtitleStylePreset);

  /// 在「片源同款 / 放大易读」之间切换，写入即重发 mpv 属性。
  void toggleSubtitleStyle() {
    subtitleStylePreset = isBurnedInSubtitleStyle
        ? SubtitleStylePreset.enlarged
        : SubtitleStylePreset.burnedIn;
  }

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

  /// 画面铺满模式：true=cover（裁切铺满，零黑边）/ false=contain（原始比例，留对称黑边）。
  ///
  /// 默认 contain（保整帧、对称留边，绝不变形/裁切）；用户可在播放器右侧悬浮按钮
  /// 一键切到 cover。选择持久化到 [AppConstants.keyPlayerFitCover]。
  bool fitCover = false;

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

  /// 当前是否处于磁力本地流会话。
  ///
  /// 不再只看 `currentPlayUrl`：4078 真机里它会被覆写成 streamUrl，导致
  /// 90s 看门狗把磁力当成普通 URL 重新 open。纯函数判定见
  /// [isMagnetStreamSession]，三重信号避免漏判 / 误判。
  bool get isMagnetStreamSessionActive => isMagnetStreamSession(
        currentPlayUrl: currentPlayUrl,
        activeStreamUrl: activeStreamUrl,
        hasMagnetSession: lastMagnetUri.isNotEmpty,
      );

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
      DiscontinuityRecoveryPolicy(
          maxAttempts: kMaxDiscontinuityRecoveryAttempts);

  /// 最近一次用户主动 seek 的时刻；刚拖过进度条的一小段时间内禁止「采纳
  /// 实际上报」，否则 mpv 迟到的旧位置报告会把用户刚拖到的进度拽回去。
  DateTime? _lastExplicitSeekAt;

  /// 用户主动 seek 后禁止采纳上报的保护窗口。
  static const Duration kAdoptGuardAfterExplicitSeek = Duration(seconds: 10);

  /// 用户主动暂停后不走「缓冲耗尽停滞」软重载的保护窗口。
  static const Duration kUserPauseStallGuard = Duration(seconds: 10);
  DateTime? _lastUserPauseAt;

  /// 播放/暂停请求的代次：seek 落位期间连点两下时只执行最后一次。
  int _playPauseRequestSeq = 0;

  /// 在途用户 seek 的目标；非空表示 lifecycle 仍应保持 seeking，
  /// 且 mpv 迟到的旧 position 上报必须整条丢弃（见 seek_landing_policy.dart）。
  Duration? _pendingSeekTarget;
  Timer? _seekLandingTimer;
  Completer<void>? _seekLandingCompleter;

  bool get hasSeekLandingPending => _pendingSeekTarget != null;

  /// 磁力 seek 之后「等画面真的出来」的加载态。
  ///
  /// 与 [hasSeekLandingPending] 刻意分开：后者服务进度权威（2.5s 兜底超时
  /// 保证进度条别乱跳），这里服务 UI（磁力按块下载，seek 到未下载片段时
  /// mpv 要阻塞 5~10s，加载提示必须等到出画）。判定见
  /// `playback/magnet_seek_visual_policy.dart`。
  bool magnetSeekVisualPending = false;
  Duration? _magnetSeekVisualTarget;
  Timer? _magnetSeekVisualTimer;
  bool _magnetSeekPolling = false;

  /// 等出画时长的 UI 计数（与 open 的 [openElapsedSeconds] 分开，避免
  /// seek 期间显示上一次开播留下的陈旧「已等待 Ns」）。
  final ValueNotifier<double> seekWaitSeconds = ValueNotifier<double>(0.0);
  late final OpenElapsedTicker _seekWaitTicker;

  /// seek 落位（或超时/失败）后通知 UI 恢复控制栏隐藏计时。
  void Function()? onSeekLandedUi;
  Timer? _heartbeatTimer;

  /// 「提前完成」恢复次数与兜底定时器。
  ///
  /// 2026-11-05 实测：片源声明时长比真实可播内容长（广告段计了 EXTINF、PTS
  /// 不推进），播到真实末端时 `completed` 会比 `duration` 早 50~66 秒到达，
  /// 被 [PlayheadAuthority.isPrematureComplete] 判成「提前完成」。原实现只做
  /// 恢复 seek，而恢复目标本身就在流的尽头 → mpv 直接 idle，此后 16 次 seek
  /// 全部无效，画面定格 34 分钟、自动连播永不触发。必须有次数上限和退路。
  int _prematureRecoveryAttempts = 0;
  Timer? _prematureFallbackTimer;
  Duration? _prematureAnchor;

  /// 卡死看门狗：连续多少次心跳位置不推进即判僵死（30s/次）。
  static const int kStalledHeartbeatsBeforeReload = 3;
  static const int kMaxStallReloadAttempts = 2;
  int _stalledHeartbeats = 0;
  int _stallReloadAttempts = 0;
  bool _stallGiveUpLogged = false;
  Duration? _lastWatchdogPosition;

  /// 磁力流「就地重开 mpv」的次数 / 锚点（不删种子，见 [_reopenMagnetStream]）。
  int _magnetStreamReopens = 0;
  static const int _maxMagnetStreamReopens = 3;
  Duration? _magnetReopenAnchor;

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
    unawaited(syncSystemVolume());
    _listenSystemVolume();

    // 心跳：稳态播放不打日志，崩在无 [Crash] 的原生崩溃时无法判断「活了多久」。
    // 每 30s 记一次位置/时长/缓冲，下次崩溃日志末尾的时间戳即可定位存活时长与崩溃点。
    ensureHeartbeat();
  }

  /// 确保心跳定时器在跑（幂等）。
  ///
  /// 2026-11-08 真机现场：磁力起播后整段日志**一条 heartbeat 都没有**，
  /// 连带「卡死看门狗」也一起失效（它挂在心跳里），画面定格十几分钟无人
  /// 兜底。心跳装载点原本只有 [_setupPlayerCallbacks] 一处，一旦该路径被
  /// 走过一次后页面对象被复用/定时器被取消，就再也不会回来。
  /// 现在起播前显式再装一次，保证「只要在播放，就有心跳 + 有看门狗」。
  void ensureHeartbeat() {
    if (_disposing) {
      DebugLog.log('Play', '心跳装载被跳过: _disposing=true', flush: true);
      return;
    }
    if (_heartbeatTimer?.isActive ?? false) {
      DebugLog.log('Play', '心跳已在运行，无需重装', flush: true);
      return;
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _heartbeat());
    DebugLog.log('Play', '心跳/看门狗定时器已装载', flush: true);
  }

  void _handlePositionChanged(Duration pos) {
    // 在途用户 seek：只认「落在目标附近」的第一条上报，其余都是 seek 前的
    // 旧值，整条丢弃。旧实现在 mpv `seek` 命令一返回就结束 seeking，这些旧值
    // 被 ingest 后会被 PlayheadAuthority 判成回跳 → 纠偏 / 采纳旧值 →
    // 「过一会画面回来，播放位置完全不对」。
    final verdict = classifySeekPosition(
      pendingTarget: _pendingSeekTarget,
      reported: pos,
    );
    if (verdict == SeekPositionVerdict.ignoreStale) return;
    if (verdict == SeekPositionVerdict.landed) _finishSeekLanding();

    if (_shouldIgnoreResumePositionReport(pos)) return;
    // 纠偏恢复 seek 期间（没有 _pendingSeekTarget）仍按旧规则忽略上报。
    if (playback.lifecycle == PlaybackLifecycle.seeking) return;
    // 位置在推进却停在 error：非致命错误（如 codec 提示）后 mpv 已继续播，
    // 把状态拉回 playing，恢复心跳与看门狗。
    if (playback.lifecycle == PlaybackLifecycle.error && pos > Duration.zero) {
      playback.noteProgressWhileErrored();
    }
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
    _trackMagnetFailureRecovery(position);
    // 真的往前走了（越过触发「提前完成」时的位置）就说明恢复成功，计数归零，
    // 否则下一集片尾又会被历史上限挡住。
    final anchor = _prematureAnchor;
    if (anchor != null && position > anchor + const Duration(seconds: 5)) {
      _prematureAnchor = null;
      _prematureRecoveryAttempts = 0;
    }
    // 磁力就地重开之后，位置真的往前走了 30s 以上才认为「救回来了」，
    // 计数归零；否则连续断流会很快耗尽重开额度。
    final reopenAnchor = _magnetReopenAnchor;
    if (reopenAnchor != null &&
        position > reopenAnchor + const Duration(seconds: 30)) {
      _magnetReopenAnchor = null;
      _magnetStreamReopens = 0;
    }
    final total = duration;
    if (total > Duration.zero) {
      onPlaybackProgress?.call(playback.authoritativePosition, total);
    }
    // 不再整页 setState：position 的 setter 已经把新值推给 positionListenable，
    // 只有进度条/时间文本会重建（见 DetailPage 的 ValueListenableBuilder）。
  }

  /// 磁力失败态的自动撤销（见 [MagnetFailureDismissPolicy]）。
  ///
  /// 失败结论由首帧看门狗在看门窗口末尾拍板，而慢种子常常在窗口边沿才刚出
  /// 画面（真机 2026-11-07：卡片挂着、画面正常播）。失败态本身不会自己消失，
  /// 所以这里用「位置是否连续推进」这条唯一可信的证据把它撤掉：
  /// 位置在连续往前走 = 画面是活的 = 刚才那条失败结论是误报。
  ///
  /// 只在磁力失败态下累计；seek 跳变与回退都会把计数清零（拖进度条不是播放）。
  void _trackMagnetFailureRecovery(Duration pos) {
    if (playbackErrorType != PlaybackErrorType.magnetFailed) {
      _magnetErrorProgress = Duration.zero;
      _lastMagnetErrorTick = null;
      return;
    }
    final previous = _lastMagnetErrorTick ?? pos;
    _lastMagnetErrorTick = pos;
    _magnetErrorProgress = MagnetFailureDismissPolicy.accumulate(
      accumulated: _magnetErrorProgress,
      previousPosition: previous,
      currentPosition: pos,
    );
    if (!MagnetFailureDismissPolicy.shouldDismiss(
      magnetFailed: true,
      accumulated: _magnetErrorProgress,
    )) {
      return;
    }
    DebugLog.log(
      'Magnet',
      '失败态自愈: 位置连续推进 ${_magnetErrorProgress.inMilliseconds}ms '
          '→ 撤销「磁力播放失败」卡片',
      flush: true,
    );
    _dismissMagnetFailure();
  }

  /// 撤销磁力失败态，把播放器状态拉回「正常播放」。
  ///
  /// 只清失败相关的 UI 状态：不碰片源/路由、不重新 open、不动进度，
  /// 避免把一次明明正常的播放打断。
  void _dismissMagnetFailure() {
    playbackErrorType = PlaybackErrorType.none;
    playerErrorMessage = '';
    magnetNoFrameFailure = false;
    magnetWaitingFirstFrame = false;
    magnetSourcePreparing = false;
    magnetRetrying = false;
    torrentStep = 0;
    torrentStage = 0;
    torrentMessage = '';
    retryCount = 0;
    _magnetErrorProgress = Duration.zero;
    _lastMagnetErrorTick = null;
    _notifyUiImmediate();
  }

  void _handleDurationChanged(Duration duration) {
    final changedShow = this.duration > Duration.zero &&
        (this.duration - duration).abs() > const Duration(seconds: 5);
    this.duration = duration;
    if (changedShow) {
      // 换集/换源：上一集的片尾恢复计数不能带到下一集。
      _prematureRecoveryAttempts = 0;
      _prematureAnchor = null;
      _stalledHeartbeats = 0;
      _stallReloadAttempts = 0;
      _stallGiveUpLogged = false;
      _lastWatchdogPosition = null;
    }
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
    // 字幕已由 mpv/libass 画进视频帧（单一渲染源），浮层不显示时这段文本
    // 没有任何 UI 消费它 —— 再触发重绘就是每 220ms 一次的空转。
    // 只有浮层兜底模式（mediacodec_embed / Web）才需要刷新。
    if (showSubtitles &&
        subtitleRenderer == SubtitleRenderer.flutterOverlay) {
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

  /// codec 打开失败不是终态错误。
  ///
  /// ffmpeg 打不开某个解码器（典型是硬解不可用、或音轨编码不被支持）时，
  /// mpv 会先抛 `Could not open codec.`，随后回退到软解/其它轨道继续播。
  /// 实测 04:10 与 09:51 两次都是「报了错、画面正常、位置正常推进」。
  ///
  /// 之所以必须单独识别：一旦走 _handlePlayerError 的常规分支，
  /// `playback.onPlaybackError()` 会把 lifecycle 钉在 error，而心跳只认
  /// playing/paused —— 整段日志一条心跳都没有，后面所有排查都失明。
  /// 如果这次真的打不开（黑屏无位置推进），停滞看门狗会在 90 秒后接管。
  static bool _isNonFatalCodecError(String error) {
    final e = error.toLowerCase();
    return e.contains('could not open codec') ||
        e.contains('could not open audio codec') ||
        e.contains('could not open video codec');
  }

  void _handlePlayerError(String error) {
    if (_isNonFatalSeekError(error)) {
      // 续播 seek 失败已有 PlaybackStartSeekException 重试路径兜底，这里只记录。
      DebugLog.log('Play', 'player seek 提示(非致命): $error');
      return;
    }
    if (_isNonFatalCodecError(error)) {
      // 只记日志，不置 error 态：mpv 通常已经回退继续播。
      // 真黑屏的话位置不会推进，90 秒后停滞看门狗会软重载。
      DebugLog.log('Play', 'player codec 提示(非致命，继续观察): $error', flush: true);
      return;
    }
    DebugLog.log('Play', 'player error: $error', flush: true);
    playerErrorMessage = error;
    // 磁力流（currentPlayUrl 是 `magnet-file://<index>`）中途断源时，
    // mpv 只会抛一句底层错误。归类成 magnetFailed，UI 才会给
    // 「自动重试结论 + 建议换源」的磁力卡片，而不是静默黑屏/直接断开。
    final magnetStream = isMagnetStreamSessionActive;
    playbackErrorType = magnetStream
        ? PlaybackErrorType.magnetFailed
        : PlaybackErrorType.networkOrPlayer;
    // mpv 报错后 buffering 流事件可能停留在 true，缓冲遮罩会永久卡在
    // 「Buffering… 已等待 0s」。错误即停止缓冲态，让错误 UI 露出。
    isBuffering = false;
    // 报错了就别再挂着「正在缓冲」的加载提示，让错误卡片露出来。
    _finishMagnetSeekVisual();
    playback.onPlaybackError();
    _notifyUiImmediate();
  }

  void _handleCompleted(int _) {
    // 🔴 4078 真机：磁力本地流等 piece 时 mpv 会误报 completed（pos≈7s /
    // dur=7507s）。旧链路直接 _finishPlayback → lifecycle=ended、心跳被吞、
    // 权威进度被设成片长，随后纠偏把片长当目标 seek 到片尾，播放彻底死掉。
    if (shouldIgnoreMagnetPrematureComplete(
      isMagnet: isMagnetStreamSessionActive,
      position: playback.lastPlayerReport,
      duration: duration,
    )) {
      DebugLog.log(
        'Play',
        '磁力流误报完成: pos=${playback.lastPlayerReport.inSeconds}s '
        'dur=${duration.inSeconds}s buffered=${bufferedPosition.inSeconds}s '
        '→ 不进 ended，保持等待供数',
        flush: true,
      );
      // 关键补充（2026-11-08）：EOF 之后 mpv **不会**自己续读，必须换一个
      // 解复用器。这里就地重开（不删种子），从断点接着播。
      if (_canReopenMagnetStream) {
        unawaited(_reopenMagnetStream('EOFMisreport'));
        return;
      }
      isBuffering = true;
      _notifyUiImmediate();
      return;
    }
    if (playback.isPrematureComplete(duration)) {
      final action = resolvePrematureCompletion(
        recoveryAttempts: _prematureRecoveryAttempts,
      );
      if (action == CompletionAction.recover) {
        _prematureRecoveryAttempts++;
        _prematureAnchor = playback.authoritativePosition;
        DebugLog.log(
          'Play',
          '提前完成 pos=${playback.authoritativePosition.inSeconds}s '
              'dur=${duration.inSeconds}s buffered=${bufferedPosition.inSeconds}s '
              '→ 第 $_prematureRecoveryAttempts 次恢复 seek',
          flush: true,
        );
        unawaited(_recoverFromDiscontinuity(playback.authoritativePosition));
        _armPrematureFallback();
        return;
      }
      // 恢复用尽仍然「提前完成」：这就是片源时长虚标，不是流被截断。
      // 继续 seek 只会永远停在流的尽头，必须按本集结束，让自动连播接上。
      DebugLog.log(
        'Play',
        '提前完成且恢复已用尽（pos=${playback.authoritativePosition.inSeconds}s '
            'dur=${duration.inSeconds}s buffered=${bufferedPosition.inSeconds}s）'
            ' → 按本集结束',
        flush: true,
      );
    }
    _finishPlayback();
  }

  /// 本集播放结束：落状态 + 通知上层（自动连播/显示重播）。
  void _finishPlayback() {
    _prematureFallbackTimer?.cancel();
    _prematureFallbackTimer = null;
    isPlaying = false;
    playback.onPlaybackEnded(duration: duration);
    if (duration > Duration.zero) {
      position = playback.authoritativePosition;
    }
    onPlaybackEnded?.call();
    _notifyUiImmediate();
  }

  /// 恢复 seek 之后的位置验证：观察窗结束时位置没往前走，就说明 seek 落在了
  /// 流的尽头（恢复无效），按结束处理，绝不允许停在「completed 已发、却没有后续」的死角。
  void _armPrematureFallback() {
    _prematureFallbackTimer?.cancel();
    final anchor = playback.authoritativePosition;
    _prematureFallbackTimer = Timer(kPrematureRecoveryVerifyWindow, () {
      if (_disposing) return;
      if (didPlayheadAdvance(
        anchor: anchor,
        current: playback.authoritativePosition,
      )) {
        return;
      }
      DebugLog.log(
        'Play',
        '恢复 seek 后 ${kPrematureRecoveryVerifyWindow.inSeconds}s '
            '位置未推进（仍停在 ${anchor.inSeconds}s）→ 按本集结束',
        flush: true,
      );
      _finishPlayback();
    });
  }

  void _heartbeat() {
    if (_disposing) return;
    final lc = playback.lifecycle;
    // 看门狗必须跑在生命周期过滤之前：2026-11-05 的僵死现场 lifecycle 一直没
    // 进 playing（心跳全被下面这行吞掉），只看 playing/paused 就永远发现不了。
    if (duration > Duration.zero) _checkStallWatchdog(lc);
    // 只跳过 idle/ended：opening/seeking/error 也必须留心跳。
    // 2026-11-05 事故——`Could not open codec.` 后 lifecycle 停在 opening/error，
    // 心跳被这行全部吞掉，整段日志没有任何位置记录，无法判断是「卡死」还是
    // 「其实在播」；用户看到的画面明明在动，我们的诊断却是全黑。
    if (lc == PlaybackLifecycle.idle || lc == PlaybackLifecycle.ended) return;
    DebugLog.log(
      'Play',
      // 毫秒级位置：磁力「每 5 分钟才走 40ms」这种极慢爬行，用整秒看不出
      // 是否真的在动，会被误判成「完全冻结」。
      'heartbeat pos=${position.inMilliseconds}ms '
          'dur=${duration.inSeconds}s '
          'buffered=${bufferedPosition.inSeconds}s playing=$isPlaying '
          'rate=${playbackSpeed.toStringAsFixed(2)} lc=${lc.name}',
      flush: true,
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
    // 缓存/预读真实状态：排查「缓冲永远贴着播放位置」。
    unawaited(playerService.probeCacheState());
    // 实际播放速率：与心跳里的 rate= 对照，确认 mpv 实例真的是 1.0x。
    unawaited(playerService.probePlaybackRate());
    // 存活标记：每次心跳刷新时间戳，供下次启动推断「是否正常退出」。
    _writeAliveMarker();
  }

  /// 卡死看门狗：`playing=true` 但位置长时间不推进 = 播放器僵死。
  ///
  /// 2026-11-03 的日志里有 4 次位置定格（7 / 8 / 31 / 24 分钟），全是缓冲耗尽后
  /// mpv 放弃读流、又不发 error：`isBufferExhaustedStall` 首行 `if (isPlaying)
  /// return false` 把它们全部排除，而 `reloadStalled()` 只在用户手动点播放时才
  /// 触发 —— 用户不点，画面就一直黑着。这里补上自动兜底。
  ///
  /// 只数 **mpv 真的在播** 的心跳：暂停 / 主动 seek 中都不算僵死。
  /// 注意不能只信 `lifecycle == playing` —— 2026-11-05 的事故里 lifecycle
  /// 从 open 之后就没进过 playing，靠它判断会漏掉整整 34 分钟。
  void _checkStallWatchdog(PlaybackLifecycle lc) {
    // 已经判结束/还没开始：再反复软重载只会把状态越推越坏（4078 真机
    // ended 之后每 90s 一次「软重载」，位置永远停在片长）。看门狗只服务
    // opening/playing/seeking/error 这些「本该在播」的状态。
    if (lc == PlaybackLifecycle.ended || lc == PlaybackLifecycle.idle) {
      _stalledHeartbeats = 0;
      _lastWatchdogPosition = null;
      return;
    }
    if (!isPlaying || lc == PlaybackLifecycle.seeking) {
      _stalledHeartbeats = 0;
      _lastWatchdogPosition = null;
      return;
    }
    final pos = position;
    final prev = _lastWatchdogPosition;
    if (prev == null || pos > prev + const Duration(seconds: 1)) {
      _stalledHeartbeats = 0;
      _stallReloadAttempts = 0;
      _stallGiveUpLogged = false;
    } else {
      _stalledHeartbeats++;
    }
    _lastWatchdogPosition = pos;
    if (_stalledHeartbeats < kStalledHeartbeatsBeforeReload) return;
    if (_stallReloadAttempts >= kMaxStallReloadAttempts) {
      if (!_stallGiveUpLogged) {
        _stallGiveUpLogged = true;
        DebugLog.log(
          'Play',
          '位置连续 ${_stalledHeartbeats * 30}s 未推进，软重载已用尽，停止自动恢复',
          flush: true,
        );
      }
      return;
    }
    _stallReloadAttempts++;
    _stalledHeartbeats = 0;
    DebugLog.log(
      'Play',
      '位置定格 ${kStalledHeartbeatsBeforeReload * 30}s 未推进'
          '（pos=${pos.inSeconds}s buffered=${bufferedPosition.inSeconds}s）'
          ' → 第 $_stallReloadAttempts 次软重载',
      flush: true,
    );
    unawaited(reloadStalled());
  }

  static const MethodChannel _crashChannel = MethodChannel('videocask/crash');
  bool _crashHandlerReasserted = false;

  /// 播放器后端（media_kit/libmpv）初始化后重新断言原生崩溃处理器，抢回注册权。
  Future<void> _reassertCrashHandler() async {
    if (_crashHandlerReasserted) return;
    _crashHandlerReasserted = true;
    try {
      await _crashChannel.invokeMethod<void>('reassert');
      DebugLog.log(
          'Crash', 'native crash handler re-asserted after player init',
          flush: true);
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
      final f = File(
          '${DebugLog.directoryPath}${Platform.pathSeparator}alive_marker.txt');
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
    // 磁力本地流不支持可靠的随机 seek：补发精确 seek 会打断顺序预取，
    // 而且目标 piece 没下下来时 seek 落空，只会把僵死变成更深的僵死。
    if (isMagnetStreamSessionActive) {
      DebugLog.log(
        'Playhead',
        'discontinuity 跳过(磁力本地流不补发 seek)',
        flush: true,
      );
      return;
    }
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
    if (!isValidRecoverySeekTarget(target: target, duration: duration)) {
      DebugLog.log(
        'Playhead',
        'discontinuity 跳过(目标非法): target=${target.inSeconds}s '
            'dur=${duration.inSeconds}s',
        flush: true,
      );
      return;
    }

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
            DateTime.now().difference(lastSeek) < kAdoptGuardAfterExplicitSeek;
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
      // 用排程时捕获的 target：700ms 后 authoritativePosition 可能已被
      // completed 推到片长，拿实时值 seek 会直接跳到片尾（4078 真机）。
      unawaited(_recoverFromDiscontinuity(target));
    });
  }

  /// 换集/换片前作废「上一集遗留」的在途恢复动作。
  ///
  /// 两类定时器都属于**旧媒体**，跨集必须清：
  /// - `_discontinuityRecoveryTimer`：2026-11-05 实测旧集的纠偏预约在新集 open
  ///   之后才 fire，于是对新集补发一次精确 seek（目标还是旧集进度），表现为
  ///   换集后进度莫名 +55/+47/+39s；
  /// - `_prematureFallbackTimer`：它用「位置有没有越过 anchor」判断恢复是否成功，
  ///   换集后位置归零必然判失败 → 直接把新集按「结束」处理，触发自动连播跳集。
  ///
  /// 同时清掉 12s 纠偏冷却：那是旧集留下的，不该拖住新集的恢复。
  void cancelPendingRecovery() {
    _discontinuityRecoveryTimer?.cancel();
    _discontinuityRecoveryTimer = null;
    _prematureFallbackTimer?.cancel();
    _prematureFallbackTimer = null;
    _lastDiscontinuityRecoveryAt = null;
    // 上一片的「在途 seek / 用户暂停」不能带进新的一次 open。
    _clearSeekLanding();
    _lastUserPauseAt = null;
    _lastExplicitSeekAt = null;
  }

  Future<void> _recoverFromDiscontinuity(Duration target) async {
    _syncDiscontinuityRecoveryGeneration();
    if (_discontinuityRecovery.disabled) return;
    if (_discontinuityRecoveryInFlight || _disposing) return;
    if (isMagnetStreamSessionActive) return;
    if (!isValidRecoverySeekTarget(target: target, duration: duration)) {
      DebugLog.log(
        'Playhead',
        'recover seek 拒绝(目标非法): target=${target.inSeconds}s '
            'dur=${duration.inSeconds}s',
        flush: true,
      );
      return;
    }
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
    // 在途 seek 必须绑定发起时的 open 代次：seekPrecise 与后面 1.2s 落位校验
    // 都是 async 的，期间用户完全可能换集。代次变了就立刻放弃，
    // 否则会拿旧集的目标位置去 pace 新集（实测 +55/+47/+39s 偏移就是这么来的）。
    final generation = playback.openGeneration;
    DebugLog.log(
      'Playhead',
      'recover seek 执行 target=${target.inSeconds}s gen=$generation',
      flush: true,
    );
    try {
      playback.onSeekStarted();
      await playerService.seekPrecise(target);
      if (_disposing || playback.openGeneration != generation) {
        if (!_disposing) {
          DebugLog.log(
            'Playhead',
            'recover seek 已作废：open 代次变化 '
                '$generation→${playback.openGeneration}',
            flush: true,
          );
        }
        return;
      }
      // 落位校验：断网时 seek 不抛异常也不生效（流已死），必须等一小段看
      // mpv 实际上报是否真的到了目标附近，否则会一直空转纠偏。
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (_disposing || playback.openGeneration != generation) return;
      final landed = playback.lastPlayerReport;
      if ((landed - target).abs() > const Duration(seconds: 10)) {
        _registerDiscontinuityRecoveryFailure(
          'seek 未落位 target=${target.inSeconds}s 实际=${landed.inSeconds}s',
        );
        playback.onSeekFinished(playing: isPlaying);
        return;
      }
      _discontinuityRecovery.recordSuccess();
      playback.confirmExplicitPosition(target, duration: duration);
      position = playback.authoritativePosition;
      playback.onSeekFinished(playing: isPlaying);
      if (!isPlaying) {
        await playerService.resume();
      }
      _notifyUiThrottled();
    } catch (e) {
      debugPrint('discontinuity recovery seek failed: $e');
      DebugLog.log('Playhead', 'recover seek 失败: $e', flush: true);
      // 换集导致的失败不算「旧媒体纠偏失败」，别把失败计数带给新集。
      if (playback.openGeneration != generation) return;
      _registerDiscontinuityRecoveryFailure('seek 异常 $e');
      playback.onSeekFinished(playing: isPlaying);
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
    // 🔴 2026-11-08 真机定案：磁力流起播后 seek 会打断顺序预取，目标位置
    // 一个 piece 都没有 → buffered=3s 永久定格（00:37:52 `Jump 0ms ->
    // 3345954ms`）。只挡 >30s 的远端续播不够：4078 真机 3s 的小续播同样
    // 让 mpv 对本地 HTTP 流发起 Range 请求，位置推进到 7s 后定格。
    // 磁力流续播一律暂缓、从头播；用户想跳历史位置自己拖进度条即可，
    // 那时目标 piece 会按需拉取。
    final magnetStream = isMagnetStreamSessionActive;
    if (shouldSkipResumeSeek(isMagnet: magnetStream, pending: pending)) {
      DebugLog.log(
        'Play',
        '磁力续播暂缓: target=${pending.inSeconds}s '
        'buffered=${bufferedPosition.inSeconds}s'
        '（任何起播 seek 都会打断顺序预取，改从头播）',
        flush: true,
      );
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

  /// 暂停播放。
  ///
  /// 若用户刚点了进度条、mpv 还在向未缓冲位置 seek，直接 pause 会让播放停在
  /// 一个还没有解码帧的位置 → 全屏黑底透出。这里先等落位（最多 2.5s）再暂停，
  /// 同时立刻把 UI 的播放态翻成暂停，用户不会觉得按键没反应。
  Future<void> pause() async {
    final seq = ++_playPauseRequestSeq;
    _lastUserPauseAt = DateTime.now();
    isPlaying = false;
    _notifyUiImmediate();
    await _awaitSeekLanding();
    if (seq != _playPauseRequestSeq || _disposing) return;
    await playerService.pause();
  }

  /// 恢复播放。
  ///
  /// 若处于「缓冲耗尽停滞」（断网耗尽缓冲后 mpv 放弃读流，见 [isStalledExhausted]），
  /// 单纯 `player.play()` 唤不醒——必须按当前进度重新 open 媒体流。
  /// 否则用户表现为「网络恢复后怎么点播放都没反应」。
  Future<void> resume() async {
    final seq = ++_playPauseRequestSeq;
    await _awaitSeekLanding();
    if (seq != _playPauseRequestSeq || _disposing) return;
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
  /// 🔴 但「seek 到未缓冲点后用户主动暂停」缓存本来就贴合，旧判据会误判，
  /// 因此额外豁免：在途 seek、以及用户刚主动暂停的保护窗口内都不算停滞。
  bool get isStalledExhausted {
    if (_pendingSeekTarget != null) return false;
    return isBufferExhaustedStall(
      duration: duration,
      position: playback.lastPlayerReport,
      bufferedPosition: bufferedPosition,
      isPlaying: isPlaying,
      isBuffering: isBuffering,
      // 看门狗每 30s 采样一次位置：`_stalledHeartbeats > 0` 表示上一次采样
      // 位置没有推进（mpv 会把 playing 一直报成 true 却定格不动）。
      advancing: _stalledHeartbeats == 0,
      userPaused: _isUserPausedRecently(),
    );
  }

  /// 磁力流「就地重开」：丢掉当前 mpv 解复用器，从断点重新拉同一条本地流。
  ///
  /// 为什么必须重开而不能只「等供数」：
  /// mpv 的 demuxer 一旦读到 EOF 就永久停在 EOF 态（`eof-reached=yes`），
  /// 即使本地流服务器随后又有数据，它也不会自己续读 —— 2026-11-08 真机现场
  /// 就是「停在 11s 十几分钟不动」。重开一次 open 会触发**新的 Range 请求**，
  /// 本地流服务器顺势从断点重新供数，并把 `seek_generation` 推进一代、叫醒
  /// 卡在旧位置上的 `serve_range` 线程（见 torrent_bridge.cpp）。
  ///
  /// 关键：**只重开 mpv，不碰 torrentService**（种子/缓冲全部保留），
  /// 这与 [DetailMagnetPlayback] 里首帧阶段的「就地重开」是同一策略。
  bool get _canReopenMagnetStream =>
      isMagnetStreamSessionActive &&
      (activeStreamUrl?.isNotEmpty ?? false) &&
      _magnetStreamReopens < _maxMagnetStreamReopens;

  Future<void> _reopenMagnetStream(String reason) async {
    final url = activeStreamUrl;
    if (url == null || url.isEmpty) return;
    _magnetStreamReopens++;
    // 起点取「已缓冲到的位置」往前退 2s：mpv 从断点重开时第一帧正好接上，
    // 不会出现「回到 0s 再花几十秒缓冲」的观感倒退。
    final anchor = bufferedPosition > position ? bufferedPosition : position;
    final resumeAt = anchor > const Duration(seconds: 3)
        ? anchor - const Duration(seconds: 2)
        : Duration.zero;
    _magnetReopenAnchor = anchor;
    DebugLog.log(
      'Play',
      '磁力流就地重开($reason) 第 $_magnetStreamReopens/$_maxMagnetStreamReopens 次: '
          'pos=${position.inSeconds}s buffered=${bufferedPosition.inSeconds}s '
          'resumeAt=${resumeAt.inSeconds}s url=$url（不删种子）',
      flush: true,
    );
    isBuffering = true;
    _notifyUiImmediate();
    try {
      await playerService.play(url, startAt: resumeAt);
    } catch (e) {
      DebugLog.log('Play', '磁力流就地重开失败: $e', flush: true);
    }
    if (!_disposing) _notifyUiImmediate();
  }

  /// 停滞软重载：按当前权威进度重新拉流（不跳片头、不丢进度）。
  Future<void> reloadStalled() async {
    // 🔴 2026-11-08 真机定案：磁力流是 TorrentPlayerService 手里的本地 HTTP
    // 流，piece 调度由引擎管。重新 play(旧 url) 会打断顺序预取；而且
    // `currentOpenUrl` 对磁力只是 `magnet-file://<index>` 伪地址（或上一部片
    // 的残留 URL），拿它去 open 必然 `Failed to recognize file format` →
    // lifecycle=error，之后位置永远定格、无人恢复。
    // 磁力停滞时不重开播放器：退回 buffering 等引擎继续供数，让 mpv 自己
    // 接着读；只有在线/普通 URL 才走下面的「按进度重新 open」。
    final magnetStream = isMagnetStreamSessionActive;
    DebugLog.log(
      'Play',
      '软重载入口: magnet=$magnetStream currentPlayUrl=$currentPlayUrl '
          'activeStreamUrl=$activeStreamUrl '
          'lc=${playback.lifecycle.name} pos=${position.inSeconds}s '
          'buffered=${bufferedPosition.inSeconds}s',
      flush: true,
    );
    if (magnetStream) {
      // 2026-11-08 修正：旧实现在这里**只等不救**，理由是 `currentOpenUrl`
      // 对磁力是 `magnet-file://<index>` 伪地址。但现在有了真正的本地流地址
      // `activeStreamUrl`（http://127.0.0.1:PORT/...），可以从断点重开。
      // 90s 位置不推进 = mpv 侧已经僵死，光等是等不回来的。
      if (_canReopenMagnetStream) {
        await _reopenMagnetStream('看门狗定格');
        return;
      }
      DebugLog.log(
        'Play',
        '磁力缓冲停滞 → 保持流句柄等待供数（pos=${position.inSeconds}s '
        'buffered=${bufferedPosition.inSeconds}s '
        'speed=${torrentService.downloadSpeed}B/s），不重开播放器',
        flush: true,
      );
      isBuffering = true;
      _notifyUiImmediate();
      return;
    }
    final url = currentOpenUrl ?? activeStreamUrl;
    if (url == null || url.isEmpty) {
      await playerService.resume();
      return;
    }
    // 刚被用户拖过进度条时，mpv 的 lastPlayerReport 很可能还停在 seek 之前，
    // 不能按「偏差>30s 以实际上报为准」把它当成真相：那会把软重载起点设成
    // 用户拖动之前的位置（2026-11-07「恢复画面但位置完全不对」）。
    final lastSeek = _lastExplicitSeekAt;
    final recentlySought = lastSeek != null &&
        DateTime.now().difference(lastSeek) < kAdoptGuardAfterExplicitSeek;
    final at = resolveReloadStartAt(
      authoritative: playback.authoritativePosition,
      reported: playback.lastPlayerReport,
      preferAuthoritative: recentlySought,
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

  /// 清掉在途 seek 的等待状态（换集 / 释放 / 新一次 seek 前）。
  /// 只清自己的状态，不改 lifecycle —— 换集时 lifecycle 由 prepareOpen 管。
  void _clearSeekLanding() {
    _pendingSeekTarget = null;
    _seekLandingTimer?.cancel();
    _seekLandingTimer = null;
    final completer = _seekLandingCompleter;
    _seekLandingCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// 结束在途 seek：落位 / 超时 / 底层异常都走这里，保证 lifecycle 不会
  /// 永久卡在 seeking（旧实现没有 try/finally，`seek()` 抛异常就再也没人调
  /// onSeekFinished，此后所有 position 上报被整页忽略，进度条彻底冻结）。
  void _finishSeekLanding() {
    final target = _pendingSeekTarget;
    if (target == null) return;
    _clearSeekLanding();
    playback.onSeekFinished(playing: isPlaying);
    if (!_disposing) {
      DebugLog.log(
        'Playhead',
        'seek 落位结束 target=${target.inSeconds}s '
        '实际=${playback.lastPlayerReport.inSeconds}s',
      );
      onSeekLandedUi?.call();
    }
  }

  /// 开始等「磁力 seek 之后画面真的回来」。
  ///
  /// 必须在 `await playerService.seek()` **之前**调用：磁力流 seek 到一个还没
  /// 下载到的片段时，这个 await 本身就会阻塞好几秒（真机日志里 496s / 3046s
  /// 两处都是这样）。
  void _startMagnetSeekVisualWait(Duration target) {
    if (!isMagnetStreamSessionActive) return;
    _magnetSeekVisualTimer?.cancel();
    _magnetSeekVisualTarget = target;
    magnetSeekVisualPending = true;
    _seekWaitTicker.start();
    final startedAt = DateTime.now();
    _magnetSeekVisualTimer = Timer.periodic(
      kMagnetSeekVisualPollInterval,
      (_) => unawaited(_pollMagnetSeekVisual(startedAt)),
    );
    _notifyUiImmediate();
  }

  /// 轮询 mpv 原生属性判断是否已出画。
  ///
  /// `seeking` 是 mpv 自己的「还在 seek 吗」，比位置上报更贴近「画面回来
  /// 没有」；`demuxer-cache-duration` 是目标附近可立即播放的缓存量。任一
  /// 读到 null 就按无证据处理（只靠位置推进 / 兜底上限收尾）。
  Future<void> _pollMagnetSeekVisual(DateTime startedAt) async {
    if (_magnetSeekPolling) return;
    final target = _magnetSeekVisualTarget;
    if (target == null || _disposing) {
      _finishMagnetSeekVisual();
      return;
    }
    _magnetSeekPolling = true;
    try {
      final elapsed = DateTime.now().difference(startedAt);
      // 磁力流下 mpv 可能正卡在 demuxer 读上，属性读取跟着长时间不返回；
      // 每次读都设上限，读不到按「无证据」处理，绝不让轮询自己挂死。
      Future<String?> read(String name) => playerService
          .mpvProperty(name)
          .timeout(kMagnetSeekPropertyTimeout, onTimeout: () => null);
      final pos = parseMpvSeconds(await read('time-pos'));
      final seeking = parseMpvFlag(await read('seeking'));
      final cache = parseMpvSeconds(await read('demuxer-cache-duration'));
      if (_disposing || _magnetSeekVisualTarget != target) return;
      final reported = pos ?? playback.lastPlayerReport;
      if (!shouldFinishMagnetSeekVisualWait(
        target: target,
        reportedPosition: reported,
        mpvSeeking: seeking,
        cacheDuration: cache,
        playing: isPlaying,
        elapsed: elapsed,
      )) {
        return;
      }
      DebugLog.log(
        'Playhead',
        '磁力 seek 出画: target=${target.inSeconds}s '
        'pos=${reported.inSeconds}s '
        'seeking=${seeking == null ? '?' : (seeking ? 'yes' : 'no')} '
        'cache=${cache?.inMilliseconds ?? -1}ms '
        '耗时=${elapsed.inMilliseconds}ms',
        flush: true,
      );
      _finishMagnetSeekVisual();
    } finally {
      _magnetSeekPolling = false;
    }
  }

  /// 结束「等出画」：出画 / 超时 / 报错 / 换集都走这里。
  void _finishMagnetSeekVisual() {
    _magnetSeekVisualTimer?.cancel();
    _magnetSeekVisualTimer = null;
    _magnetSeekVisualTarget = null;
    _seekWaitTicker.stop();
    if (!magnetSeekVisualPending) return;
    magnetSeekVisualPending = false;
    _notifyUiImmediate();
    // 加载态结束 = 控制栏可以重新进入 3 秒隐藏倒计时。
    if (!_disposing) onSeekLandedUi?.call();
  }

  /// 暂停 / 恢复前等在途 seek 落位，避免「向未缓冲位置 seek 途中暂停」导致
  /// mpv 没有解码出任何新帧、外层黑底直接透出来（2026-11-07 用户反馈）。
  Future<void> _awaitSeekLanding() async {
    final completer = _seekLandingCompleter;
    if (completer != null && !completer.isCompleted) {
      await completer.future;
    }
  }

  bool _isUserPausedRecently() {
    final at = _lastUserPauseAt;
    if (at == null) return false;
    // 只要还停在暂停态就不该判停滞；恢复播放后再留 10s，覆盖「seek 刚落位、
    // 缓冲前沿还没铺开」的那一瞬间。打开新媒体时由 cancelPendingRecovery 清掉。
    if (!isPlaying) return true;
    return DateTime.now().difference(at) < kUserPauseStallGuard;
  }

  /// 跳转到指定位置。
  ///
  /// mpv 的 `seek` 命令是**异步**的：命令返回 ≠ 已落位。这里保持 seeking
  /// 直到收到落在目标附近的第一条 position 上报（或兜底超时），期间旧上报
  /// 全丢；这样用户「点进度条 → 立刻点暂停」也不会把进度权威值搞乱。
  Future<void> seek(Duration position) async {
    // 用户主动 seek（进度条拖动 / 滑动手势 / 续播自身）：先取消「续播点待确认」
    // 纠偏。否则 900ms 后的 _confirmResumeStart 会把用户的移动误判成「续播未
    // 生效」，反复 seek 回旧续播点——表现为拖回前段立刻被弹回续播点
    // （2026-10-18《爱情公寓》S1E1 27→36 分用户反馈）。
    _cancelPendingResumeConfirm();
    _lastExplicitSeekAt = DateTime.now();
    // 上一次 seek 还没落位就又拖了一次：先放行旧的等待者，避免挂死。
    _clearSeekLanding();
    _pendingSeekTarget = position;
    _seekLandingCompleter = Completer<void>();
    playback.onSeekStarted();
    playback.confirmExplicitPosition(position, duration: duration);
    this.position = playback.authoritativePosition;
    _seekLandingTimer = Timer(kSeekLandingTimeout, _finishSeekLanding);
    // 磁力：进度权威 2.5s 兜底超时只影响进度条，加载提示要按「真的出画」撤。
    _startMagnetSeekVisualWait(position);
    try {
      await playerService.seek(position);
    } catch (e) {
      DebugLog.log('Playhead', '用户 seek 失败 target=${position.inSeconds}s: $e');
      _finishSeekLanding();
      return;
    }
    // 等落位（或超时）；pause()/resume() 会等同一个 completer。
    final completer = _seekLandingCompleter;
    if (completer != null) await completer.future;
  }

  /// 取消续播点的延迟确认/纠偏（用户已主动 seek 时调用）。
  void _cancelPendingResumeConfirm() {
    isApplyingResume = false;
    _resumeSeekTarget = null;
  }

  /// 调整音量（写入系统音量；mpv 保持 100% 直通，实际响度由系统决定）
  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, maxVolumeUi);
    this.volume = v;
    await SystemVolume.instance.setVolume(v);
  }

  /// 切换静音（仅播放器增益 0/100，不动系统音量）
  Future<void> toggleMute() async {
    isMuted = !isMuted;
    await playerService.setVolume(isMuted ? 0 : 100);
  }

  /// 把系统音量同步进 UI（只读取，不写入）。
  ///
  /// [force] 为 true 时即使正在竖滑也回写 —— 只在手势起始处使用：此时累计位移
  /// 已清零，用系统值当起点，避免「App 内 volume 陈旧（如 0）而系统是 10」时
  /// 一滑动音量先跳到 0 的跳变。
  Future<void> syncSystemVolume({bool force = false}) async {
    final v = await SystemVolume.instance.getVolume();
    if (verticalGestureActive && !force) return;
    volume = v.clamp(0.0, maxVolumeUi);
    onUiChanged?.call();
  }

  /// 订阅系统音量变化，保持 App 内 volume 与系统一致。
  ///
  /// 🔴 之前只定义了 [SystemVolume.onVolumeChanged] 却没有任何订阅：EventChannel
  /// 的 onListen 不触发 → Kotlin 侧 registerReceiver 从不执行 → 系统音量变化永远
  /// 到不了 Dart。实测系统音量 10 时 App 内 volume 仍停在 0，一滑动音量先跳到 0。
  void _listenSystemVolume() {
    if (_systemVolumeSub != null) return;
    _systemVolumeSub = SystemVolume.instance.onVolumeChanged.listen(
      _applySystemVolume,
      onError: (Object e) => debugPrint('[Volume] 系统音量流异常: $e'),
    );
  }

  /// 应用系统回报的归一化音量（手势进行中不覆盖，避免打断用户拖动）。
  void _applySystemVolume(double v) {
    if (_disposing || verticalGestureActive) return;
    final next = v.clamp(0.0, maxVolumeUi);
    if ((next - volume).abs() < 0.001) return;
    volume = next;
    onUiChanged?.call();
  }

  /// 调整播放速度
  Future<void> setPlaybackSpeed(double speed) async {
    // 先落日志再改：setRate 在播放器重建瞬间可能作用到旧实例（甚至抛异常），
    // 先记下「谁把速率设成多少」，事后可与 mpv speed 探针比对是否真的生效。
    DebugLog.log(
      'Speed',
      'setPlaybackSpeed ${playbackSpeed.toStringAsFixed(2)} -> '
          '${speed.toStringAsFixed(2)}',
      flush: true,
    );
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
    _clearSeekLanding();
    _finishMagnetSeekVisual();
    _lastUserPauseAt = null;
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
    _magnetErrorProgress = Duration.zero;
    _lastMagnetErrorTick = null;
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
    onPlaybackActiveChanged = null;
    onSeekLandedUi = null;

    _seekLandingTimer?.cancel();
    _clearSeekLanding();
    _finishMagnetSeekVisual();
    hideTimer?.cancel();
    seekBubbleTimer?.cancel();
    gestureBarTimer?.cancel();
    gestureHintTimer?.cancel();
    progressPersistTimer?.cancel();
    lockChromeHideTimer?.cancel();
    _discontinuityRecoveryTimer?.cancel();
    _prematureFallbackTimer?.cancel();
    _heartbeatTimer?.cancel();
    _systemVolumeSub?.cancel();
    _systemVolumeSub = null;

    // 必须摘掉 lifecycleNotifier 的监听：监听闭包捕获了本对象，
    // 不摘会让整个详情页对象图（含 coordinator / authority）被 ValueNotifier 持有，
    // 每次进出详情页泄漏一份；若离开时正处于 opening 状态，
    // _openElapsedTicker 的 200ms 定时器还会继续跑。
    disposeLifecycleListener();

    _clearPlayerServiceCallbacks();

    // 释放 notifier 本身（UI 侧通过 ValueListenableBuilder 绑定过）。
    positionListenable.dispose();
    playerLifecycleNotifier.dispose();
    openElapsedSeconds.dispose();
    seekWaitSeconds.dispose();
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
