import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'playback_strategy.dart';
import 'playback_start_seek_exception.dart';
// mpv 专有能力按平台分发（Web 上 NativePlayer 无相关方法）
import 'player_mpv.dart';

/// 播放器服务
///
/// 统一处理播放器的初始化、播放控制、进度管理等逻辑
class PlayerService {
  /// demuxer 读缓存（默认 32MB 偏小，网络流首帧/拖动后恢复偏慢）
  static const int defaultDemuxerBufferBytes = 96 * 1024 * 1024;

  PlaybackStrategyConfig _strategyConfig =
      PlaybackStrategyConfig.fromKey('balanced');

  PlaybackStrategyConfig get strategyConfig => _strategyConfig;

  /// 播放器实例
  Player? _player;

  /// 视频控制器
  VideoController? _videoController;

  /// 播放器流订阅列表
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// 播放状态回调
  Function(bool)? onPlayingChanged;

  /// 位置更新回调
  Function(Duration)? onPositionChanged;

  /// 时长更新回调
  Function(Duration)? onDurationChanged;

  /// 缓冲状态回调
  Function(bool)? onBufferingChanged;

  /// 缓冲进度回调
  Function(Duration)? onBufferChanged;

  /// 播放完成回调
  Function()? onCompleted;

  /// 错误回调
  Function(String)? onError;

  /// 播放倍速（与 [Player.stream.rate] 同步）
  Function(double)? onRateChanged;

  /// 音频码率（bits/s，来自 mpv `audio-bitrate`，可能为 null）
  Function(double?)? onAudioBitrateChanged;

  /// 视频分辨率
  Function(int? width, int? height)? onVideoSizeChanged;

  /// 当前显示的内嵌字幕行
  Function(List<String> lines)? onSubtitle;

  int? _lastVideoWidth;
  int? _lastVideoHeight;
  int _videoRotate = 0;

  int get videoRotate => _videoRotate;

  /// 位置更新节流时间戳
  int _lastPositionUpdateMs = 0;

  /// 位置更新节流间隔（毫秒）
  static const _positionThrottleMs = 200;

  Future<void>? _playChain;
  bool _disposed = false;

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

  /// 初始化播放器
  Future<void> init() async {
    if (_player != null) return;

    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: _strategyConfig.demuxerBufferBytes,
      ),
    );
    await _applyMpvTuning(hardwareDecode: true);
    // 显式设置音量为最大，确保有声音
    await _player!.setVolume(100.0);
    _videoController = VideoController(_player!);

    // 监听播放状态
    _subscriptions.add(
      _player!.stream.playing.listen((playing) {
        onPlayingChanged?.call(playing);
      }),
    );

    // 监听位置（节流：每200ms更新一次UI）
    _subscriptions.add(
      _player!.stream.position.listen((position) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastPositionUpdateMs < _positionThrottleMs) return;
        _lastPositionUpdateMs = now;
        onPositionChanged?.call(position);
      }),
    );

    // 监听时长
    _subscriptions.add(
      _player!.stream.duration.listen((duration) {
        onDurationChanged?.call(duration);
      }),
    );

    // 监听缓冲状态
    _subscriptions.add(
      _player!.stream.buffering.listen((buffering) {
        onBufferingChanged?.call(buffering);
      }),
    );

    // 监听缓冲进度
    _subscriptions.add(
      _player!.stream.buffer.listen((buffer) {
        onBufferChanged?.call(buffer);
      }),
    );

    // 监听完成
    _subscriptions.add(
      _player!.stream.completed.listen((completed) {
        if (completed) {
          onCompleted?.call();
        }
      }),
    );

    // 监听错误
    _subscriptions.add(
      _player!.stream.error.listen((error) {
        onError?.call(error.toString());
      }),
    );

    _subscriptions.add(
      _player!.stream.rate.listen((rate) {
        onRateChanged?.call(rate);
      }),
    );

    _subscriptions.add(
      _player!.stream.audioBitrate.listen((bitrate) {
        onAudioBitrateChanged?.call(bitrate);
      }),
    );

    _subscriptions.add(
      _player!.stream.width.listen((w) {
        _lastVideoWidth = w;
        _emitVideoSizeIfReady();
      }),
    );

    _subscriptions.add(
      _player!.stream.height.listen((h) {
        _lastVideoHeight = h;
        _emitVideoSizeIfReady();
      }),
    );

    _subscriptions.add(
      _player!.stream.subtitle.listen((lines) {
        onSubtitle?.call(lines);
      }),
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
    onVideoSizeChanged?.call(w, h);
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
  Future<void> play(String url, {Duration? startAt}) async {
    final previous = _playChain;
    final current = _playInternal(url, startAt: startAt);
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

  Future<void> _playInternal(String url, {Duration? startAt}) async {
    if (_disposed) return;
    if (_player == null) {
      await init();
    }
    if (_disposed || _player == null) return;
    // 换片源时重置字幕偏移，避免上一集调过的时间轴带到新片源。
    if (_subtitleDelaySeconds != 0) {
      _subtitleDelaySeconds = 0;
      await _applySubtitleDelay();
    }
    final resume = startAt != null && startAt > Duration.zero ? startAt : null;
    if (resume != null) {
      await _player!.open(Media(url), play: false);
      if (_disposed) return;
      await _seekForOpenStart(resume);
      if (_disposed) return;
      await _player!.play();
      return;
    }
    await _player!.open(Media(url), play: true);
  }

  /// open 后 seek 到续播点；失败则抛 [PlaybackStartSeekException]（禁止静默从 0 播）。
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

    debugPrint(
      'startAt seek failed: target=${target.inSeconds}s actual=${actual.inSeconds}s',
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
  Future<void> setExternalSubtitleFromFile(String filePath) async {
    if (kIsWeb || _player == null) return;
    await _player!.setSubtitleTrack(
      SubtitleTrack.uri(
        Uri.file(filePath).toString(),
        title: 'External',
      ),
    );
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

  /// 按用户播放策略与硬件解码开关调优 mpv。
  Future<void> applyPlaybackStrategy(
    PlaybackStrategyConfig config, {
    required bool hardwareDecode,
  }) async {
    _strategyConfig = config;
    if (_player == null) return;
    await _applyMpvTuning(hardwareDecode: hardwareDecode);
  }

  Future<void> _applyMpvTuning({required bool hardwareDecode}) async {
    if (kIsWeb || _player == null) return;

    final c = _strategyConfig;
    final props = <String, String>{
      'hr-seek': c.hrSeek,
      'demuxer-seekable-cache': c.demuxerSeekableCache,
      'cache-secs': '${c.cacheSecs}',
      'network-timeout': '${c.networkTimeoutSecs}',
      'hwdec': hardwareDecode ? 'auto-safe' : 'no',
    };

    for (final entry in props.entries) {
      try {
        await setMpvProperty(_player!, entry.key, entry.value);
      } catch (e) {
        debugPrint('mpv setProperty ${entry.key} failed: $e');
      }
    }
  }

  /// 跳转到指定位置（精确 seek，松手时用）
  Future<void> seek(Duration position) async {
    await seekPrecise(position);
  }

  /// 拖动进度条：关键帧快速 seek，减少卡顿。
  Future<void> seekFast(Duration position) async {
    if (_player == null) return;
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
    final pendingPlay = _playChain;
    if (pendingPlay != null) {
      try {
        await pendingPlay;
      } catch (_) {}
    }
    // 取消所有流订阅
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    // 停止并释放播放器
    await _player?.stop();
    await _player?.dispose();
    _player = null;
    _videoController = null;
    _playChain = null;
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
