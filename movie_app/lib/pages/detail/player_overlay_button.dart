import 'package:flutter/material.dart';

/// 播放器叠加层里的半透明圆形图标按钮。
///
/// 锁屏钮、顶栏图标、返回钮等本质都是「黑底半透明 + 圆角圆形 + 白色图标 +
/// Tooltip + 语义标签」这一套视觉，这里抽成公共组件避免各处重复手写 Container。
///
/// [active] 为真时加深背景并改用 [activeColor]，用于「已锁定 / 已选中」等状态。
class PlayerOverlayIconButton extends StatelessWidget {
  const PlayerOverlayIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconSize = 22,
    this.padding = 8,
    this.borderRadius = 20,
    this.backgroundColor = Colors.black38,
    this.color = Colors.white,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double iconSize;
  final double padding;
  final double borderRadius;
  final Color backgroundColor;
  final Color color;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final fg = active ? (activeColor ?? color) : color;
    final bg =
        active ? backgroundColor.withValues(alpha: 0.9) : backgroundColor;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Icon(icon, color: fg, size: iconSize),
          ),
        ),
      ),
    );
  }
}
