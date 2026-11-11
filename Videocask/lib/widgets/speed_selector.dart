import 'package:flutter/material.dart';
import 'package:movie_app/config/constants.dart';
import 'package:movie_app/l10n/app_localizations.dart';

import 'app_bottom_sheet.dart';

/// 倍速选择展示方式。
enum SpeedSelectorPresentation {
  /// 独立播放页等：底部 sheet。
  bottomSheet,

  /// 详情页嵌入播放器：倍速按钮上方横向小块。
  detailEmbedded,

  /// 详情页全屏：控制栏上方右侧竖向列表。
  detailFullscreen,
}

/// 倍速选择器（底部 sheet 样式，供设置页等使用）。
class SpeedSelector extends StatelessWidget {
  const SpeedSelector({
    super.key,
    required this.currentSpeed,
    required this.onSelected,
  });

  final double currentSpeed;
  final ValueChanged<double> onSelected;

  static bool speedsMatch(double a, double b) => (a - b).abs() < 0.02;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.designV3TooltipSpeed,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppConstants.speedOptions.map((speed) {
                final isSelected = speedsMatch(speed, currentSpeed);
                return _SpeedChip(
                  label: speed == 1.0 ? l10n.speedSelectorNormal : '${speed}x',
                  isSelected: isSelected,
                  onTap: () => onSelected(speed),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 详情页播放器内紧凑倍速面板（深色半透明）。
class SpeedSelectorCompact extends StatelessWidget {
  const SpeedSelectorCompact({
    super.key,
    required this.currentSpeed,
    required this.onSelected,
    required this.vertical,
  });

  final double currentSpeed;
  final ValueChanged<double> onSelected;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    Widget option(double speed) {
      final selected = SpeedSelector.speedsMatch(speed, currentSpeed);
      final label = speed == 1.0 ? l10n.speedSelectorNormal : '${speed}x';
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(speed),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: BoxConstraints(
              minWidth: vertical ? 52 : 0,
              minHeight: vertical ? 30 : 28,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: vertical ? 10 : 8,
              vertical: vertical ? 4 : 2,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.22)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: vertical ? 12 : 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    final children =
        AppConstants.speedOptions.map(option).toList(growable: false);

    // 倍速项可能较多（含 6/8/10x），竖向/横向紧凑面板都限制最大高度并允许滚动，
    // 避免内容超出屏幕被裁切。
    // 注意：这里必须按「实际项数」估算高度。原先横向写死 168dp，而 6 项约需
    // 188dp，导致最后一项（2.0x）被 Clip 裁掉一半；横向又没有可见滚动条，
    // 用户会以为选项缺失。
    const perItemHeight = 30.0;
    final contentHeight = children.length * perItemHeight + 8;
    final maxHeight =
        vertical ? 360.0 : contentHeight.clamp(120.0, 240.0).toDouble();

    return Material(
      color: Colors.black.withValues(alpha: 0.9),
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Scrollbar(
          thumbVisibility: vertical,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: vertical
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: children,
                    )
                  : SizedBox(
                      width: 228,
                      child: Wrap(
                        spacing: 2,
                        runSpacing: 2,
                        alignment: WrapAlignment.center,
                        children: children,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 显示倍速选择器。
Future<void> showSpeedSelector({
  required BuildContext context,
  required double currentSpeed,
  required ValueChanged<double> onSelected,
  SpeedSelectorPresentation presentation =
      SpeedSelectorPresentation.bottomSheet,
  GlobalKey? anchorKey,
}) async {
  switch (presentation) {
    case SpeedSelectorPresentation.bottomSheet:
      await _showSpeedBottomSheet(
        context: context,
        currentSpeed: currentSpeed,
        onSelected: onSelected,
      );
    case SpeedSelectorPresentation.detailEmbedded:
    case SpeedSelectorPresentation.detailFullscreen:
      await _showSpeedPopover(
        context: context,
        currentSpeed: currentSpeed,
        onSelected: onSelected,
        presentation: presentation,
        anchorKey: anchorKey,
      );
  }
}

Future<void> _showSpeedBottomSheet({
  required BuildContext context,
  required double currentSpeed,
  required ValueChanged<double> onSelected,
}) async {
  await showAppBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // SpeedSelector 自绘圆角卡片，不叠加系统拖拽条。
    showDragHandle: false,
    builder: (context) => SpeedSelector(
      currentSpeed: currentSpeed,
      onSelected: (speed) {
        onSelected(speed);
        Navigator.of(context).pop();
      },
    ),
  );
}

Future<void> _showSpeedPopover({
  required BuildContext context,
  required double currentSpeed,
  required ValueChanged<double> onSelected,
  required SpeedSelectorPresentation presentation,
  GlobalKey? anchorKey,
}) async {
  final vertical = presentation == SpeedSelectorPresentation.detailFullscreen;
  // 面板高度必须与 SpeedSelectorCompact 内部一致（每项 ~30dp + 8dp 内边距），
  // 否则定位会把菜单放得太靠下、底部被屏幕裁掉。
  final panelH = vertical
      ? 360.0
      : (AppConstants.speedOptions.length * 30.0 + 8);
  final anchorBox = anchorKey?.currentContext?.findRenderObject() as RenderBox?;
  final media = MediaQuery.of(context);
  final screen = media.size;
  final padding = media.padding;

    var panelOffset = Offset(
      screen.width - (vertical ? 68 : 236),
      screen.height - padding.bottom - panelH,
    );

    if (anchorBox != null && anchorBox.hasSize) {
      final anchor = anchorBox.localToGlobal(Offset.zero) & anchorBox.size;
      if (vertical) {
        const panelW = 60.0;
        var top = anchor.top - panelH - 8;
        if (top < padding.top + 8) {
          top = anchor.bottom + 8;
        }
        panelOffset = Offset(
          (anchor.right - panelW).clamp(8.0, screen.width - panelW - 8),
          top.clamp(padding.top + 8, screen.height - panelH - padding.bottom - 8),
        );
      } else {
        const panelW = 236.0;
        var top = anchor.top - panelH - 6;
        if (top < padding.top + 8) {
          top = anchor.bottom + 6;
        }
        panelOffset = Offset(
          (anchor.right - panelW).clamp(8.0, screen.width - panelW - 8),
          top.clamp(padding.top + 8, screen.height - panelH - padding.bottom - 8),
        );
      }
    }

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, _, __) {
      return Stack(
        children: [
          Positioned(
            left: panelOffset.dx,
            top: panelOffset.dy,
            child: SpeedSelectorCompact(
              currentSpeed: currentSpeed,
              vertical: vertical,
              onSelected: (speed) {
                onSelected(speed);
                Navigator.of(dialogContext).pop();
              },
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, _, child) {
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut),
          ),
          alignment: vertical ? Alignment.bottomRight : Alignment.bottomCenter,
          child: child,
        ),
      );
    },
  );
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(
                  color: theme.dividerColor,
                ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? theme.colorScheme.onPrimary
                : theme.textTheme.bodyMedium?.color,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
