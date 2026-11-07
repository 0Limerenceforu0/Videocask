import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

/// 与 `docs/static-gallery/hifi-common.css` 等静态稿对齐的设计常量（逐步接入 Theme）。
abstract final class HiFiDesignTokens {
  /// `--accent` 近似值
  static const Color accent = Color(0xFF00AEEC);

  /// 宽屏内容区最大宽度（与静态稿约 1160px 对齐）
  static const double shellMaxWidth = 1160;

  /// Web 顶栏展示「品牌 + 频道」合并行时的最小逻辑宽度
  static const double desktopChannelNavMinWidth = 900;

  /// Web 或桌面 OS（Windows / Linux / macOS）且宽度足够时，使用高保真顶栏（品牌 + 频道 + 嵌入式搜索）。
  static bool useWideTopBarShell(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < desktopChannelNavMinWidth) {
      return false;
    }
    if (kIsWeb) {
      return true;
    }
    // 使用 [defaultTargetPlatform]（含测试里 `debugDefaultTargetPlatformOverride`），
    // 勿用 [Theme.of] 的 platform：在部分环境下与真实 OS 不一致，会导致宽屏壳误判。
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.macOS =>
        true,
      _ => false,
    };
  }
}
