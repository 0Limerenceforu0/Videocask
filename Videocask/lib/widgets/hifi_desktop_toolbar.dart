import 'package:flutter/foundation.dart' show defaultTargetPlatform;
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

    // 手机（Android/iOS）任意宽度都有底部导航的「关注 / 我的」入口，顶栏这两个
    // 图标纯属重复；且 6 个图标与标题并排在 360dp 逻辑宽下 RenderFlex 右溢出
    // （实测溢出 84px，release 下表现为最右图标被裁切）。桌面端无底部导航，
    // 「关注 / 我的」仅能经顶栏进入，保留全部图标。
    final isMobilePlatform = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };

    return [
      if (includeSearchIcon)
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => AppRoutes.toSearch(context),
          tooltip: l10n.toolbarSearch,
        ),
      if (!isMobilePlatform)
        IconButton(
          icon: const Icon(Icons.subscriptions_outlined),
          onPressed: () => AppRoutes.toFollow(context),
          tooltip: l10n.toolbarFollow,
        ),
      if (!isMobilePlatform)
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
