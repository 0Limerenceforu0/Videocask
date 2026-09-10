import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/subtitle_ai_backend.dart';
import '../services/subtitle_ai_model_manager.dart';
import '../services/subtitle_ai_service.dart';

/// 字幕选择器组件
class SubtitleSelector extends StatelessWidget {
  /// 当前选中的字幕索引（-1表示关闭字幕）
  final int currentIndex;

  /// 字幕轨道列表
  final List<String> subtitleTracks;

  /// 选择回调
  final ValueChanged<int> onSelected;

  /// 当前播放的视频源（URL 或本地路径）。给 AI 字幕用。
  final String? currentVideoSource;

  /// 视频标题（用于 AI 字幕 prompt 提示）
  final String? videoTitle;

  /// AI 字幕生成成功回调（拿到 SRT 文本，由调用方挂回播放器）
  final ValueChanged<String>? onAiSubtitleReady;

  const SubtitleSelector({
    super.key,
    required this.currentIndex,
    required this.subtitleTracks,
    required this.onSelected,
    this.currentVideoSource,
    this.videoTitle,
    this.onAiSubtitleReady,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '字幕选择',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),

          // 关闭字幕选项
          _buildOption(
            context,
            title: '关闭字幕',
            isSelected: currentIndex == -1,
            onTap: () => onSelected(-1),
          ),

          // 字幕列表
          ...List.generate(subtitleTracks.length, (index) {
            final track = subtitleTracks[index];
            final name = track.split('/').last;
            return _buildOption(
              context,
              title: name,
              subtitle: track,
              isSelected: currentIndex == index,
              onTap: () => onSelected(index),
            );
          }),

          // AI 字幕入口
          if (currentVideoSource != null && currentVideoSource!.isNotEmpty)
            _buildAiSubtitleOption(context),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildAiSubtitleOption(BuildContext context) {
    final theme = Theme.of(context);
    final runtime = SubtitleAiService().runtimeFromSettings();
    final configured = _isBackendConfigured(runtime);
    final isOffline = runtime.backend != SubtitleAiBackendKind.onlineApi;

    final String subtitleLine;
    if (!configured) {
      if (isOffline) {
        subtitleLine = '未配置：到「设置 → AI 字幕生成」下载离线模型';
      } else {
        subtitleLine =
            '未配置 API：在「设置 → AI 字幕生成」填一个 Whisper 兼容端点';
      }
    } else if (isOffline) {
      final model = kSubtitleAiModelRegistry.findById(runtime.selectedModelId);
      final max = runtime.maxAudioDuration?.inMinutes ?? 10;
      subtitleLine = model == null
          ? '离线模型未选择（设置 → AI 字幕生成）'
          : '离线识别前 $max 分钟音频 · ${model.displayName}';
    } else {
      final max = runtime.maxAudioDuration?.inMinutes ?? 10;
      subtitleLine = '在线 API · 识别前 $max 分钟音频';
    }

    return InkWell(
      onTap: () async {
        Navigator.of(context).pop();
        await _runAiSubtitle(context);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isOffline ? Icons.memory : Icons.cloud_outlined,
              color: configured
                  ? theme.colorScheme.primary
                  : theme.disabledColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOffline ? '本地离线生成中文字幕' : 'AI 生成中文字幕（在线）',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: configured
                          ? theme.textTheme.bodyMedium?.color
                          : theme.disabledColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleLine,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      fontSize: 11,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.hintColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  bool _isBackendConfigured(SubtitleAiRuntimeConfig runtime) {
    switch (runtime.backend) {
      case SubtitleAiBackendKind.onlineApi:
        return runtime.isOnlineApiConfigured;
      case SubtitleAiBackendKind.sherpaNative:
        if (kIsWeb) return false;
        return runtime.isOfflineReady;
      case SubtitleAiBackendKind.transformersWeb:
        if (!kIsWeb) return false;
        return true;
    }
  }

  Future<void> _runAiSubtitle(BuildContext context) async {
    final source = currentVideoSource!;
    if (source.isEmpty) return;

    final runtime = SubtitleAiService().runtimeFromSettings();
    if (!_isBackendConfigured(runtime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先在「设置 → AI 字幕生成」中配置后端'),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AiSubtitleProgressDialog(
        source: source,
        title: videoTitle,
        runtime: runtime,
        onCompleted: (srtOrPath) {
          onAiSubtitleReady?.call(srtOrPath);
        },
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required String title,
    String? subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? theme.colorScheme.primary : theme.hintColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                color: theme.colorScheme.primary,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

/// 显示字幕选择器底部弹窗
Future<void> showSubtitleSelector({
  required BuildContext context,
  required int currentIndex,
  required List<String> subtitleTracks,
  required ValueChanged<int> onSelected,
  String? currentVideoSource,
  String? videoTitle,
  ValueChanged<String>? onAiSubtitleReady,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => SubtitleSelector(
      currentIndex: currentIndex,
      subtitleTracks: subtitleTracks,
      onSelected: (index) {
        onSelected(index);
        Navigator.of(context).pop();
      },
      currentVideoSource: currentVideoSource,
      videoTitle: videoTitle,
      onAiSubtitleReady: onAiSubtitleReady,
    ),
  );
}

/// AI 字幕生成进度对话框：实时显示阶段与百分比。
class _AiSubtitleProgressDialog extends StatefulWidget {
  const _AiSubtitleProgressDialog({
    required this.source,
    required this.title,
    required this.runtime,
    required this.onCompleted,
  });

  final String source;
  final String? title;
  final SubtitleAiRuntimeConfig runtime;
  final ValueChanged<String> onCompleted;

  @override
  State<_AiSubtitleProgressDialog> createState() =>
      _AiSubtitleProgressDialogState();
}

class _AiSubtitleProgressDialogState extends State<_AiSubtitleProgressDialog> {
  String _stage = '准备中…';
  double _progress = 0.0;
  String? _error;
  String? _srtOrPath;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _isOffline = widget.runtime.backend != SubtitleAiBackendKind.onlineApi;
    _start();
  }

  Future<void> _start() async {
    try {
      final result = await SubtitleAiService().generateWithBackend(
        source: widget.source,
        runtime: widget.runtime,
        hintTitle: widget.title,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _stage = p.stage;
            _progress = p.value;
          });
        },
      );

      // 落盘到临时目录：srt 文本 + 用播放器加载
      String? localPath;
      try {
        if (!kIsWeb) {
          final dir = await getTemporaryDirectory();
          final f = File(
            '${dir.path}${Platform.pathSeparator}ai_${DateTime.now().millisecondsSinceEpoch}.srt',
          );
          await f.writeAsString(result.srtContent, flush: true);
          localPath = f.path;
        }
      } catch (_) {}
      final segCount = result.srtContent.split("\n\n").length - 1;

      if (!mounted) return;
      setState(() {
        _srtOrPath = localPath ?? result.srtContent;
        _stage = '生成完成 · 共 $segCount 条字幕';
        _progress = 1.0;
      });
      // 落盘路径或 SRT 文本都通过 onCompleted 回传
      widget.onCompleted(_srtOrPath!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isOffline ? Icons.memory : Icons.cloud_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(_isOffline ? '本地离线生成字幕' : '在线 AI 生成字幕'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Icon(Icons.error_outline, color: Colors.red.shade400, size: 36),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
          ] else if (_srtOrPath == null) ...[
            Text(_stage, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: _progress, minHeight: 6),
            ),
            const SizedBox(height: 4),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ] else ...[
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 36),
            const SizedBox(height: 8),
            Text(_stage, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            const Text(
              '字幕已挂到播放器。',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (_srtOrPath != null) {
              widget.onCompleted(_srtOrPath!);
            }
            Navigator.of(context).pop();
          },
          child: Text(_srtOrPath == null ? '取消' : '关闭'),
        ),
      ],
    );
  }
}