import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 自定义AppBar组件
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// 标题
  final String title;

  /// 是否显示返回按钮
  final bool showBackButton;

  /// 返回按钮回调
  final VoidCallback? onBack;

  /// 右侧操作按钮列表
  final List<Widget>? actions;

  /// 背景色（透明则使用主题色）
  final Color? backgroundColor;

  /// 标题颜色
  final Color? titleColor;

  /// 是否居中标题
  final bool centerTitle;

  /// 底部组件
  final PreferredSizeWidget? bottom;

  /// 高度
  final double height;

  /// 是否自动隐藏（滚动时）
  final bool autoHide;

  const CustomAppBar({
    super.key,
    required this.title,
    this.showBackButton = true,
    this.onBack,
    this.actions,
    this.backgroundColor,
    this.titleColor,
    this.centerTitle = true,
    this.bottom,
    this.height = kToolbarHeight,
    this.autoHide = false,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        height + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveBgColor =
        backgroundColor ?? theme.appBarTheme.backgroundColor;
    final effectiveTitleColor = titleColor ??
        theme.appBarTheme.titleTextStyle?.color ??
        theme.colorScheme.onSurface;

    return AppBar(
      title: Text(
        title,
        style: TextStyle(
          color: effectiveTitleColor,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      centerTitle: centerTitle,
      backgroundColor: effectiveBgColor,
      elevation: 0,
      leading: showBackButton
          ? IconButton(
              icon: Icon(
                Icons.arrow_back_ios,
                color: effectiveTitleColor,
                size: 20,
              ),
              onPressed: onBack ?? () => context.pop(),
            )
          : null,
      actions: actions,
      bottom: bottom,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          color: effectiveBgColor,
        ),
      ),
    );
  }
}

/// 带渐变效果的AppBar
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final VoidCallback? onBack;
  final List<Color>? gradientColors;

  const GradientAppBar({
    super.key,
    required this.title,
    this.actions,
    this.onBack,
    this.gradientColors,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = gradientColors ??
        [theme.colorScheme.primary, theme.colorScheme.primaryContainer];

    return AppBar(
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
        onPressed: onBack ?? () => context.pop(),
      ),
      actions: actions,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
    );
  }
}
