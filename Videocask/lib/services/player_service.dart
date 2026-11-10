import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'playback_strategy.dart';
import 'playback_start_seek_exception.dart';
// mpv 专有能力按平台分发（Web 上 NativePlayer 无相关方法）
import 'player_mpv.dart';
import 'debug_log.dart';
import 'hw_decode_policy.dart';
import 'video_output_policy.dart';
import 'subtitle_render_policy.dart';
import 'player_listeners.dart';
import 'playback_experiment.dart';
import 'resource_scope.dart';
import 'storage_service.dart';

/// Android 视频输出配置 —— 🔴 FD 泄漏修复的锁死点。
///
/// 2026-10-23 荣耀70真机实测：SurfaceProducer（默认）每送显一帧漏 1 个
/// `anon_inode:sync_file` fd（+22~24/s，约 24 分钟耗尽 32768 崩溃）；
/// SurfaceTexture 路径 5 分钟 31 点采样斜率 +0.000/s。
/// 机制与证据链见 [PlayerService._videoControllerConfig] 内注释。
///
/// 提取为顶层函数的原因：测试宿主是 Windows，`Platform.isAndroid` 恒为
/// false，走不到 `_videoControllerConfig` 的 Android 分支——不提取就无法
/// 用回归测试锁死 `enableAndroidSurfaceProducer: false`。
/// 锁死测试：test/services/player_service_test.dart
/// 「FD 泄漏修复锁死（SurfaceTexture 路径）」组。摘修复即红。
VideoControllerConfiguration androidVideoControllerConfig({
  required String? vo,
  required String? hwdec,
}) {
  return VideoControllerConfiguration(
    vo: vo,
    hwdec: hwdec,
    // false = SurfaceTexture 老路径（FD 泄漏修复，荣耀70实测 +0.000/s）。
    // 矩阵测试期间可被 debugSurfaceProducerOverride 临时覆盖（见下）。
    enableAndroidSurfaceProducer: PlayerService.debugSurfaceProducerOverride ?? false,
  );
}

/// ===== FD 泄漏矩阵测试通道（仅 debug 构建；2026-10-23 新增）=====
///
/// 真机排列组合实验用：deeplink `movieapp://testcfg?sp=...&gpuapi=...` 设置。
/// 不持久化——重启即失效，每次测试由脚本重新下发，不会污染正式包行为
/// （release 构建里这两个字段恒 null，行为与没有它们时完全一致）。

/// 播放器服务
///
/// 统一处理播放器的初始化、播放控制、进度管理等逻辑
class PlayerService {
  /// demuxer 读缓存（默认 32MB 偏小，网络流首帧/拖动后恢复偏慢）
  static const int defaultDemuxerBufferBytes = 96 * 1024 * 1024;

  /// 实验台专用：周期缓存探针 + 配置热切（仅 experiment.json 存在时启动）。
  Timer? _experimentTimer;

  // ── 门 0 观测通道修复（2026-11-09）──
  // PlayerService 不是单例：每个 DetailPlayer 会 new 一个。旧代码给每个实例
  // 都起一个 Timer.periodic，且 dispose() 不 cancel。页面退出后旧实例仍每 5s
  // 调 probeCacheState()，此时 _player 已置 null → 8 个 mpv 属性全读不到 →
  // 写一行「缓存: ...= = =」空值。真机 6671 行探针里只有 1189 行带数值，
  // 空值率 74~93% 就是这么来的；历史只能靠 [Jump] mpv 快照 补值，存在
  // 「有 Jump 才有读数」的选择偏差。
  // 现在全局只允许一个活跃探针，且绑定当前持有播放器实例的 service。
  static Timer? _activeExperimentTimer;
  static PlayerService? _activeProbeOwner;
  static int _nextInstanceId = 0;

  int _instanceId = 0;
  bool _probeBusy = false;

  int get _probeId {
    if (_instanceId == 0) _instanceId = ++_nextInstanceId;
    return _instanceId;
  }

  PlaybackStrategyConfig _strategyConfig =
      PlaybackStrategyConfig.fromKey('balanced');

  PlaybackStrategyConfig get strategyConfig => _strategyConfig;

  /// 矩阵测试专用：覆盖 SurfaceProducer 开关（null=修复默认 false）。
  ///
  /// 由 debug deeplink（movieapp://testcfg?sp=true|false）写 Hive，
  /// [init] 时读取。**必须持久化**：早期版本用纯内存静态变量，被
  /// 「testcfg → force-stop → 冷启」流程中的重启冲掉，白跑一整批
  /// （2026-10-23 实测教训）。release 构建里 Hive 无此 key，恒 null。
  static bool? debugSurfaceProducerOverride;

  /// 矩阵测试专用：覆盖 mpv `gpu-api`（null=mpv 自选）。同落 Hive。
  static String? debugGpuApiOverride;

  /// 清理矩阵测试 override（测试批次结束后调用，恢复修复默认行为）。
  static void clearDebugOverrides() {
    debugSurfaceProducerOverride = null;
    debugGpuApiOverride = null;
  }

  /// 从 Hive 读取矩阵测试 override（[init] 调用；release 下两个 key 不存在）。
  static void _loadDebugOverridesFromStorage() {
    try {
      final storage = StorageService();
      final sp = storage.getSetting('debug_surface_producer');
      debugSurfaceProducerOverride = (sp == 'true' || sp == 'false') ? sp == 'true' : null;
      final api = storage.getSetting('debug_gpu_api');
      debugGpuApiOverride = (api == 'vulkan' || api == 'opengl') ? api : null;
    } catch (_) {
      // 存储不可用（如 Web/测试宿主）时静默保持 null，不影响正常播放。
    }
  }

  /// 播放器实例
  Player? _player;

  /// 视频控制器
  VideoController? _videoController;

  /// 本次播放器实例所持有的资源（订阅 / 播放器 / 控制器）。
  ///
  /// 用 [ResourceScope] 统一管理：回收重建 = 释放旧作用域 + 建新作用域，
  /// 释放顺序保证「订阅先于播放器」死亡，避免回调打到已销毁对象。
  ResourceScope _scope = ResourceScope(name: 'player');

  /// 播放状态变化（多播）。
  ///
  /// 改为多播的原因：播放器实例会被回收重建，若外部直接订阅
  /// `player.stream.playing`，订阅会挂在已 dispose 的旧实例上，表现为
  /// 「回收一次，进度/状态永久冻结」。订阅服务而非实例，重建后自动恢复。
  final PlayerEventChannel<bool> playingChanged = PlayerEventChannel<bool>();

  /// 位置更新（多播，内部已按 200ms 节流）。
  final PlayerEventChannel<Duration> positionChanged =
      PlayerEventChannel<Duration>();

  /// 时长更新（多播）。
  final PlayerEventChannel<Duration> durationChanged =
      PlayerEventChannel<Duration>();

  /// 缓冲状态变化（多播）。
  final PlayerEventChannel<bool> bufferingChanged = PlayerEventChannel<bool>();

  /// 缓冲进度更新（多播）。
  final PlayerEventChannel<Duration> bufferChanged =
      PlayerEventChannel<Duration>();

  /// 播放完成（多播）。
  final PlayerEventChannel<int> completed = PlayerEventChannel<int>();

  /// 播放错误（多播）。
  final PlayerEventChannel<String> error = PlayerEventChannel<String>();

  /// 播放倍速变化（多播）。
  final PlayerEventChannel<double> rateChanged = PlayerEventChannel<double>();

  /// 音频码率变化（多播，bits/s）。
  final PlayerEventChannel<double?> audioBitrateChanged =
      PlayerEventChannel<double?>();

  /// 视频分辨率变化（多播）。
  final PlayerEventChannel<(int?, int?)> videoSizeChanged =
      PlayerEventChannel<(int?, int?)>();

  /// 内嵌字幕行变化（多播）。
  final PlayerEventChannel<List<String>> subtitle =
      PlayerEventChannel<List<String>>();

  int? _lastVideoWidth;
  int? _lastVideoHeight;
  int _videoRotate = 0;

  int get videoRotate => _videoRotate;

  /// 位置更新节流时间戳
  int _lastPositionUpdateMs = 0;

  /// 位置更新节流间隔（毫秒）
  static const _positionThrottleMs = 200;

  // ===== 位置跳变取证（2026-11-04「正常播放被跳过片段」） =====
  //
  // 现象：录屏 14.83s 弹「正在缓冲…」、14.92s 已换成另一场戏、随后画面冻 4 帧。
  // 说明不是时间轴缓慢漂移，而是**瞬时位置切换 + rebuffer**。
  // 但 30s 一次的心跳抓不到 17s 录屏里的那一下，[Playhead] 也一条都没有。
  // 这里在**未经节流的原始 position 流**上做突变检测：无论跳变来自 App 的
  // seek、mpv 内部 seek，还是 HLS 分片 pts 错乱，都会被记下来。

  /// 上一次原始上报的位置与墙钟（节流前，200ms 粒度的真实采样）
  Duration? _lastRawPos;
  int _lastRawPosMs = 0;

  /// 最近一次 App 主动 seek 的目标/来源/时刻（用于区分「我们跳的」和「它自己跳的」）
  Duration? _lastSeekTarget;
  String _lastSeekSource = '';
  int _lastSeekAtMs = 0;

  /// 最近一次 buffering 事件（跳变时一并记录，判断是否伴随 rebuffer）
  bool _lastBuffering = false;

  /// 判定为「跳变」的最小位移与最大墙钟间隔。
  /// 正常播放 200ms 只前进 0.2s，所以 2s 位移足够区分；
  /// 墙钟间隔 >1.5s 说明中间被暂停/切后台，不算同一段连续播放。
  static const _jumpMinMs = 2000;

  Future<void>? _playChain;
  bool _disposed = false;

  /// 当前播放的媒体 URL（回收重建后续播用）
  String? _currentUrl;

  /// 当前硬件解码档位（回收重建后恢复用）。
  HwDecodeMode _hwDecodeMode = HwDecodeMode.disabled;

  /// 当前硬件解码档位（对外只读）。
  HwDecodeMode get hwDecodeMode => _hwDecodeMode;

  /// 服务是否已被 [dispose] 永久销毁（单例语义：一旦销毁不再可用）。
  ///
  /// 页面级关闭请用 [releasePlayerInstance]——只释放播放器实例，
  /// 服务保持可懒重建；误调 [dispose] 会让后续所有播放入口静默短路。
  bool get isDisposed => _disposed;

  /// 硬解运行时探测到的实际后端（如 `mediacodec-copy`）；null = 尚未探测。
  ///
  /// 仅作诊断展示（日志/缓存），不参与任何自动改档逻辑。
  String? _observedHwDecBackend;

  /// 实际探测到的后端（诊断用）。
  String? get observedHwDecBackend => _observedHwDecBackend;

  /// 播放器实例被回收重建后通知 UI（Video widget 需重绑 controller）
  void Function()? onPlayerRecreated;

  /// 回收重建计数（UI 用作 Video widget 的 key，强制重建以干净释放旧 controller）
  int recycleEpoch = 0;

  /// 回收进行中（防重入）
  bool _recycling = false;

  /// 自动播放下一集
  bool _autoPlayNext = true;

  /// 自动播放下一集
  bool get autoPlayNext => _autoPlayNext;

  /// 视频控制器
  VideoController? get videoController => _videoController;

  /// 播放速度
  double _playbackSpeed = 1.0;

  /// 播放速度
  double get playbackSpeed => _playbackSpeed;

  /// 播放器配置。
  ///
  /// [PlayerConfiguration.libass] 默认是 `false`，media_kit 会在每次 open 时
  /// 把 `sub-ass` / `sub-visibility` / `secondary-sub-visibility` 写成 `no`。
  /// 后果是内封字幕轨即使被 `sid` 选中也永远不会绘制：2026-11-07 真机实测
  /// 回读为 `期望sid=1 实际sid=no visibility=no sub-ass=no sub-text=`。
  /// 因此必须显式开启 libass；Android 的 libass/fontconfig 读不到系统字体，
  /// 还要随包内置一份中文字体（子集化 Noto Sans CJK SC，约 1.8MB）。
  PlayerConfiguration _playerConfiguration() {
    return PlayerConfiguration(
      bufferSize: _strategyConfig.demuxerBufferBytes,
      libass: true,
      libassAndroidFont: 'assets/fonts/subtitle_zh.otf',
      libassAndroidFontName: 'Noto Sans CJK SC',
    );
  }

  /// 初始化播放器
  Future<void> init() async {
    if (_player != null) return;

    // 矩阵测试 override 先读盘（debug deeplink 写入；release 下无 key 恒 null）。
    _loadDebugOverridesFromStorage();

    _player = Player(configuration: _playerConfiguration());
    // 硬解档位沿用当前生效值（由设置层下发），**不**在这里硬编码关闭。
    await _applyMpvTuning();
    // 矩阵测试专用：显式指定 mpv gpu-api（vulkan/opengl），仅 debug 下发。
    // gpu-api 是 mpv 初始化期选项，必须在 open 媒体前设置才生效；
    // 仅 vo=gpu-next 时该属性有意义（vo=gpu 老渲染器只有 GL）。
    if (debugGpuApiOverride != null) {
      try {
        await setMpvProperty(_player!, 'gpu-api', debugGpuApiOverride!);
        DebugLog.log(
          'Play',
          '矩阵测试: gpu-api 覆盖为 ${debugGpuApiOverride}',
          flush: true,
        );
      } catch (e) {
        DebugLog.log(
          'Play',
          '矩阵测试: gpu-api 覆盖失败 $e',
          flush: true,
        );
      }
    }
    // 显式设置音量为最大，确保有声音
    await _player!.setVolume(100.0);
    _videoController = VideoController(
      _player!,
      configuration: _videoControllerConfig(),
    );

    // media_kit 建 Player 时把 sub-visibility / secondary-sub-visibility 全写
    // yes；这里立刻压回「用户上次的选择 + 次字幕恒关」，避免字幕自己冒出来。
    await _pushSubtitleVisibility();
    _wireStreams();
  }

  /// 订阅播放器各状态流（init 与回收重建复用）。
  ///
  /// 所有订阅都注册进 [_scope]，回收时随作用域一并释放，**不会**残留
  /// 挂在已 dispose 的旧 Player 实例上。
  void _wireStreams() {
    // 监听播放状态
    _scope.addSubscription(
      _player!.stream.playing.listen((playing) {
        playingChanged.emit(playing);
      }),
      label: 'stream:playing',
    );

    // 监听位置（节流：每200ms更新一次UI）
    _scope.addSubscription(
      _player!.stream.position.listen((position) {
        final now = DateTime.now().millisecondsSinceEpoch;
        // 取证必须在节流**之前**：节流会丢掉 200ms 内的采样，
        // 而一次 seek 的跳变恰好就发生在两次上报之间。
        _detectPositionJump(position, now);
        if (now - _lastPositionUpdateMs < _positionThrottleMs) return;
        _lastPositionUpdateMs = now;
        positionChanged.emit(position);
      }),
      label: 'stream:position',
    );

    // 监听时长
    _scope.addSubscription(
      _player!.stream.duration.listen((duration) {
        durationChanged.emit(duration);
      }),
      label: 'stream:duration',
    );

    // 监听缓冲状态
    _scope.addSubscription(
      _player!.stream.buffering.listen((buffering) {
        _lastBuffering = buffering;
        bufferingChanged.emit(buffering);
      }),
      label: 'stream:buffering',
    );

    // 监听缓冲进度
    _scope.addSubscription(
      _player!.stream.buffer.listen((buffer) {
        bufferChanged.emit(buffer);
      }),
      label: 'stream:buffer',
    );

    // 监听完成
    _scope.addSubscription(
      _player!.stream.completed.listen((isCompleted) {
        if (isCompleted) {
          completed.emit(0);
        }
      }),
      label: 'stream:completed',
    );

    // 监听错误
    _scope.addSubscription(
      _player!.stream.error.listen((err) {
        error.emit(err.toString());
      }),
      label: 'stream:error',
    );

    _scope.addSubscription(
      _player!.stream.rate.listen((rate) {
        rateChanged.emit(rate);
      }),
      label: 'stream:rate',
    );

    _scope.addSubscription(
      _player!.stream.audioBitrate.listen((bitrate) {
        audioBitrateChanged.emit(bitrate);
      }),
      label: 'stream:audioBitrate',
    );

    _scope.addSubscription(
      _player!.stream.width.listen((w) {
        _lastVideoWidth = w;
        _emitVideoSizeIfReady();
      }),
      label: 'stream:width',
    );

    _scope.addSubscription(
      _player!.stream.height.listen((h) {
        _lastVideoHeight = h;
        _emitVideoSizeIfReady();
      }),
      label: 'stream:height',
    );

    _scope.addSubscription(
      _player!.stream.subtitle.listen((lines) {
        subtitle.emit(lines);
      }),
      label: 'stream:subtitle',
    );
  }

  void _emitVideoSizeIfReady() {
    final w = _lastVideoWidth;
    final h = _lastVideoHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return;
    unawaited(_syncVideoRotateAndNotify());
  }

  Future<void> _syncVideoRotateAndNotify() async {
    final w = _lastVideoWidth;
    final h = _lastVideoHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return;
    await _syncVideoRotate();
    videoSizeChanged.emit((w, h));
  }

  Future<void> _syncVideoRotate() async {
    if (kIsWeb || _player == null) return;
    try {
      final raw = await getMpvProperty(_player!, 'video-params/rotate');
      _videoRotate = int.tryParse((raw ?? '').trim()) ?? 0;
    } catch (_) {
      _videoRotate = 0;
    }
  }

  /// 播放视频；[startAt] 非空时先 open 再 seek，避免从 0 起播后 position 流把 UI 打回开头。
  Future<void> play(
    String url, {
    Duration? startAt,
  }) async {
    // 回收进行中时，外部播放请求需等待回收完成（回收会 dispose 当前 Player），
    // 否则可能与回收竞态：在已被销毁的 Player 上 open → 未捕获异常。
    while (_recycling) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final previous = _playChain;
    final current = _playInternal(
      url,
      startAt: startAt,
    );
    _playChain = current;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }
    try {
      await current;
    } finally {
      if (identical(_playChain, current)) {
        _playChain = null;
      }
    }
  }

  Future<void> _playInternal(
    String url, {
    Duration? startAt,
  }) async {
    if (_disposed) return;
    _currentUrl = url;
    if (_player == null) {
      await init();
    }
    if (_disposed || _player == null) return;
    // 换片源时重置字幕偏移，避免上一集调过的时间轴带到新片源。
    if (_subtitleDelaySeconds != 0) {
      _subtitleDelaySeconds = 0;
      await _applySubtitleDelay();
    }
    final media = Media(url);
    final resume = startAt != null && startAt > Duration.zero ? startAt : null;
    DebugLog.log(
      'Play',
      'playInternal startAt=${startAt?.inSeconds ?? -1}s '
          'branch=${resume != null ? 'resume(open+seek)' : 'open(play:true)'}',
    );
    if (resume != null) {
      await _player!.open(media, play: false);
      if (_disposed) return;
      // 网络 HLS 流打开初期 duration 尚未就绪，立刻 seek 会落空（位置停在 0），
      // 表现为「进度条显示续播点、画面却从开头播」。等流可定位后再 seek。
      await waitUntilSeekable(resume);
      if (_disposed) return;
      await _seekForOpenStart(resume);
      if (_disposed) return;
      await _player!.play();
      // open 会把 sub-visibility 重置成 yes，必须按用户选择重压一次。
      await _pushSubtitleVisibility();
      return;
    }
    await _player!.open(media, play: true);
    await _pushSubtitleVisibility();
  }

  /// open 后 seek 到续播点；失败则抛 [PlaybackStartSeekException]（禁止静默从 0 播）。
  ///
  /// 2026-11-08 真机修复：`_player.state.duration/position` 在磁力流
  /// `open(play:false)` 阶段会长期停在 0，而 mpv 原生 `duration` 已是 7507s、
  /// `track-list` 完整、`[Jump]` 也确实跳到了续播点。于是下面三次 350ms 判定
  /// 必然误判「seek 失败」→ 抛异常 → 上层重开流 → 磁力数据不足报
  /// `Failed to recognize file format` → 失败卡片压住画面。
  /// 稳定复现两次（00:39 / 01:15，target 均 3345s）。
  /// 因此判失败后先用 mpv 原生属性二次确认：流已识别就**不重开**，
  /// 让已生效的 seek 在缓冲到位后继续播，续播纠偏链路继续兜底。
  Future<void> _seekForOpenStart(Duration target) async {
    const tolerance = Duration(seconds: 8);
    await seekPrecise(target);
    var actual = _player?.state.position ?? Duration.zero;
    if (_seekCloseEnough(actual, target, tolerance)) return;

    await Future<void>.delayed(const Duration(milliseconds: 350));
    actual = _player?.state.position ?? Duration.zero;
    if (_seekCloseEnough(actual, target, tolerance)) return;

    await seekPrecise(target);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    actual = _player?.state.position ?? Duration.zero;
    if (_seekCloseEnough(actual, target, tolerance)) return;

    // Dart 侧状态滞后 ≠ 流坏了：读 mpv 原生属性确认。只要 duration 有效，
    // 说明文件已被识别、可正常解码，seek 只是还没缓冲到目标位置
    //（磁力流远端续播的典型表现）。此时绝不能重开流。
    final p = _player;
    if (p != null) {
      try {
        final rawDur = await getMpvProperty(p, 'duration');
        final dur = double.tryParse(rawDur?.trim() ?? '') ?? 0;
        if (dur > 0) {
          final rawPos = await getMpvProperty(p, 'time-pos');
          DebugLog.log(
            'Play',
            'openStart seek 未到位但流已就绪: '
            'target=${target.inSeconds}s state.pos=${actual.inSeconds}s '
            'mpv.duration=${dur.toStringAsFixed(1)}s '
            'mpv.time-pos=${rawPos ?? '-'} '
            '→ 不重开流，等待缓冲后由续播纠偏拉回',
            flush: true,
          );
          return;
        }
      } catch (e) {
        debugPrint('openStart seek 二次确认失败: $e');
      }
    }

    debugPrint(
      'startAt seek failed: target=${target.inSeconds}s actual=${actual.inSeconds}s',
    );
    DebugLog.log(
      'Play',
      'openStart seek FAILED target=${target.inSeconds}s '
          'actual=${actual.inSeconds}s -> 抛 PlaybackStartSeekException',
      flush: true,
    );
    throw PlaybackStartSeekException(target, actual);
  }

  static bool _seekCloseEnough(
    Duration actual,
    Duration target,
    Duration tolerance,
  ) {
    if (target <= const Duration(seconds: 5)) return true;
    return (actual - target).abs() <= tolerance ||
        actual >= target - const Duration(seconds: 5);
  }

  /// 等流可定位：duration 已知且不小于 [target] 时返回；否则在 [timeout] 后返回（部分
  /// 网络流不上报 duration，由调用方继续重试 seek）。用于续播开场，避免 0 位 seek 落空。
  Future<void> waitUntilSeekable(
    Duration target, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_player == null) return;
    final startedAt = DateTime.now();
    while (DateTime.now().difference(startedAt) < timeout) {
      if (_disposed || _player == null) return;
      final dur = _player!.state.duration;
      if (dur > Duration.zero && dur >= target) return;
      // 磁力流 `open(play:false)` 阶段 media_kit 的 Dart 状态会长期停在 0，
      // 但 mpv 原生 duration 往往已经就绪（真机实测 Dart=0 / mpv=7507s）。
      // 此时流已可定位，别再空等满 8 秒。
      try {
        final raw = await getMpvProperty(_player!, 'duration');
        final nativeDur = double.tryParse(raw?.trim() ?? '') ?? 0;
        if (nativeDur > 0 && nativeDur >= target.inSeconds) return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final finalDur = _player?.state.duration ?? Duration.zero;
    DebugLog.log(
      'Play',
      'waitUntilSeekable done target=${target.inSeconds}s '
          'dur=${finalDur.inSeconds}s',
    );
  }

  /// 外挂字幕的时间轴偏移（秒）。正数 = 字幕延后出现。
  double _subtitleDelaySeconds = 0;

  /// 当前字幕时间轴偏移（秒）。
  double get subtitleDelaySeconds => _subtitleDelaySeconds;

  /// 设置字幕时间轴偏移（秒），正数表示字幕延后出现。
  Future<void> setSubtitleDelaySeconds(double seconds) async {
    _subtitleDelaySeconds = seconds;
    await _applySubtitleDelay();
  }

  /// 在现有偏移基础上增量调整（秒），返回调整后的值。
  Future<double> adjustSubtitleDelaySeconds(double delta) async {
    await setSubtitleDelaySeconds(_subtitleDelaySeconds + delta);
    return _subtitleDelaySeconds;
  }

  Future<void> _applySubtitleDelay() async {
    if (kIsWeb || _player == null) return;
    try {
      await setMpvProperty(
        _player!,
        'sub-delay',
        _subtitleDelaySeconds.toStringAsFixed(2),
      );
    } catch (e) {
      debugPrint('mpv setProperty sub-delay failed: $e');
    }
  }

  /// 加载外挂字幕文件（SRT / VTT 等，由 mpv 解析）。
  ///
  /// 2026-11-08 真机修复：原先走 `SubtitleTrack.uri(Uri.file(path).toString())`，
  /// Android 上 `file://` URL 传给 mpv `sub-add` 后轨没进 track-list
  /// （真机日志 `sid=3 visibility=yes sub-text=[] sub轨=仅两条内封 PGS`），
  /// 「已挂在线简中字幕」其实是假象。改为先用 mpv 标准裸路径
  /// `sub-add <path> select`，回读 track-list 确认；没有外部轨再用官方
  /// `SubtitleTrack.data`（让 media_kit 自己写临时文件）兜底。
  Future<void> setExternalSubtitleFromFile(String filePath) async {
    if (kIsWeb || _player == null) return;
    final p = _player!;
    try {
      final f = File(filePath);
      final exists = f.existsSync();
      DebugLog.log(
        'Subtitle',
        '外挂字幕挂载: path=$filePath exists=$exists '
        'size=${exists ? f.lengthSync() : 0}',
      );
    } catch (_) {}

    try {
      await runMpvCommand(p, ['sub-add', filePath, 'select']);
    } catch (e) {
      debugPrint('mpv sub-add 裸路径失败: $e');
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));

    var hasExternal = false;
    try {
      final raw = await getMpvProperty(p, 'track-list');
      hasExternal = (raw ?? '').contains('"external":true') ||
          (raw ?? '').contains('"external": true');
    } catch (_) {}
    DebugLog.log(
      'Subtitle',
      '外挂字幕回读: 裸路径 sub-add 后外部轨=${hasExternal ? '存在' : '缺失'}',
    );

    if (!hasExternal) {
      try {
        final text = await File(filePath).readAsString(encoding: utf8);
        if (text.isNotEmpty) {
          await p.setSubtitleTrack(
            SubtitleTrack.data(
              text,
              title: 'External',
              language: 'zh',
            ),
          );
          DebugLog.log('Subtitle', '外挂字幕: 已走 SubtitleTrack.data 兜底');
        }
      } catch (e) {
        debugPrint('外挂字幕 data 兜底失败: $e');
      }
    }
    // 换轨后 mpv 会保留 sub-delay，但外挂轨刚挂载时再刷一次更稳。
    await _applySubtitleDelay();
  }

  /// 恢复为内嵌轨自动选择（并卸掉外挂文件轨）。
  Future<void> clearExternalSubtitleTrack() async {
    if (_player == null) return;
    await _player!.setSubtitleTrack(SubtitleTrack.auto());
  }

  /// 暂停
  Future<void> pause() async {
    await _player?.pause();
  }

  /// 恢复播放
  Future<void> resume() async {
    await _player?.play();
  }

  /// 按用户播放策略与硬件解码档位调优 mpv。
  ///
  /// [hwDecodeMode] 是**权威档位**（设置层下发的用户选定档位，App 不自动降档），
  /// 应用它会同时刷新 mpv 的 `hwdec` 属性。
  Future<void> applyPlaybackStrategy(
    PlaybackStrategyConfig config, {
    required HwDecodeMode hwDecodeMode,
    VideoOutputMode? videoOutputMode,
  }) async {
    _strategyConfig = config;
    if (_hwDecodeMode != hwDecodeMode) {
      _hwDecodeMode = hwDecodeMode;
    }
    // vo **只在创建 VideoController 时生效**（见 [_videoControllerConfig]）：
    // `_applyMpvTuning` 里没有 vo 这一项，改完档位若不重建控制器，
    // 用户的设置要等到下次冷启动才生效。
    // 比较的是**实际生效**的后端（mediacodec_embed + 软解会回落 gpu）。
    final previousVo = _effectiveVoMode();
    if (videoOutputMode != null) {
      _videoOutputMode = videoOutputMode;
    }
    if (_player == null) return;
    if (_effectiveVoMode() != previousVo) {
      DebugLog.log(
        'Play',
        '视频输出后端切换为 ${mpvVoValue(_effectiveVoMode())}，重建播放器以生效',
        flush: true,
      );
      // 重建会重建 VideoController（带上新 vo）并回到原进度继续播。
      await recyclePlayer();
      return;
    }
    await _applyMpvTuning();
  }

  Future<void> _applyMpvTuning() async {
    if (kIsWeb || _player == null) return;

    final c = _strategyConfig;
    final props = <String, String>{
      'hr-seek': c.hrSeek,
      'demuxer-seekable-cache': c.demuxerSeekableCache,
      'cache-secs': '${c.cacheSecs}',
      'demuxer-max-bytes': '${c.demuxerMaxBytes}',
      'demuxer-readahead-secs': '${c.demuxerReadaheadSecs}',
      'demuxer-readahead-bytes': '${c.demuxerReadaheadBytes}',
      'cache-pause': c.cachePause,
      'network-timeout': '${c.networkTimeoutSecs}',
      'hwdec': mpvHwDecValue(_hwDecodeMode),
      // mpv 的 `--slang` 是**加载期选项**：只在 open 媒体时参与自动选轨。
      // 之前放到首帧后 4s 才设，早已错过选轨时机，是内封中文轨选不中的
      // 根因之一（真机回读 sid=no）。这里在播放器初始化期（open 之前）下发，
      // 让 mpv 打开文件时直接按语言优先级选中简中轨。
      'slang': 'chi,zho,zh,chs,cht,zh-Hans',
    };

    for (final entry in props.entries) {
      try {
        await setMpvProperty(_player!, entry.key, entry.value);
      } catch (e) {
        // 注意：失败只进 logcat（debugPrint），不进文件日志，故下面再读回确认。
        debugPrint('mpv setProperty ${entry.key} failed: $e');
      }
    }
    // 诊断：读回实际生效值。mpv 对越界/只读选项会拒收，而失败只 debugPrint，
    // 文件日志里看不出来；这里把读回值写进文件，用于确认缓存参数真的落地。
    final applied = <String>[];
    for (final key in const [
      'cache-secs',
      'demuxer-max-bytes',
      'demuxer-readahead-secs',
      'demuxer-readahead-bytes',
      'cache-pause',
      'cache-size',
      'slang',
      // 11-08 教训：数值属性设失败只 debugPrint，之前漏读这一项，
      // 「network-timeout=60 已下发」其实从未被证实过。
      'network-timeout',
    ]) {
      applied.add('$key=${await _safeMpvProperty(key) ?? '?'}');
    }
    DebugLog.log(
      'Play',
      'mpv 调优参数生效值: runId=${PlaybackExperiment.runId} '
          '${applied.join(' ')}',
      flush: true,
    );
    _startExperimentLoop();
    await _persistHwDecodeState();
  }

  /// 实验台：每 5s 采一次 mpv 真实缓冲曲线，并检测配置热切。
  ///
  /// 只写观测数据、不改任何播放行为；实验文件不存在时整个定时器都不会创建。
  void _startExperimentLoop() {
    if (!PlaybackExperiment.enabled) return;
    // 只允许一个活跃探针：切到新 DetailPlayer 时先停掉旧实例的定时器。
    if (!identical(_activeProbeOwner, this)) {
      _activeExperimentTimer?.cancel();
      _activeExperimentTimer = null;
      _activeProbeOwner = this;
    }
    _experimentTimer?.cancel();
    _experimentTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      // 旧实例 / 已 dispose / 播放器已释放 → 停表且绝不写空值行。
      if (_disposed || _player == null || !identical(_activeProbeOwner, this)) {
        _experimentTimer?.cancel();
        _experimentTimer = null;
        return;
      }
      // 8 个属性是 8 次 native IPC；上一轮没读完就别再起一轮，
      // 否则并发抢通道也会把属性读成空。
      if (_probeBusy) return;
      _probeBusy = true;
      try {
        final changed = await PlaybackExperiment.load();
        if (changed != null) {
          DebugLog.log(
            'Experiment',
            '热切参数 -> runId=$changed ${PlaybackExperiment.summary}',
            flush: true,
          );
          final cb = PlaybackExperiment.reapply;
          if (cb != null) unawaited(cb());
        }
        await probeCacheState();
      } catch (e) {
        DebugLog.log('Experiment', '实验探针异常: $e');
      } finally {
        _probeBusy = false;
      }
    });
    _activeExperimentTimer = _experimentTimer;
  }

  /// 把当前硬解档位落盘到日志目录（`hwdec_state.txt`）。
  ///
  /// 原生崩溃处理器（`crash_handler.cpp`）在写崩溃栈时会附带这个文件，
  /// 于是「这次崩溃是否发生在硬解会话中」可被**自动**判定，
  /// 不必靠用户口述或事后猜测。
  Future<void> _persistHwDecodeState() async {
    try {
      final dir = DebugLog.directory;
      if (dir == null) return;
      final file = File(
        '${dir.path}${Platform.pathSeparator}hwdec_state.txt',
      );
      await file.writeAsString(
        'mode=${_hwDecodeMode.name} '
        'mpv=${mpvHwDecValue(_hwDecodeMode)} '
        'observed=${_observedHwDecBackend ?? "unknown"} '
        'timestamp=${DateTime.now().millisecondsSinceEpoch}',
        flush: true,
      );
    } catch (e) {
      debugPrint('persist hwdec state failed: $e');
    }
  }

  /// 最近一次记录的「解码档位 + 视频输出后端」签名（避免重复刷日志）。
  String? _lastVoSignature;

  /// 视频输出后端（mpv `--vo`）。Android 默认 `gpu`（与 media_kit 默认一致）。
  ///
  /// ⚠️ 2026-10-22 定位到的**本项目自身缺陷**：此前创建 `VideoController` 从未
  /// 传 configuration，于是 media_kit 在 `AndroidVideoController.create` 里用
  /// 自己的默认值把 mpv 的 `vo` / `hwdec` **整个覆盖**掉：
  /// ```dart
  /// 'vo': 'null', 'hwdec': configuration.hwdec!, ...  // 默认 hwdec = auto-safe
  /// ```
  /// 结果：设置里选的档位（包括"关闭硬解"）在每次新建/重建播放器后都被重置，
  /// 日志里却因为软解档位不打探测日志而看不出来 —— 用户以为在测软解，实际仍在硬解。
  VideoOutputMode _videoOutputMode = defaultVideoOutputMode;

  /// 当前生效的视频输出后端（供日志/诊断读）。
  VideoOutputMode get videoOutputMode => _videoOutputMode;

  /// 运行时切换视频输出后端；切换后需重建 `VideoController` 才会生效，
  /// 因此这里直接走一次回收重建（调用方是设置页时播放器通常处于空闲态）。
  Future<void> setVideoOutputMode(VideoOutputMode mode) async {
    if (mode == _videoOutputMode) return;
    _videoOutputMode = mode;
    DebugLog.log('Play', '视频输出后端切换为 ${mpvVoValue(mode)}', flush: true);
    if (_player != null && _currentUrl != null) {
      await recyclePlayer();
    }
  }

  /// 实际生效的视频输出后端。
  ///
  /// 名义档位可能被当前解码方式改写：软解下 `mediacodec_embed` 走不了 Surface
  /// 直出，实际是 `gpu`。凡是要「按后端做判断」的地方（诊断日志、vo 生效值）
  /// 都必须用这个值，用名义档位会得出错误结论。
  VideoOutputMode _effectiveVoMode() {
    if (voRequiresHardwareDecode(_videoOutputMode) &&
        _hwDecodeMode == HwDecodeMode.disabled) {
      return VideoOutputMode.gpu;
    }
    return _videoOutputMode;
  }

  /// mpv 当前能否把字幕画进视频帧。
  ///
  /// 决定字幕由 mpv 还是 Flutter 浮层渲染，见 `subtitle_render_policy.dart`。
  /// 用实际生效的 vo（而非名义档位）：`mediacodec_embed` 在软解下会被
  /// [_effectiveVoMode] 回落成 `gpu`，此时 mpv 又能画字幕了。
  bool get mpvCanRenderSubtitle {
    if (kIsWeb) return false; // web 字幕轨行为与原生不同，维持浮层兜底
    if (!Platform.isAndroid) return true; // 桌面 mpv 正常
    return _effectiveVoMode() != VideoOutputMode.mediacodecEmbed;
  }

  /// 用户是否要显示字幕（由 `DetailPlayer.showSubtitles` 收口写入）。
  bool _subtitleVisible = false;

  /// 同步字幕开关到 mpv。
  ///
  /// 单一渲染源是 mpv，所以「关字幕」必须真的写 `sub-visibility=no`；
  /// 只改 Dart 字段的话，mpv 那份照旧画在帧里 —— 这正是历史上快捷键与
  /// 弹窗「关闭字幕」关不掉的原因。
  Future<void> syncSubtitleVisibility(bool visible) async {
    _subtitleVisible = visible;
    DebugLog.log(
      'Subtitle',
      '字幕可见性同步: show=$visible 渲染源='
          '${resolveSubtitleRenderer(mpvCanRenderSubtitle: mpvCanRenderSubtitle).name}',
      flush: true,
    );
    await _pushSubtitleVisibility();
  }

  /// 幂等重发字幕可见性。
  ///
  /// 每次 `open` 都会让 media_kit 的 `_create()` 把 `sub-visibility` /
  /// `secondary-sub-visibility` 重置成 `yes`，所以 open 收尾和播放器重建后
  /// 都要压一次，否则「上次关了字幕，换集又自己冒出来」。
  Future<void> _pushSubtitleVisibility() async {
    final p = _player;
    if (p == null) return;
    try {
      await setMpvProperty(
        p,
        'sub-visibility',
        subtitleVisibilityValue(showSubtitles: _subtitleVisible),
      );
    } catch (_) {}
    // 第三处潜在双份来源：media_kit 默认把次字幕也设成可见。
    try {
      await setMpvProperty(p, 'secondary-sub-visibility', 'no');
    } catch (_) {}
  }

  /// 创建 `VideoController` 时必须显式给出的 vo / hwdec。
  ///
  /// 不传 = 交给 media_kit 默认值 = 我们设置的档位被静默覆盖（见
  /// [_videoOutputBackend] 注释）。桌面端保持 media_kit 默认（返回 null）。
  /// 非 Android（桌面/Web）保持 media_kit 的平台默认值，不要塞 Android 的 vo。
  VideoControllerConfiguration _videoControllerConfig() {
    if (kIsWeb || !Platform.isAndroid) {
      return const VideoControllerConfiguration();
    }
    final mode = _effectiveVoMode();
    var hwdecMode = _hwDecodeMode;
    if (voRequiresHardwareDecode(_videoOutputMode)) {
      if (hwdecMode == HwDecodeMode.disabled) {
        // 软解时 mpv 不能走 Surface 直出 → _effectiveVoMode 已回落 gpu。
      } else if (hwdecMode != HwDecodeMode.mediaCodecZeroCopy) {
        // mediacodec_embed 要求 hwdec=mediacodec（零拷贝直出 Surface）；
        // copy 模式帧已拷回 CPU，走不了这条路径。
        hwdecMode = HwDecodeMode.mediaCodecZeroCopy;
      }
    }
    // 🔴 FD 泄漏修复（2026-10-23 荣耀70真机实测生效）：Android 禁用
    // SurfaceProducer，走 SurfaceTexture 老路径。
    //
    // 机制：media_kit 默认 SurfaceProducer（API 33+ 由 ImageReader 支撑），
    // Adreno GL 驱动每次 eglSwapBuffers 都会建一个 sync_file fence，而
    // Flutter 引擎 SurfaceProducer 消费侧不关它 → 每送显一帧漏 1 个 fd
    // （≈帧率 24/s），约 24 分钟耗尽 RLIMIT_NOFILE(32768) → SIGSEGV。
    // libplacebo 的 sync 修复（c93aa134）只覆盖其内部 sync 对象，管不到
    // eglSwapBuffers→Surface 这条送显末端；SurfaceTexture 路径由 GLConsumer
    // 按帧消费，fence 随 BufferQueue 正常回收。
    //
    // 真机对照实验（HONOR 70 / 骁龙 778G+ / Adreno 642L / Android 14）：
    //   SurfaceProducer（默认）: sync_file +22~24/s（正式包日志基线）
    //   SurfaceTexture（本设置）: 5 分钟 31 点采样 59~61 震荡，斜率 +0.000/s
    // 同场验证：初始播放与换集切换均正常出画，未见黑屏。
    //
    // 渲染后端约束（2026-10-23 双机终版定论，勿再反复）：
    //   - 荣耀 70（Adreno 642L / Android 14）：引擎实际后端 = Impeller-OpenGLES
    //     （Vulkan Impeller 起不来、回退 GLES，无 "Using the Skia" 行）。
    //     SurfaceTexture 老桥在 Impeller-GLES 下实测出画正常 + 零泄漏。
    //   - 新机（Adreno 830 / Android 16）：引擎实际后端 = Impeller-Vulkan
    //     （android_context_vk_impeller.cc → Using the Impeller rendering
    //     backend (Vulkan)）。9 组矩阵里 SurfaceTexture 6 组全部出画且零泄漏，
    //     **推翻了「Vulkan 不支持老桥」的旧假设**——SurfaceTexture 在 Vulkan
    //     Impeller 下同样可用。
    //   - 结论：SurfaceTexture 是 GLES 与 Vulkan 两种 Impeller 后端通用的安全桥；
    //     真正仍在漏的是 SurfaceProducer（无论 vo），已用
    //     enableAndroidSurfaceProducer:false 锁死。media_kit dartdoc 称
    //     SurfaceTexture「仅 Skia 有效」属过时保守，以真机实测为准。
    //   - ⚠️ 判定 Flutter 后端只能看引擎日志（vk_impeller / gl_impeller 行），
    //     dumpsys gfxinfo 的 "Pipeline=Skia (OpenGL)" 是 HWUI 层，证明不了
    //     FlutterView(SurfaceView) 引擎内部后端（此坑 2026-10-23 踩过两次）。
    //   换 Flutter 大版本或换机型时，复测「当前后端 + 本路径」这一格。
    // 实现锁死在顶层函数 androidVideoControllerConfig（测试可直接断言）。
    return androidVideoControllerConfig(
      vo: mpvVoValue(mode),
      hwdec: mpvHwDecValue(hwdecMode),
    );
  }

  Future<void> probeVideoOutput() async {
    if (kIsWeb || _player == null) return;
    final vo = await _safeMpvProperty('current-vo');
    final api = await _safeMpvProperty('gpu-api');
    final hwdec = await _safeMpvProperty('hwdec-current');
    final signature = '$_hwDecodeMode|$vo|$api|$hwdec';
    if (signature == _lastVoSignature) return;
    _lastVoSignature = signature;
    // mpv 实际生效值优先于我们下发的值（下发值可能被底层覆盖）。
    DebugLog.log(
      'Play',
      '视频输出: 档位=$_hwDecodeMode hwdec-current=${hwdec ?? '?'} '
      'current-vo=${vo ?? '?'} gpu-api=${api ?? '?'}',
      flush: true,
    );
    // 哨兵：设置说软解、mpv 却仍在硬解 = 我们的档位没真正生效。
    // 2026-10-22 就是因为缺这条校验，把「软解没生效」误读成「软解也泄漏」。
    final actual = hwdec?.trim();
    if (_hwDecodeMode == HwDecodeMode.disabled &&
        actual != null &&
        actual.isNotEmpty &&
        actual != 'no') {
      DebugLog.log(
        'Play',
        '⚠️ 档位要求软解但 mpv 实际为 $actual —— 档位未生效（检查 '
        'VideoController 是否传了 configuration）',
        flush: true,
      );
    }
    // 落盘实际生效的渲染后端：原生崩溃文件会附带它（见 crash_handler.cpp），
    // 于是「这次崩溃用的哪个后端」不用靠猜。
    // 2026-10-22：这份 `last_vo.txt` 曾因自动兜底机制被删而变成**陈旧文件**
    // （内容还停在几天前），差点据此误判当前后端。
    _persistVideoOutputState(vo, api, hwdec);
  }

  /// 把实际生效的渲染后端写入日志目录的 `last_vo.txt`。
  void _persistVideoOutputState(
    String? vo,
    String? api,
    String? hwdec,
  ) {
    try {
      final dir = DebugLog.directory;
      if (dir == null) return;
      final file = File(
        '${dir.path}${Platform.pathSeparator}last_vo.txt',
      );
      file.writeAsStringSync(
        'vo=${vo ?? "?"} '
        'gpu-api=${api ?? "?"} '
        'hwdec-current=${hwdec ?? "?"} '
        'mode=${_hwDecodeMode.name} '
        'timestamp=${DateTime.now().millisecondsSinceEpoch}',
        flush: true,
      );
    } catch (e) {
      debugPrint('persist vo state failed: $e');
    }
  }

  /// 读一个可能不被当前 mpv 构建支持的属性（不支持时返回 null，不抛异常）。
  Future<String?> _safeMpvProperty(String name) async {
    // 捕获局部引用：await 期间播放器可能被 recycle/dispose 置 null，
    // 用 `_player!` 会直接抛异常并被吞成「属性不支持」，制造假空值。
    final p = _player;
    if (p == null) return null;
    try {
      return await getMpvProperty(p, name);
    } catch (_) {
      return null;
    }
  }

  /// 供上层读 mpv 原生属性（首帧 / 解码证据等）。
  ///
  /// 磁力首帧看门狗要用 `estimated-vf-fps` 区分「解析出时长但一帧没解」
  /// 与「真的出画」；这个属性读失败一律返回 null，调用方按「无证据」处理。
  Future<String?> mpvProperty(String name) => _safeMpvProperty(name);

  /// 把 mpv 的帧率写进日志（fd 泄漏排查专用）。
  ///
  /// 2026-10-23：真机日志显示 fd 泄漏速率稳定在 ~24/s，与「每送显一帧漏一个
  /// fd」的假设吻合，但日志里**没有任何帧率数据**，该假设只能靠猜。这里补记
  /// `estimated-vf-fps`（实际送显帧率）与 `container-fps`（容器帧率），下次
  /// 真机复现时可直接比对「泄漏 fd/s ≈ 送显帧率」是否成立。
  Future<void> probeFrameRate() async {
    if (kIsWeb || _player == null) return;
    final vf = await _safeMpvProperty('estimated-vf-fps');
    final cf = await _safeMpvProperty('container-fps');
    if (vf == null && cf == null) return;
    DebugLog.log(
      'Play',
      '帧率: estimated-vf-fps=${vf ?? '?'} container-fps=${cf ?? '?'}',
    );
  }

  /// 缓存/预读实时状态。
  ///
  /// `demuxer-cache-time` 才是 mpv 真正「已解封装、可立即播放」的缓冲末端，
  /// 比 media_kit 的 `state.buffer` 更能反映预读是否生效；用于诊断「缓冲永远
  /// 贴着播放位置」到底是预读没下发，还是 HLS 分支不吃该参数。
  Future<void> probeCacheState() async {
    if (kIsWeb || _player == null) return;
    final ct = await _safeMpvProperty('demuxer-cache-time');
    final cd = await _safeMpvProperty('demuxer-cache-duration');
    final idle = await _safeMpvProperty('demuxer-cache-idle');
    final bs = await _safeMpvProperty('cache-buffering-state');
    final sp = await _safeMpvProperty('cache-speed');
    // 「本地磁力流到底还在不在供数」的唯一直接证据：
    // `raw-input-rate` 是 demuxer 每秒从输入（我们的本地 HTTP 流）吃进的字节数。
    // 2026-11-08 真机现场，画面每 5 分钟才前进一帧，但当时没有任何一路数据
    // 能区分「种子断供」与「本地服务器堵住」——加上这三项即可一眼定案：
    //   raw-input-rate≈0 && eof-reached=yes → 流被对端关掉了（EOF）
    //   raw-input-rate 正常 && cache 在涨 → 问题在解码/送显，不在数据
    final inRate = await _safeMpvProperty('raw-input-rate');
    final eof = await _safeMpvProperty('eof-reached');
    final fsz = await _safeMpvProperty('file-size');
    // inst 标记用于验收「连续读数来自同一个播放器实例」。
    // 第九轮：mpv 读不到属性时可能返回空字符串而不是 null，旧判据
    // `ct != null && cd != null` 会把「读到了空串」误判成有效观测，
    // 使 probe=ok 比例虚高、空值率口径失真。只有能解析成数值才算有效。
    final ok = double.tryParse(ct ?? '') != null
        && double.tryParse(cd ?? '') != null;
    DebugLog.log(
      'Play',
      '缓存: runId=${PlaybackExperiment.runId} inst=$_probeId '
          'probe=${ok ? 'ok' : 'stale'} '
          'demuxer-cache-time=$ct cache-duration=$cd idle=$idle '
          'buffering-state=$bs cache-speed=$sp raw-input-rate=$inRate '
          'eof=$eof file-size=$fsz',
      flush: true,
    );
  }

  /// 把**实际生效**的播放速率写进日志（排查「正常播放却像被跳过片段」）。
  ///
  /// 2026-11-04：用户日志显示心跳每 30s 前进 57~62s（≈2x），同段却零纠偏记录，
  /// 但日志里没有任何 rate 数据，无法判断是「倍速卡住」还是「时间轴错位」。
  /// 这里每心跳读一次 mpv 的 `speed` 并与模块字段对照：两者不一致就说明
  /// setRate 没落到当前实例上（旧实例已 dispose / 新实例没应用）。
  Future<void> probePlaybackRate() async {
    if (kIsWeb || _player == null) return;
    final speed = await _safeMpvProperty('speed');
    final pitch = await _safeMpvProperty('audio-pitch-correction');
    DebugLog.log(
      'Speed',
      'mpv speed=${speed ?? '?'} audio-pitch-correction=${pitch ?? '?'} '
          '模块 playbackSpeed=$_playbackSpeed',
    );
  }

  /// 位置跳变取证：原始上报相对上一次的位移超过阈值就落盘。
  ///
  /// 判据是「位移偏离预期」而不是「位移大小」：
  /// 按当前播放速率，墙钟过去 [wall] 毫秒，位置本该前进 `wall * rate`；
  /// 实际位移与这个预期相差超过 [_jumpMinMs] 才算异常。
  ///
  /// 为什么不再用「两次上报间隔 <=1.5s」当门槛：用户报的「跳几分钟」是静置
  /// 观看时出现的，那时上报本来就稀疏，老逻辑会把整段都丢弃——199 次里只记到
  /// 1~2 条，最关键的现场反而抓不到。改用速率预期后，间隔多长都不影响判定。
  ///
  /// 打点带三个关键信息：
  /// - `appSeek`：最近 3s 内 App 是否主动 seek 过（含调用方文件:行号与目标位置）；
  /// - `buffering`：跳变瞬间是否处于缓冲态（对应录屏里那一下 rebuffer）；
  /// - 随后异步读 mpv 的 time-pos / playback-time（两者脱节 = 分片 pts 问题，
  ///   不是 seek）。
  void _detectPositionJump(Duration pos, int nowMs) {
    final last = _lastRawPos;
    final lastMs = _lastRawPosMs;
    _lastRawPos = pos;
    _lastRawPosMs = nowMs;
    if (last == null || lastMs == 0) return;
    final wall = nowMs - lastMs;
    if (wall <= 0) return;

    final deltaMs = pos.inMilliseconds - last.inMilliseconds;
    // 位置一点没动（暂停 / 缓冲卡住 / 卡死）：不是跳变，交给停滞看门狗。
    if (deltaMs == 0) return;

    final rate = _playbackSpeed <= 0 ? 1.0 : _playbackSpeed;
    final expected = (wall * rate).round();
    final deviation = deltaMs - expected;
    if (deviation.abs() < _jumpMinMs) return;

    final sinceSeek =
        _lastSeekAtMs == 0 ? -1 : nowMs - _lastSeekAtMs;
    final appSeek = sinceSeek >= 0 && sinceSeek < 3000
        ? '${_lastSeekSource.isEmpty ? '?' : _lastSeekSource}'
            '@+${sinceSeek}ms target=${_lastSeekTarget?.inSeconds ?? -1}s'
        : 'none';
    DebugLog.log(
      'Jump',
      '位置跳变 ${last.inMilliseconds}ms -> ${pos.inMilliseconds}ms '
          '(delta=${deltaMs >= 0 ? '+' : ''}${deltaMs}ms '
          'expected=${expected}ms deviation=${deviation >= 0 ? '+' : ''}${deviation}ms '
          'wall=${wall}ms) '
          'appSeek=$appSeek buffering=$_lastBuffering '
          'rate=$_playbackSpeed',
      flush: true,
    );
    unawaited(_logJumpMpvState(pos));
  }

  /// 跳变瞬间读一次 mpv 侧时间轴，区分「真的 seek 了」和「时间戳本身错乱」。
  Future<void> _logJumpMpvState(Duration pos) async {
    if (kIsWeb || _player == null) return;
    final tp = await _safeMpvProperty('time-pos');
    final pt = await _safeMpvProperty('playback-time');
    final seeking = await _safeMpvProperty('seeking');
    final cacheT = await _safeMpvProperty('demuxer-cache-time');
    final cacheD = await _safeMpvProperty('demuxer-cache-duration');
    final bufState = await _safeMpvProperty('cache-buffering-state');
    DebugLog.log(
      'Jump',
      'mpv 快照 time-pos=$tp playback-time=$pt seeking=$seeking '
          'demuxer-cache-time=$cacheT cache-duration=$cacheD '
          'buffering-state=$bufState (上报=${pos.inMilliseconds}ms)',
      flush: true,
    );
  }

  /// 记录一次 App 主动 seek 的来源（文件:行号），供 [_detectPositionJump] 对照。
  void _markAppSeek(String source, Duration target) {
    _lastSeekSource = source;
    _lastSeekTarget = target;
    _lastSeekAtMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// 从当前调用栈里取第一个非本文件的帧，作为 seek 发起方标记。
  String _seekCallerTag() {
    final lines = StackTrace.current.toString().split('\n');
    for (final line in lines) {
      final t = line.trim();
      if (!t.startsWith('#')) continue;
      if (t.contains('player_service.dart')) continue;
      if (t.contains('dart:async')) continue;
      // #3  DetailPlayer.seek (package:.../detail_player.dart:1163:17)
      final open = t.indexOf('(');
      if (open < 0) return t;
      final body = t.substring(open + 1).split(' ').first;
      final parts = body.split('/');
      final fileLine = parts.length > 1 ? parts.last : body;
      return fileLine.replaceAll(')', '');
    }
    return 'unknown';
  }

  /// 跳转到指定位置（精确 seek，松手时用）
  Future<void> seek(Duration position) async {
    await seekPrecise(position);
  }

  /// 拖动进度条：关键帧快速 seek，减少卡顿。
  Future<void> seekFast(Duration position) async {
    if (_player == null) return;
    _markAppSeek('seekFast/${_seekCallerTag()}', position);
    try {
      final done = await runMpvCommand(_player!, [
        'seek',
        '${position.inMicroseconds / 1e6}',
        'absolute',
        'keyframes',
      ]);
      if (done) return;
    } catch (e) {
      debugPrint('mpv fast seek failed: $e');
    }
    await _player!.seek(position);
  }

  /// 精确 seek（松手 / 点击定位）
  Future<void> seekPrecise(Duration position) async {
    if (_player == null) return;
    // 记来源：栈里第一个非 player_service.dart 的帧，就是真正发起方。
    _markAppSeek('precise/${_seekCallerTag()}', position);
    if (_strategyConfig.hrSeek == 'yes') {
      try {
        final done = await runMpvCommand(_player!, [
          'seek',
          '${position.inMicroseconds / 1e6}',
          'absolute',
        ]);
        if (done) return;
      } catch (e) {
        debugPrint('mpv precise seek failed: $e');
      }
    }
    await _player!.seek(position);
  }

  /// 设置播放速度
  Future<void> setRate(double rate) async {
    await _player?.setRate(rate);
  }

  /// 设置音量（0–200；mpv 常可超过 100，失败时回退到 0–100）
  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 200.0);
    if (_player == null) return;
    try {
      await _player!.setVolume(v);
    } catch (_) {
      await _player!.setVolume(v.clamp(0.0, 100.0));
    }
  }

  /// 停止播放
  Future<void> stop() async {
    await _player?.stop();
  }

  /// 释放播放器
  Future<void> dispose() async {
    _disposed = true;
    // 门 0：页面退出必须停掉探针，否则旧实例会一直写全空缓存行。
    _experimentTimer?.cancel();
    _experimentTimer = null;
    if (identical(_activeProbeOwner, this)) {
      _activeExperimentTimer?.cancel();
      _activeExperimentTimer = null;
      _activeProbeOwner = null;
    }
    final pendingPlay = _playChain;
    if (pendingPlay != null) {
      try {
        await pendingPlay;
      } catch (_) {}
    }

    // 统一释放：作用域内含全部流订阅 + 播放器 + 控制器，逆序释放且单项失败隔离。
    await _scope.dispose();

    // 停止并释放播放器
    await _player?.stop();
    await _player?.dispose();
    _player = null;
    _videoController = null;
    _playChain = null;

    // 事件通道随服务一起失效，清空以免外部持有残留引用。
    playingChanged.clear();
    positionChanged.clear();
    durationChanged.clear();
    bufferingChanged.clear();
    bufferChanged.clear();
    completed.clear();
    error.clear();
    rateChanged.clear();
    audioBitrateChanged.clear();
    videoSizeChanged.clear();
    subtitle.clear();
  }

  /// 释放旧 Player/VideoController 并新建实例续播。
  ///
  /// 仅用于运行时手动切换视频输出后端（vo）—— 改变 vo 必须重建 VideoController
  /// 才会生效。事件通道不重建，外部订阅者持续有效。
  Future<void> recyclePlayer() async {
    if (_recycling || _disposed || _player == null) return;
    final url = _currentUrl;
    if (url == null || url.isEmpty) return;
    _recycling = true;
    try {
      final wasPlaying = _player!.state.playing;
      final pos = _player!.state.position;
      final rate = _playbackSpeed;
      await _scope.dispose();
      await _player!.stop().catchError((_) {});
      await _player!.dispose().catchError((_) {});
      _player = null;
      _videoController = null;

      _scope = ResourceScope(name: 'player');
      _player = Player(configuration: _playerConfiguration());
      await _applyMpvTuning();
      // 矩阵测试专用：回收重建后同样要重新下发 gpu-api 覆盖（新 Player）。
      if (debugGpuApiOverride != null) {
        try {
          await setMpvProperty(_player!, 'gpu-api', debugGpuApiOverride!);
        } catch (_) {}
      }
      await _player!.setVolume(100.0);
      _videoController = VideoController(
        _player!,
        configuration: _videoControllerConfig(),
      );
      await _pushSubtitleVisibility();
      _wireStreams();

      recycleEpoch++;
      onPlayerRecreated?.call();

      if (wasPlaying) {
        await _playInternal(url, startAt: pos > Duration.zero ? pos : null);
      } else {
        await _player!.open(Media(url), play: false);
        await _pushSubtitleVisibility();
        if (pos > Duration.zero) {
          await waitUntilSeekable(pos);
          await _seekForOpenStart(pos);
        }
      }
      if (rate != 1.0) {
        // 记录「非 1.0 速率被带进新实例」这件事：长按 2x 若在重建瞬间没复位，
        // 2.0 会被新播放器沿用，之后整场都是 2 倍速（用户观感=剧情被跳过）。
        DebugLog.log(
          'Speed',
          'recyclePlayer 继承旧 rate=$rate（新实例继续沿用）',
          flush: true,
        );
        await _player!.setRate(rate);
      }
    } catch (e) {
      DebugLog.log('Play', 'recyclePlayer 失败: $e', flush: true);
    } finally {
      _recycling = false;
    }
  }

  /// 释放播放器**实例**（mpv Player/VideoController + 全部流订阅），服务保持可用。
  ///
  /// 与 [dispose] 的分界：本服务是**单例**，页面级关闭（退出详情页）只应释放
  /// 播放器实例以回收 mpv 占用的内存/fd，**不允许**把单例标记为已销毁——
  /// `_disposed` 一旦置位便无任何路径复位，之后所有播放入口静默短路，
  /// 表现为「再打开任何视频都没反应」。单例的生死只归应用退出路径
  /// （`PlayerProvider.dispose` → [dispose]）。
  ///
  /// 语义等价于「回收但不续播」：新建作用域、置空实例；下次播放经 [init]
  /// 懒重建（`init` 对 `_player == null` 会重建实例并重新接流）。
  /// 事件通道不动，因此外部订阅者（详情页 / 迷你播放器）持续有效。
  Future<void> releasePlayerInstance() async {
    final pendingPlay = _playChain;
    if (pendingPlay != null) {
      try {
        await pendingPlay;
      } catch (_) {}
    }
    await _scope.dispose();
    await _player?.stop().catchError((_) {});
    await _player?.dispose().catchError((_) {});
    _player = null;
    _videoController = null;
    _playChain = null;
    _currentUrl = null;
    DebugLog.log('Play', 'releasePlayerInstance: 实例已释放，服务保持可用');
  }

  /// 获取播放器实例
  Player? get player => _player;

  /// 检查是否支持播放
  ///
  /// media_kit 在 Web 上走 HTML <video> + hls.js，同样可用，因此全平台为 true。
  static bool get isSupported => true;

  /// 设置亮度
  void setBrightness(double brightness) {
    // 亮度控制逻辑
  }

  /// 进入全屏
  void enterFullScreen() {
    // 进入全屏逻辑
  }

  /// 退出全屏
  void exitFullScreen() {
    // 退出全屏逻辑
  }

  /// 设置自动播放下一集
  Future<void> setAutoPlayNext(bool value) async {
    _autoPlayNext = value;
  }

  /// 开始播放
  Future<void> startPlaying(String url) async {
    await play(url);
  }

  /// 跳转到指定位置
  Future<void> seekTo(int milliseconds) async {
    await seek(Duration(milliseconds: milliseconds));
  }

  /// 设置播放速度
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    await setRate(speed);
  }
}
