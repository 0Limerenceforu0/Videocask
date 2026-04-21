import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/routes.dart';
import '../l10n/app_localizations.dart';

/// 顶栏嵌入式搜索（对齐静态 `hifi-kp-topbar-search` / `hifi-win-search-box`），点击进搜索页。
class HiFiDesktopSearchBar extends StatelessWidget {
  const HiFiDesktopSearchBar({
    super.key,
    required this.hintText,
  });

  final String hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final width = MediaQuery.sizeOf(context).width;
    final maxBar = math.min(480.0, width * 0.36).clamp(140.0, 480.0);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxBar, minWidth: 140),
      child: Material(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => AppRoutes.toSearch(context),
          child: Semantics(
            label: l10n.toolbarSearch,
            button: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.search, size: 20, color: theme.hintColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hintText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.hintColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
