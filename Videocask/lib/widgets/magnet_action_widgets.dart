import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../pages/detail/playback/subtitle_availability_policy.dart';
import '../services/magnet_download_service.dart';

/// 磁力资源卡片上的「是否有中文字幕」徽标。
///
/// 详情页与搜索页共用同一个纯函数判定，避免出现两套口径。
/// 标题没写字幕标记时显示「未标注字幕」，不冒充「无字幕」。
class MagnetSubtitleBadge extends StatelessWidget {
  const MagnetSubtitleBadge({
    super.key,
    required this.title,
    this.compact = false,
    this.muted,
    this.accent,
  });

  final String title;
  final bool compact;
  final Color? muted;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = detectMagnetSubtitle(title);
    final hasSubtitle = hasChineseSubtitleMark(value);
    final fg = hasSubtitle
        ? (accent ?? theme.colorScheme.primary)
        : (muted ?? theme.hintColor);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSubtitle ? Icons.subtitles_outlined : Icons.subtitles_off_outlined,
            size: compact ? 12 : 14,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            subtitleAvailabilityLabel(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 「点一下就真的开始下载」的按钮。
///
/// 不再只复制磁力链接：调用 [MagnetDownloadService.start] 让 App 内的
/// libtorrent 会话直接写盘，并实时显示进度；Web 端给出明确的不支持提示。
class MagnetDownloadButton extends StatelessWidget {
  const MagnetDownloadButton({
    super.key,
    required this.magnetUri,
    required this.name,
    this.foreground,
    this.borderColor,
    this.compact = false,
  });

  final String magnetUri;
  final String name;
  final Color? foreground;
  final Color? borderColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final service = MagnetDownloadService();
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final task = service.taskFor(magnetUri);
        final active = task != null && !task.finished;
        final label = task == null
            ? l10n.detailMagnetDownload
            : (task.finished
                ? '已下载'
                : '${(task.progress * 100).toStringAsFixed(0)}%');
        return OutlinedButton.icon(
          onPressed: () => _start(context, service),
          icon: Icon(
            task == null
                ? Icons.download_outlined
                : (task.finished
                    ? Icons.download_done_rounded
                    : Icons.downloading_rounded),
            size: compact ? 16 : 18,
          ),
          label: Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground ?? theme.colorScheme.onSurface,
            side: BorderSide(
              color: (borderColor ?? theme.colorScheme.outline)
                  .withValues(alpha: active ? 0.9 : 0.6),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 6 : 8,
            ),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 13),
          ),
        );
      },
    );
  }

  Future<void> _start(
    BuildContext context,
    MagnetDownloadService service,
  ) async {
    final result = await service.start(magnetUri: magnetUri, name: name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
