import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../utils/web_http_stub.dart'
    if (dart.library.html) '../../utils/web_http.dart' as web_http;

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
          imageUrl: web_http.webProxiedImageUrl(imageUrl),
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

  /// 构建磁力准备进度条（底部单条，含一步文案）
  ///
  /// 升级版：实时显示下载速度、做种/下载节点数、ETA、缓冲百分比、当前阶段。
  /// 当 [bufferPct] > 0 时切换为「缓冲」阶段；当 [metaWait] > 30s 时提示「解析较慢」。
  static Widget buildTorrentProgressBar(
    int torrentStep,
    String torrentMessage, {
    int downloadSpeed = 0,
    int peers = 0,
    int seeds = 0,
    int bufferPct = 0,
    String etaFormatted = '--',
    String metaWait = '',
    bool webFallback = false,
  }) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 第一行：阶段 + 速度 + 节点
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                    value: bufferPct > 0 ? bufferPct / 100 : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    torrentMessage.trim().isEmpty
                        ? (webFallback ? '云端代理加载中…' : '准备中…')
                        : torrentMessage.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (downloadSpeed > 0) ...[
                  const SizedBox(width: 8),
                  _TorrentStatChip(
                    icon: Icons.arrow_downward_rounded,
                    text: '${_formatBytes(downloadSpeed)}/s',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // 第二行：节点 / 缓冲 / ETA
            Row(
              children: [
                if (peers > 0)
                  _TorrentStatChip(
                    icon: Icons.people_alt_outlined,
                    text: '节点 $peers',
                  ),
                if (peers > 0) const SizedBox(width: 6),
                if (seeds > 0) ...[
                  _TorrentStatChip(
                    icon: Icons.upload_rounded,
                    text: '做种 $seeds',
                    color: const Color(0xFF80E27E),
                  ),
                  const SizedBox(width: 6),
                ],
                if (bufferPct > 0) ...[
                  _TorrentStatChip(
                    icon: Icons.layers_outlined,
                    text: '缓冲 $bufferPct%',
                  ),
                  const SizedBox(width: 6),
                ],
                if (etaFormatted.isNotEmpty && etaFormatted != '--') ...[
                  _TorrentStatChip(
                    icon: Icons.timer_outlined,
                    text: 'ETA $etaFormatted',
                  ),
                ],
                const Spacer(),
                if (metaWait.isNotEmpty && metaWait.isNotEmpty)
                  _TorrentStatChip(
                    icon: Icons.hourglass_empty_rounded,
                    text: '解析 $metaWait',
                    color: metaWait.contains('m')
                        ? const Color(0xFFFFB74D)
                        : Colors.white70,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // 进度条：解析 25% / 缓冲 50% / 播放 100%（按 step）
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: bufferPct > 0
                    ? (bufferPct / 100).clamp(0.02, 1.0)
                    : (torrentStep <= 0
                        ? 0.05
                        : (torrentStep / 4).clamp(0.05, 1.0)),
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 构建字幕叠加层
  static Widget buildSubtitleOverlay(
    String subtitleText, {
    double fontSize = 16,
    Color color = Colors.white,
    double bottom = 80,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    return Positioned(
      bottom: bottom + padding.bottom,
      left: padding.left + 12,
      right: padding.right + 12,
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
    bool showLockShortcut = true,
  }) {
    if (!show) return const SizedBox.shrink();

    final lockLine = showLockShortcut ? 'L：锁屏\n' : '';

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
                Text(
                  'Esc：关闭本面板 / 退出全屏\n'
                  '空格：播放 / 暂停\n'
                  'F：全屏\n'
                  'M：静音\n'
                  '$lockLine'
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
                  '底部工具栏：DLNA 投屏、全屏；窄屏时在工具栏选线路。'
                  '点击音量图标在上方展开纵向滑块（B 站风格）。'
                  '鼠标在画面上移动会显示控制栏与进度条，约 3 秒静止后自动隐藏。\n'
                  '\n'
                  '手势：左半屏竖滑调亮度，右半屏竖滑调音量；长按画面临时 2 倍速。',
                  style: const TextStyle(
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

/// 磁力 / 缓冲条上的小信息芯片（下载速度 / 节点数 / 缓冲 / ETA / 解析耗时）。
class _TorrentStatChip extends StatelessWidget {
  const _TorrentStatChip({
    required this.icon,
    required this.text,
    this.color = Colors.white70,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
