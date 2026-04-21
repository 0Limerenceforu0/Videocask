import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/movie.dart';

/// 可复用的UI组件
class DetailComponents {
  /// 构建播放器封面
  static Widget buildPlayerCover(Movie movie) {
    final imageUrl = movie.backdrop.isNotEmpty ? movie.backdrop : movie.cover;
    if (imageUrl.isEmpty) {
      return Container(color: const Color(0xFF000000));
    }
    return Hero(
      tag: 'movie_${movie.id}',
      child: SizedBox.expand(
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) =>
              Container(color: const Color(0xFF000000)),
        ),
      ),
    );
  }

  /// 构建播放器顶部栏
  static Widget buildPlayerTopBar(
    BuildContext context, {
    required Function() onBack,
    required Function() onFavorite,
    required Function() onShare,
  }) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 返回按钮
            GestureDetector(
              onTap: onBack,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(128),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const Spacer(),
            // 收藏按钮
            GestureDetector(
              onTap: onFavorite,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(128),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.favorite_border,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 分享按钮
            GestureDetector(
              onTap: onShare,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(128),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.share,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建播放器控制栏
  static Widget buildPlayerControls(
    BuildContext context, {
    required bool isPlaying,
    required bool isMuted,
    required double volume,
    required double playbackSpeed,
    required bool isFullScreen,
    required Duration position,
    required Duration duration,
    required double bufferedPosition,
    required Function() onPlayPause,
    required Function() onMute,
    required Function() onFullScreen,
    required Function(double) onSeek,
    required Function() onSpeed,
  }) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            children: [
              // 进度条
              SizedBox(
                width: double.infinity,
                child: Slider(
                  value: position.inMilliseconds.toDouble(),
                  max: duration.inMilliseconds.toDouble(),
                  onChanged: onSeek,
                  activeColor: Colors.blue,
                  inactiveColor: Colors.white30,
                ),
              ),
              // 时间和控制按钮
              Row(
                children: [
                  // 当前时间
                  Text(
                    _formatDuration(position),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '/ ${_formatDuration(duration)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const Spacer(),
                  // 播放/暂停按钮
                  GestureDetector(
                    onTap: onPlayPause,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 静音按钮
                  GestureDetector(
                    onTap: onMute,
                    child: Icon(
                      isMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 播放速度
                  GestureDetector(
                    onTap: onSpeed,
                    child: Text(
                      '${playbackSpeed}x',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 全屏按钮
                  GestureDetector(
                    onTap: onFullScreen,
                    child: Icon(
                      isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建磁力缓存进度条
  static Widget buildTorrentProgressBar(
    int torrentStep,
    String torrentMessage,
  ) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 4,
        child: LinearProgressIndicator(
          value: torrentStep / 4,
          backgroundColor: Colors.black38,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
        ),
      ),
    );
  }

  /// 构建字幕叠加层
  static Widget buildSubtitleOverlay(
    String subtitleText, {
    double fontSize = 16,
    Color color = Colors.white,
  }) {
    return Positioned(
      bottom: 80,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            subtitleText,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              shadows: const [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 4,
                  color: Colors.black87,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  /// 构建手势指示器
  static Widget buildGestureIndicator(IconData icon, double value) {
    return Positioned(
      top: 100,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text(
              '${(value * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建速度提示叠加层
  static Widget buildSpeedHintOverlay(double speed) {
    return Positioned(
      top: 100,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${speed}x',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建快捷键帮助面板
  static Widget buildShortcutHelpPanel(
    bool show, {
    required VoidCallback onClose,
  }) {
    if (!show) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        color: Colors.black87,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '快捷键',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Esc：关闭本面板 / 退出全屏\n'
                  '空格：播放 / 暂停\n'
                  'F：全屏\n'
                  'M：静音\n'
                  'L：锁屏\n'
                  'C：内嵌字幕开关\n'
                  '[ / ]：减速 / 加速\n'
                  '0–9：跳到 0%–90% 进度\n'
                  '↑ ↓：音量 ±10（0–200）\n'
                  '← →：快退 / 快进 5 秒\n'
                  'Shift + ← / →：快退 / 快进 10 秒\n'
                  'N / P：下一集 / 上一集\n'
                  'H / ?：打开 / 关闭本说明\n'
                  '\n'
                  '双击画面：播放 / 暂停\n'
                  '底部工具栏：对比度、DLNA 投屏、全屏；窄屏时在工具栏选线路。'
                  '点击音量图标在上方展开纵向滑块（B 站风格）。'
                  '鼠标在画面上移动会显示控制栏与进度条，约 3 秒静止后自动隐藏。\n'
                  '\n'
                  '手势：左半屏竖滑调亮度，右半屏竖滑调音量；长按画面临时 2 倍速。',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onClose,
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 格式化时长
  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = (duration.inMinutes % 60);
    final seconds = (duration.inSeconds % 60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }
}
