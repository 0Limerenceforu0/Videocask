import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 播放器服务
///
/// 统一处理播放器的初始化、播放控制、进度管理等逻辑
class PlayerService {
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

  /// 位置更新节流时间戳
  int _lastPositionUpdateMs = 0;

  /// 位置更新节流间隔（毫秒）
  static const _positionThrottleMs = 200;

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

    _player = Player();
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
        onVideoSizeChanged?.call(_lastVideoWidth, _lastVideoHeight);
      }),
    );

    _subscriptions.add(
      _player!.stream.height.listen((h) {
        _lastVideoHeight = h;
        onVideoSizeChanged?.call(_lastVideoWidth, _lastVideoHeight);
      }),
    );

    _subscriptions.add(
      _player!.stream.subtitle.listen((lines) {
        onSubtitle?.call(lines);
      }),
    );
  }

  /// 播放视频
  Future<void> play(String url) async {
    if (_player == null) {
      await init();
    }
    await _player!.open(Media(url), play: true);
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

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
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
  }

  /// 获取播放器实例
  Player? get player => _player;

  /// 检查是否支持播放
  static bool get isSupported => !kIsWeb;

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
