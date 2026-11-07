import 'dart:async';
import 'package:flutter/material.dart';
import '../services/player_service.dart';

/// 播放器状态枚举
enum PlayerStatus {
  idle, // 空闲
  loading, // 加载中
  playing, // 播放中
  paused, // 暂停
  completed, // 播放完成
  error // 错误
}

/// 播放器状态管理
class PlayerProvider extends ChangeNotifier {
  final PlayerService _playerService = PlayerService();

  /// 是否已初始化（防止重复订阅事件通道）。
  bool _initialized = false;

  /// 当前播放状态
  PlayerStatus _status = PlayerStatus.idle;

  /// 当前播放状态
  PlayerStatus get status => _status;

  /// 当前播放位置
  Duration _position = Duration.zero;

  /// 当前播放位置
  Duration get position => _position;

  /// 总时长
  Duration _duration = Duration.zero;

  /// 总时长
  Duration get duration => _duration;

  /// 缓冲位置
  Duration _bufferedPosition = Duration.zero;

  /// 缓冲位置
  Duration get bufferedPosition => _bufferedPosition;

  /// 是否全屏
  bool _isFullScreen = false;

  /// 是否全屏
  bool get isFullScreen => _isFullScreen;

  /// 是否显示控制栏
  bool _showControls = true;

  /// 是否显示控制栏
  bool get showControls => _showControls;

  /// 播放速度
  double _playbackSpeed = 1.0;

  /// 播放速度
  double get playbackSpeed => _playbackSpeed;

  /// 当前亮度
  double _brightness = 0.5;

  /// 当前亮度
  double get brightness => _brightness;

  /// 当前音量
  double _volume = 1.0;

  /// 当前音量
  double get volume => _volume;

  /// 当前影片ID
  String _movieId = '';

  /// 当前影片ID
  String get movieId => _movieId;

  /// 当前影片名称
  String _movieName = '';

  /// 当前影片名称
  String get movieName => _movieName;

  /// 当前影片封面
  String _movieCover = '';

  /// 当前影片封面
  String get movieCover => _movieCover;

  /// 当前集数索引
  int _episodeIndex = 0;

  /// 当前集数索引
  int get episodeIndex => _episodeIndex;

  /// 自动连播
  bool _autoPlayNext = true;

  /// 自动连播
  bool get autoPlayNext => _autoPlayNext;

  // ========== 画中画（迷你播放器）相关 ==========

  /// 是否显示迷你播放器（画中画模式）
  bool _isMiniPlayer = false;

  /// 是否显示迷你播放器
  bool get isMiniPlayer => _isMiniPlayer;

  /// 迷你播放器是否正在播放
  bool _isMiniPlayerPlaying = true;

  /// 迷你播放器是否正在播放
  bool get isMiniPlayerPlaying => _isMiniPlayerPlaying;

  /// 进入迷你播放器模式（画中画）
  void enterMiniPlayer({
    required String movieId,
    required String movieName,
    required String movieCover,
    String sourceId = '',
  }) {
    _movieId = movieId;
    _movieName = movieName;
    _movieCover = movieCover;
    _isMiniPlayer = true;
    _isMiniPlayerPlaying = true;
    notifyListeners();
  }

  /// 退出迷你播放器模式
  void exitMiniPlayer() {
    _isMiniPlayer = false;
    notifyListeners();
  }

  /// 切换迷你播放器播放/暂停
  void toggleMiniPlayerPlayPause() {
    _isMiniPlayerPlaying = !_isMiniPlayerPlaying;
    notifyListeners();
  }

  /// 初始化
  ///
  /// 订阅的是 [PlayerService] 的**事件通道**（多播），而不是某个 Player 实例的
  /// stream —— 播放器实例被回收重建后通道依然有效，本 Provider 无需重新订阅，
  /// 也就不会出现「回收一次，进度/时长永久冻结」。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _playerService.init();
    _autoPlayNext = _playerService.autoPlayNext;
    _playbackSpeed = _playerService.playbackSpeed;

    _playerService.positionChanged.add(_handlePosition);
    _playerService.durationChanged.add(_handleDuration);
    _playerService.bufferChanged.add(_handleBuffer);
    _playerService.playingChanged.add(_handlePlaying);
    _playerService.completed.add(_handleCompleted);
  }

  void _handlePosition(Duration pos) {
    _position = pos;
    notifyListeners();
  }

  void _handleDuration(Duration dur) {
    _duration = dur;
    notifyListeners();
  }

  void _handleBuffer(Duration buf) {
    _bufferedPosition = buf;
    notifyListeners();
  }

  void _handlePlaying(bool isPlaying) {
    _status = isPlaying ? PlayerStatus.playing : PlayerStatus.paused;
    notifyListeners();
  }

  void _handleCompleted(int _) {
    _status = PlayerStatus.completed;
    notifyListeners();
  }

  /// 开始播放
  Future<void> startPlaying({
    required String url,
    required String movieId,
    required String movieName,
    required String movieCover,
    required int episodeIndex,
    required String episodeName,
    String sourceId = '',
  }) async {
    _movieId = movieId;
    _movieName = movieName;
    _episodeIndex = episodeIndex;
    _status = PlayerStatus.loading;
    notifyListeners();

    await _playerService.startPlaying(url);
  }

  /// 跳转
  Future<void> seekTo(Duration position) async {
    await _playerService.seekTo(position.inMilliseconds);
  }

  /// 设置播放速度
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    await _playerService.setPlaybackSpeed(speed);
    notifyListeners();
  }

  /// 设置音量
  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _playerService.setVolume(volume);
    notifyListeners();
  }

  /// 设置亮度
  void setBrightness(double brightness) {
    _brightness = brightness;
    _playerService.setBrightness(brightness);
    notifyListeners();
  }

  /// 切换全屏
  Future<void> toggleFullScreen() async {
    _isFullScreen = !_isFullScreen;
    if (_isFullScreen) {
      _playerService.enterFullScreen();
    } else {
      _playerService.exitFullScreen();
    }
    notifyListeners();
  }

  /// 切换控制栏显示
  void toggleControls() {
    _showControls = !_showControls;
    notifyListeners();
  }

  /// 设置自动连播
  Future<void> setAutoPlayNext(bool value) async {
    _autoPlayNext = value;
    await _playerService.setAutoPlayNext(value);
    notifyListeners();
  }

  /// 获取播放器服务
  PlayerService get playerService => _playerService;

  /// 释放资源
  @override
  void dispose() {
    // 从事件通道摘除本页注册的监听（多播：只摘自己的，不影响其它消费者）。
    _playerService.positionChanged.remove(_handlePosition);
    _playerService.durationChanged.remove(_handleDuration);
    _playerService.bufferChanged.remove(_handleBuffer);
    _playerService.playingChanged.remove(_handlePlaying);
    _playerService.completed.remove(_handleCompleted);
    unawaited(_playerService.dispose());
    super.dispose();
  }
}
