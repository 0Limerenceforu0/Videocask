import 'package:flutter/material.dart';

import 'hifi_design_tokens.dart';

/// 高保真静态稿相关、与 [ThemeData] 并存的可选 Token（逐步替代散落魔法数）。
@immutable
class HiFiUiTokens extends ThemeExtension<HiFiUiTokens> {
  const HiFiUiTokens({
    required this.accent,
    required this.shellMaxWidth,
    required this.desktopNavMinWidth,
    required this.cardRadiusLg,
    required this.cardRadiusMd,
  });

  /// 与静态稿 `--accent` 对齐
  final Color accent;

  /// 宽屏内容最大宽
  final double shellMaxWidth;

  /// 顶栏「品牌 + 频道 + 搜索」壳断点
  final double desktopNavMinWidth;

  /// 大卡片圆角（对照 `hifi-common.css` `--radius-lg`）
  final double cardRadiusLg;

  /// 中圆角（对照 `--radius-md`）
  final double cardRadiusMd;

  static const HiFiUiTokens standard = HiFiUiTokens(
    accent: HiFiDesignTokens.accent,
    shellMaxWidth: HiFiDesignTokens.shellMaxWidth,
    desktopNavMinWidth: HiFiDesignTokens.desktopChannelNavMinWidth,
    cardRadiusLg: 16,
    cardRadiusMd: 12,
  );

  @override
  HiFiUiTokens copyWith({
    Color? accent,
    double? shellMaxWidth,
    double? desktopNavMinWidth,
    double? cardRadiusLg,
    double? cardRadiusMd,
  }) {
    return HiFiUiTokens(
      accent: accent ?? this.accent,
      shellMaxWidth: shellMaxWidth ?? this.shellMaxWidth,
      desktopNavMinWidth: desktopNavMinWidth ?? this.desktopNavMinWidth,
      cardRadiusLg: cardRadiusLg ?? this.cardRadiusLg,
      cardRadiusMd: cardRadiusMd ?? this.cardRadiusMd,
    );
  }

  @override
  HiFiUiTokens lerp(ThemeExtension<HiFiUiTokens>? other, double t) {
    if (other is! HiFiUiTokens) {
      return this;
    }
    return HiFiUiTokens(
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      shellMaxWidth: _lerpD(shellMaxWidth, other.shellMaxWidth, t),
      desktopNavMinWidth:
          _lerpD(desktopNavMinWidth, other.desktopNavMinWidth, t),
      cardRadiusLg: _lerpD(cardRadiusLg, other.cardRadiusLg, t),
      cardRadiusMd: _lerpD(cardRadiusMd, other.cardRadiusMd, t),
    );
  }

  static double _lerpD(double a, double b, double t) => a + (b - a) * t;
}
