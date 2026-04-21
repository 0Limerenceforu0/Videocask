import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/routes.dart';
import '../l10n/app_localizations.dart';
import '../providers/theme_provider.dart';

/// Web / 桌面顶栏右侧图标组（与静态 `hifi-kp-topbar-actions` 一致），供首页与频道页等复用。
/// 宽屏顶栏中间嵌入式搜索见 [HiFiDesktopSearchBar]；此时可将 [includeSearchIcon] 设为 `false` 以免重复。
abstract final class HiFiDesktopToolbar {
  HiFiDesktopToolbar._();

  /// 返回一组 [IconButton]，可展开到父级 [Row] 的 `children`。
  static List<Widget> trailingActions(
    BuildContext context, {
    bool denseMode = false,
    VoidCallback? onToggleDenseMode,
    bool includeSearchIcon = true,
  }) {
    final l10n = AppLocalizations.of(context)!;

    return [
      if (includeSearchIcon)
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => AppRoutes.toSearch(context),
          tooltip: l10n.toolbarSearch,
        ),
      IconButton(
        icon: const Icon(Icons.subscriptions_outlined),
        onPressed: () => AppRoutes.toFollow(context),
        tooltip: l10n.toolbarFollow,
      ),
      IconButton(
        icon: const Icon(Icons.person_outline),
        onPressed: () => AppRoutes.toProfile(context),
        tooltip: l10n.toolbarProfile,
      ),
      IconButton(
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => AppRoutes.toSettings(context),
        tooltip: l10n.toolbarSettings,
      ),
      if (onToggleDenseMode != null)
        IconButton(
          icon: Icon(
            denseMode
                ? Icons.view_comfy_alt_outlined
                : Icons.grid_view_outlined,
          ),
          onPressed: onToggleDenseMode,
          tooltip:
              denseMode ? l10n.toolbarViewComfort : l10n.toolbarViewCompact,
        ),
      IconButton(
        icon: const Icon(Icons.dark_mode_outlined),
        onPressed: () async {
          final themeProvider = context.read<ThemeProvider>();
          await themeProvider.nextTheme();
          if (!context.mounted) {
            return;
          }
          final name = themeProvider.themeName;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.toolbarThemeSwitched(name)),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        tooltip: l10n.toolbarTheme,
      ),
    ];
  }
}
