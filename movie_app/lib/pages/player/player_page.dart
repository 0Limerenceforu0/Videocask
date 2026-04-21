import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../../services/video_parser.dart';
import '../../services/player_service.dart';
import '../../utils/cache_speed_formatter.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/history_provider.dart';
import '../../widgets/speed_selector.dart';
import '../../widgets/quality_selector.dart';
import '../../widgets/subtitle_selector.dart';

/// 播放器页面
class PlayerPage extends StatefulWidget {
  /// 播放地址
  final String url;

  /// 标题
  final String title;

  /// 集数索引
  final int episodeIndex;

  /// 影片ID
  final String movieId;

  /// 源ID
  final String sourceId;

  /// 源名称（用于显示当前播放源）
  final String sourceName;

  const PlayerPage({
    super.key,
    required this.url,
    required this.title,
    this.episodeIndex = 0,
    this.movieId = '',
    this.sourceId = '',
    this.sourceName = '',
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  /// 播放器服务
  final PlayerService _playerService = PlayerService();

  /// 播放器实例（用于兼容旧代码）
  Player? get _player => _playerService.player;

  /// 控制栏显示定时器
  Timer? _hideTimer;

  /// 是否显示控制栏
  bool _showControls = true;

  /// 是否全屏
  bool _isFullScreen = false;

  /// 当前位置
  Duration _position = Duration.zero;

  /// 总时长
  Duration _duration = Duration.zero;

  /// 缓冲位置
  Duration _bufferedPosition = Duration.zero;

  /// 缓存速度（字节/秒）
  int _cacheSpeed = 0;

  /// 鼠标悬停状态
  bool _isHovering = false;

  /// 是否显示缩略图
  bool _showThumbnail = false;

  /// 缩略图位置
  Offset _thumbnailPosition = Offset.zero;

  /// 缩略图时间点
  Duration _thumbnailDuration = Duration.zero;

  /// 是否正在播放
  bool _isPlaying = false;

  /// 是否正在缓冲
  bool _isBuffering = false;

  /// 播放速度
  double _playbackSpeed = 1.0;

  /// 音量
  // ignore: unused_field, prefer_final_fields
  double _volume = 1.0;

  /// 亮度
  // ignore: unused_field, prefer_final_fields
  double _brightness = 0.5;

  /// 是否正在拖拽进度
  bool _isDragging = false;

  /// 拖拽位置
  Duration _dragPosition = Duration.zero;

  /// 错误信息
  String _errorMessage = '';

  /// 重试次数
  int _retryCount = 0;

  /// 最大重试次数
  static const int maxRetryCount = 3;

  /// 缓存的 HistoryProvider 引用，用于 dispose 中保存进度
  HistoryProvider? _savedHistoryProvider;

  /// 缓存的 PlayerProvider 引用，用于 dispose 中读取配置
  PlayerProvider? _savedPlayerProvider;

  /// 缓存速度计算相关变量
  int _lastBufferPosition = 0;
  int _lastBufferTime = 0;

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _startHideTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 缓存 provider 引用，避免在 dispose 中使用已失效的 context
    _savedHistoryProvider = context.read<HistoryProvider>();
    _savedPlayerProvider = context.read<PlayerProvider>();

    // 读取用户设置的默认播放速度
    if (_playbackSpeed == 1.0) {
      final settingsProvider = context.read<SettingsProvider>();
      final defaultSpeed = settingsProvider.defaultSpeed;
      if (defaultSpeed != 1.0 && defaultSpeed > 0) {
        _playbackSpeed = defaultSpeed;
        _player?.setRate(_playbackSpeed);
      }
    }
  }

  /// 初始化播放器
  void _initPlayer() async {
    String videoUrl = widget.url;

    // 如果是网页链接，先解析为真实视频地址
    if (_isWebUrl(videoUrl)) {
      setState(() {
        _isBuffering = true;
        _errorMessage = '';
      });

      final parser = VideoParser();
      final parsedUrl = await parser.parseVideoUrl(videoUrl);

      if (parsedUrl != null) {
        videoUrl = parsedUrl;
      } else {
        if (mounted) {
          setState(() {
            _isBuffering = false;
            _errorMessage = '解析播放地址失败';
          });
        }
        return;
      }
    }

    if (!mounted) return;

    // 设置播放器回调
    _playerService.onPlayingChanged = (playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
        });
      }
    };

    _playerService.onPositionChanged = (position) {
      if (mounted && !_isDragging) {
        setState(() {
          _position = position;
        });
      }
    };

    _playerService.onDurationChanged = (duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    };

    _playerService.onBufferingChanged = (buffering) {
      if (mounted) {
        setState(() {
          _isBuffering = buffering;
        });
      }
    };

    _playerService.onBufferChanged = (buffer) {
      if (mounted) {
        setState(() {
          _bufferedPosition = buffer;
        });

        // 计算缓存速度
        final now = DateTime.now().millisecondsSinceEpoch;
        final deltaTime = now - _lastBufferTime;
        if (deltaTime > 0) {
          final deltaBuffer = buffer.inMilliseconds - _lastBufferPosition;
          if (deltaBuffer > 0) {
            // 计算字节/秒（假设1毫秒的缓冲对应100KB数据，实际需要根据视频编码和分辨率调整）
            _cacheSpeed = (deltaBuffer * 100 * 1024 * 1000) ~/ deltaTime;
          }
        }
        _lastBufferPosition = buffer.inMilliseconds;
        _lastBufferTime = now;
      }
    };

    _playerService.onCompleted = () {
      if (mounted) {
        _onPlaybackCompleted();
      }
    };

    _playerService.onError = (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error;
        });
        _handleError();
      }
    };

    // 设置系统方向
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (!mounted) return;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // 开始播放
    await _playerService.play(videoUrl);
    if (!mounted) return;
  }

  /// 检测是否为网页链接（非直接视频地址）
  bool _isWebUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    // 直接视频格式，不是网页链接
    if (lower.endsWith('.m3u8') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.flv') ||
        lower.contains('.m3u8?') ||
        lower.contains('.mp4?')) {
      return false;
    }
    // 以 http/https 开头的链接视为网页链接
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return true;
    }
    return false;
  }

  /// 处理错误
  void _handleError() async {
    if (_retryCount < maxRetryCount) {
      _retryCount++;
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      await _playerService.play(widget.url);
    }
  }

  /// 播放完成
  void _onPlaybackCompleted() {
    // 保存观看进度
    _saveProgress();

    // 自动下一集（如果启用）
    final playerProvider = _savedPlayerProvider;
    if (playerProvider != null && playerProvider.autoPlayNext) {
      _showAutoPlayNextDialog();
    }
  }

  /// 显示自动下一集对话框
  void _showAutoPlayNextDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('播放完成'),
        content: const Text('是否播放下一集？'),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              context.pop();
              _playNext();
            },
            child: const Text('下一集'),
          ),
        ],
      ),
    );
  }

  /// 播放下一集
  void _playNext() {
    context.pop();
    // 返回详情页，由详情页处理下一集逻辑
  }

  /// 保存播放进度
  void _saveProgress() {
    if (widget.movieId.isEmpty) return;

    // 使用缓存的 provider 引用，避免在 dispose 中使用已失效的 context
    final historyProvider = _savedHistoryProvider;
    if (historyProvider == null) return;

    // 检查是否为磁力链接
    String? magnetUri;
    if (widget.url.startsWith('magnet:')) {
      magnetUri = widget.url;
    }

    historyProvider.saveOrUpdateHistory(
      movieId: widget.movieId,
      movieName: widget.title,
      movieCover: '',
      episodeIndex: widget.episodeIndex,
      episodeName: '第${widget.episodeIndex + 1}集',
      progress: _position.inMilliseconds,
      duration: _duration.inMilliseconds,
      sourceId: widget.sourceId,
      magnetUri: magnetUri,
    );
  }

  /// 开始隐藏控制栏定时器
  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  /// 切换控制栏显示
  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    }
  }

  /// 播放/暂停
  void _togglePlayPause() async {
    if (_isPlaying) {
      await _playerService.pause();
    } else {
      await _playerService.resume();
    }
    _startHideTimer();
  }

  /// 跳转
  void _seekTo(Duration position) async {
    await _playerService.seek(position);
  }

  /// 快进
  void _seekForward() {
    final target = _position + const Duration(seconds: 10);
    _seekTo(target < _duration ? target : _duration);
  }

  /// 快退
  void _seekBackward() {
    final target = _position - const Duration(seconds: 10);
    _seekTo(target > Duration.zero ? target : Duration.zero);
  }

  /// 更新拖拽位置
  void _updateDragPosition(Offset position) {
    final box = context.findRenderObject() as RenderBox;
    final width = box.size.width;
    final normalizedPosition = (position.dx / width).clamp(0.0, 1.0);
    setState(() {
      _dragPosition = Duration(
        milliseconds: (_duration.inMilliseconds * normalizedPosition).round(),
      );
    });
  }

  /// 更新缩略图位置和时间点
  void _updateThumbnailPosition(Offset position) {
    final box = context.findRenderObject() as RenderBox;
    final width = box.size.width;
    final normalizedPosition = (position.dx / width).clamp(0.0, 1.0);
    setState(() {
      _thumbnailPosition = position;
      _thumbnailDuration = Duration(
        milliseconds: (_duration.inMilliseconds * normalizedPosition).round(),
      );
    });
  }

  /// 格式化时间
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 格式化缓存速度
  String _formatCacheSpeed(int speed) {
    return CacheSpeedFormatter.format(speed);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _saveProgress();
    _playerService.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Web端不支持 media_kit，显示提示信息
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.title),
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.white54,
                size: 48,
              ),
              SizedBox(height: 16),
              Text(
                'Web端暂不支持播放，请使用桌面端或移动端',
                style: TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_playerService.videoController == null) {
      // 正在解析或初始化播放器
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              const Text(
                '正在解析播放地址...',
                style: TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTap: _togglePlayPause,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! > 0) {
              _seekBackward();
            } else {
              _seekForward();
            }
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频播放器
            Center(
              child: Video(
                controller: _playerService.videoController!,
                controls: null,
              ),
            ),

            // 缓冲指示器
            if (_isBuffering)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // 错误提示
            if (_errorMessage.isNotEmpty && _retryCount >= maxRetryCount)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '播放失败',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _retryCount = 0;
                          _errorMessage = '';
                        });
                        _player?.open(Media(widget.url), play: true);
                      },
                      child: const Text(
                        '重试',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),

            // 控制栏
            if (_showControls) ...[
              // 顶部栏
              _buildTopBar(),

              // 中央控制
              _buildCenterControls(),

              // 底部栏
              _buildBottomBar(),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建顶部栏
  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          bottom: 8,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.sourceName.isNotEmpty)
                    Text(
                      widget.sourceName,
                      style: TextStyle(
                        color: Colors.white.withAlpha(153),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建中央控制
  Widget _buildCenterControls() {
    return Positioned.fill(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 快退
          IconButton(
            iconSize: 36,
            icon: const Icon(Icons.replay_10_outlined, color: Colors.white),
            onPressed: _seekBackward,
          ),
          const SizedBox(width: 32),

          // 播放/暂停
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              iconSize: 36,
              icon: Icon(
                _isPlaying ? Icons.pause_outlined : Icons.play_arrow_outlined,
                color: Colors.white,
              ),
              onPressed: _togglePlayPause,
            ),
          ),
          const SizedBox(width: 32),

          // 快进
          IconButton(
            iconSize: 36,
            icon: const Icon(Icons.forward_10_outlined, color: Colors.white),
            onPressed: _seekForward,
          ),
        ],
      ),
    );
  }

  /// 构建底部栏
  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 8,
          top: 8,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 缓存速度显示
            if (_isBuffering && _cacheSpeed > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.downloading_outlined,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatCacheSpeed(_cacheSpeed),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),

            // 进度条
            Row(
              children: [
                Text(
                  _formatDuration(_isDragging ? _dragPosition : _position),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: MouseRegion(
                      onEnter: (details) {
                        setState(() {
                          _isHovering = true;
                          _showThumbnail = true;
                          _updateThumbnailPosition(details.localPosition);
                        });
                      },
                      onExit: (details) {
                        setState(() {
                          _isHovering = false;
                          _showThumbnail = false;
                        });
                      },
                      onHover: (details) {
                        setState(() {
                          _updateThumbnailPosition(details.localPosition);
                        });
                      },
                      child: GestureDetector(
                        onTapDown: (details) {
                          setState(() {
                            _isDragging = true;
                            _updateDragPosition(details.localPosition);
                          });
                        },
                        onTapUp: (details) {
                          setState(() {
                            _isDragging = false;
                          });
                          _seekTo(_dragPosition);
                          _startHideTimer();
                        },
                        onTapCancel: () {
                          setState(() {
                            _isDragging = false;
                          });
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 背景轨道
                            Container(
                              height: _isHovering ? 8 : 4,
                              decoration: BoxDecoration(
                                color: _isHovering
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            // 缓冲进度
                            FractionallySizedBox(
                              widthFactor: _duration.inMilliseconds > 0
                                  ? (_bufferedPosition.inMilliseconds /
                                      _duration.inMilliseconds)
                                  : 0,
                              child: Container(
                                height: _isHovering ? 8 : 4,
                                decoration: BoxDecoration(
                                  color: _isHovering
                                      ? Colors.white.withValues(alpha: 0.4)
                                      : Colors.white.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            // 播放进度
                            FractionallySizedBox(
                              widthFactor: _duration.inMilliseconds > 0
                                  ? ((_isDragging
                                          ? _dragPosition.inMilliseconds
                                          : _position.inMilliseconds) /
                                      _duration.inMilliseconds)
                                  : 0,
                              child: Container(
                                height: _isHovering ? 8 : 4,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            // 滑块
                            Container(
                              width: _isHovering ? 18 : 14,
                              height: _isHovering ? 18 : 14,
                              margin: EdgeInsets.only(
                                left: (_duration.inMilliseconds > 0
                                    ? ((_isDragging
                                                ? _dragPosition.inMilliseconds
                                                : _position.inMilliseconds) /
                                            _duration.inMilliseconds) *
                                        100
                                    : 0),
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                                boxShadow: _isHovering
                                    ? [
                                        BoxShadow(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withAlpha(150),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : [],
                              ),
                            ),
                            // 缩略图
                            if (_showThumbnail && _duration.inMilliseconds > 0)
                              Positioned(
                                top: -90,
                                left: _thumbnailPosition.dx - 100,
                                child: Container(
                                  width: 200,
                                  height: 112,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    color: Colors.black,
                                  ),
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          color: Colors.black,
                                          child: Center(
                                            child: Text(
                                              _formatDuration(
                                                _thumbnailDuration,
                                              ),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        height: 20,
                                        color: Colors.black.withAlpha(150),
                                        child: Center(
                                          child: Text(
                                            _formatDuration(_thumbnailDuration),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // 倍速
                _buildActionButton(
                  icon: Icons.speed_outlined,
                  label: '${_playbackSpeed}x',
                  onTap: () => showSpeedSelector(
                    context: context,
                    currentSpeed: _playbackSpeed,
                    onSelected: (speed) {
                      setState(() {
                        _playbackSpeed = speed;
                      });
                      _player?.setRate(speed);
                    },
                  ),
                ),

                // 字幕
                _buildActionButton(
                  icon: Icons.subtitles_outlined,
                  label: '字幕',
                  onTap: () => showSubtitleSelector(
                    context: context,
                    currentIndex: -1,
                    subtitleTracks: const [],
                    onSelected: (index) {},
                  ),
                ),

                // 清晰度
                _buildActionButton(
                  icon: Icons.high_quality_outlined,
                  label: '清晰度',
                  onTap: () => showQualitySelector(
                    context: context,
                    currentQuality: '自动',
                    onSelected: (quality) {},
                  ),
                ),

                // 投屏
                _buildActionButton(
                  icon: Icons.cast_outlined,
                  label: '投屏',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('投屏功能开发中')),
                    );
                  },
                ),

                // 全屏
                _buildActionButton(
                  icon: _isFullScreen
                      ? Icons.fullscreen_exit_outlined
                      : Icons.fullscreen_outlined,
                  label: '',
                  onTap: () {
                    setState(() {
                      _isFullScreen = !_isFullScreen;
                    });
                    // Web端不支持 SystemChrome API
                    if (!kIsWeb) {
                      if (_isFullScreen) {
                        SystemChrome.setEnabledSystemUIMode(
                          SystemUiMode.immersiveSticky,
                        );
                        SystemChrome.setPreferredOrientations([
                          DeviceOrientation.landscapeLeft,
                          DeviceOrientation.landscapeRight,
                        ]);
                      } else {
                        SystemChrome.setEnabledSystemUIMode(
                          SystemUiMode.edgeToEdge,
                        );
                        SystemChrome.setPreferredOrientations([
                          DeviceOrientation.portraitUp,
                          DeviceOrientation.portraitDown,
                          DeviceOrientation.landscapeLeft,
                          DeviceOrientation.landscapeRight,
                        ]);
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建操作按钮
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
