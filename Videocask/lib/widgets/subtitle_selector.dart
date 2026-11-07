import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final configured = isSubtitleAiBackendConfigured(runtime);
    final isOffline = runtime.backend != SubtitleAiBackendKind.onlineApi;

    final String subtitleLine;
    if (!configured) {
      if (isOffline) {
        subtitleLine = '未配置：到「设置 → AI 字幕生成」下载离线模型';
      } else {
        subtitleLine = '未配置 API：在「设置 → AI 字幕生成」填一个 Whisper 兼容端点';
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
              color:
                  configured ? theme.colorScheme.primary : theme.disabledColor,
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
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.72),
                      fontSize: 11,
                      height: 1.35,
                    ),
                    softWrap: true,
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

  Future<void> _runAiSubtitle(BuildContext context) async {
    await runSubtitleAiGeneration(
      context: context,
      source: currentVideoSource ?? '',
      title: videoTitle,
      onReady: (srtOrPath) => onAiSubtitleReady?.call(srtOrPath),
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
                    Tooltip(
                      message: subtitle,
                      child: Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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
///
/// 说明：必须 `isScrollControlled: true`，否则 Flutter 默认把底部弹窗高度
/// 限制为屏幕的 9/16，内容（尤其是外挂字幕轨道较多时）会被直接裁掉且不能滚动，
/// 表现为「文字展示不完全」。
Future<void> showSubtitleSelector({
  required BuildContext context,
  required int currentIndex,
  required List<String> subtitleTracks,
  required ValueChanged<int> onSelected,
  String? currentVideoSource,
  String? videoTitle,
  ValueChanged<String>? onAiSubtitleReady,
}) async {
  final height = MediaQuery.sizeOf(context).height;
  final maxHeight = height * 0.85;
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: maxHeight),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        // 键盘弹出时把内容顶上去，避免输入框被盖住。
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SubtitleSelector(
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
      ),
    ),
  );
}

/// 当前设置的 AI 字幕后端是否可用（未配置返回 false）。
///
/// 抽成顶层函数，供字幕选择器与详情页字幕面板共用。
bool isSubtitleAiBackendConfigured(SubtitleAiRuntimeConfig runtime) {
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

/// 跑一次 AI 字幕生成（含进度对话框），完成后通过 [onReady] 回传结果。
///
/// [onReady] 给的可能有两种形态：
/// - 桌面/移动端：已落盘的 **临时 SRT 文件路径**
/// - Web（无本地文件系统）：**SRT 文本**
///
/// 调用方负责把结果挂到播放器上。
Future<void> runSubtitleAiGeneration({
  required BuildContext context,
  required String source,
  String? title,
  required ValueChanged<String> onReady,
}) async {
  if (source.trim().isEmpty) return;

  final runtime = SubtitleAiService().runtimeFromSettings();
  if (!isSubtitleAiBackendConfigured(runtime)) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请先在「设置 → AI 字幕生成」中配置后端'),
      ),
    );
    return;
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AiSubtitleProgressDialog(
      source: source,
      title: title,
      runtime: runtime,
      onCompleted: onReady,
    ),
  );
}

/// AI 字幕生成进度对话框：实时显示阶段与百分比。
class AiSubtitleProgressDialog extends StatefulWidget {
  const AiSubtitleProgressDialog({
    super.key,
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
  State<AiSubtitleProgressDialog> createState() =>
      AiSubtitleProgressDialogState();
}

class AiSubtitleProgressDialogState extends State<AiSubtitleProgressDialog> {
  String _stage = '准备中…';
  double _progress = 0.0;
  String? _error;
  String? _srtOrPath;
  bool _isOffline = false;
  bool _copied = false;

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
      final segCount = result.srtContent.split('\n\n').length - 1;

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
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.72);
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isOffline ? Icons.memory : Icons.cloud_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isOffline ? '本地离线生成字幕' : '在线 AI 生成字幕',
              softWrap: true,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 36),
              const SizedBox(height: 8),
              // 错误信息往往很长（ffmpeg 缺失、模型缺失等），必须可滚动 +
              // 可选中复制，否则只能看到被掐断的半句话。
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _error!,
                    style: TextStyle(
                      color: theme.brightness == Brightness.dark
                          ? Colors.red.shade300
                          : Colors.red.shade800,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _error!));
                    if (!mounted) return;
                    setState(() => _copied = true);
                  },
                  icon: Icon(
                    _copied ? Icons.check : Icons.copy_all_outlined,
                    size: 16,
                  ),
                  label: Text(_copied ? '已复制' : '复制错误详情'),
                ),
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
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ] else ...[
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 36),
              const SizedBox(height: 8),
              Text(_stage, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Text(
                '字幕已挂到播放器。',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ],
        ),
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
