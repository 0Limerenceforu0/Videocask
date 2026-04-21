import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/hifi_design_tokens.dart';

/// 宽屏顶栏壳下内容区与静态稿 `max-width: 1160px` 对齐。
class HiFiWideConstrainedBody extends StatelessWidget {
  const HiFiWideConstrainedBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!HiFiDesignTokens.useWideTopBarShell(context)) {
      return child;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        var outer = constraints.maxWidth;
        if (!outer.isFinite || outer <= 0) {
          outer = MediaQuery.sizeOf(context).width;
        }
        if (!outer.isFinite || outer <= 0) {
          return const SizedBox.shrink();
        }
        final inner = math.min(outer, HiFiDesignTokens.shellMaxWidth);
        if (inner < 1) {
          return const SizedBox.shrink();
        }
        return SizedBox(
          width: outer,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: inner, child: child),
          ),
        );
      },
    );
  }
}
