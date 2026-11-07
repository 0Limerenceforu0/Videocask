import 'package:flutter/material.dart';

/// 播放器画面比例策略：把「旧的『全屏裁剪』选项 + 用户手动铺满开关」归一成 fit。
///
/// 纯函数（摘修复即红）：
/// - 默认 [BoxFit.contain] —— 原始比例、对称留边，**绝不变形 / 裁切**；
/// - 任一铺满信号（[cropFill] 旧的「全屏裁剪」、[fitCover] 用户手动「铺满」）为真
///   即 [BoxFit.cover] —— 裁切溢出部分、零黑边。
///
/// 旧实现非全屏无条件 `fitWidth`：当片源比播放槽「高」（4:3 / 方图 / 竖屏进宽槽）
/// 时会纵向溢出裁切，且片源比槽「宽」时也无法保证水平居中 —— 正是此前
/// 「右边单边黑带」的根。统一 contain 后，所有留边自动对称。
BoxFit resolvePlayerFit({required bool cropFill, required bool fitCover}) {
  return (cropFill || fitCover) ? BoxFit.cover : BoxFit.contain;
}
