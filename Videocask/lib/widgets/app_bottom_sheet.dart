import 'package:flutter/material.dart';

/// 全 App 底部弹窗的统一入口。
///
/// 🔴 历史事故（2026-11-11）：之前每处 `showModalBottomSheet` 各自手写，
/// 线路弹窗和字幕选择器分别修过「内容被屏幕底边裁掉、最后一项点不到」，
/// 但字幕面板没有复用那套修法，同一个问题第二次出现。实测 1080×2400 竖屏
/// 下字幕面板的「字幕延时」整行根本没渲染出来，UI 层级里也找不到节点。
///
/// 所以这里一次性收口四件事，任何固定内容的底部弹窗都必须走这里：
/// ① `isScrollControlled: true` 允许撑到接近全屏；
/// ② `constraints` 限制最大高度，避免键盘/横屏时越界；
/// ③ `SingleChildScrollView` 让超长内容能滚到底；
/// ④ `SafeArea` + `viewInsets.bottom` 处理挖孔、导航栏与输入法。
///
/// 新增弹窗一律用 [showAppBottomSheet]。只有自带滚动语义的特殊弹窗
/// （`DraggableScrollableSheet`、超长 `ListView`）才允许直接调
/// `showModalBottomSheet`，但也必须带 `isScrollControlled: true` 和
/// `constraints` —— 由 `test/ui/bottom_sheet_policy_test.dart` 静态兜底。
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  /// 最大高度占屏幕高的比例。横屏/键盘弹出时适当调小。
  double maxHeightFactor = 0.85,
  bool showDragHandle = true,
  Color? backgroundColor,
  ShapeBorder? shape,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: showDragHandle,
    backgroundColor: backgroundColor ??
        theme.bottomSheetTheme.modalBackgroundColor ??
        theme.colorScheme.surface,
    shape: shape,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: builder(ctx),
      ),
    ),
  );
}
