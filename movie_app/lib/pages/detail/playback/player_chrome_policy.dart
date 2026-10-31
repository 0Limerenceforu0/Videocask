// 播放器外框（返回按钮 / 控制栏）的显隐策略。
//
// 抽成纯函数是为了能被单测直接覆盖：这是「磁力加载中没有任何返回入口」
// 这类回归的唯一判定点。

/// 控制栏隐藏时，播放器区域是否必须常驻一个返回按钮。
///
/// 背景（2026-10-28 真机反馈）：磁力资源解析要几十秒，控制栏 3 秒后自动隐藏，
/// 而此时 [hasVideoController] 还是 false（VideoController 要等元数据拿到才建），
/// 于是「隐藏态返回按钮」不显示 → 整个播放器区域一个出口都没有，用户只能靠
/// 系统返回键。
///
/// 因此除了真正有控制器的情况，磁力准备中 / 播放失败（错误卡片独占画面）
/// 也必须保留返回按钮。
bool shouldShowPersistentPlayerBackButton({
  required bool hasVideoController,
  required bool controlsVisible,
  required bool fullScreen,
  required bool screenLocked,
  required bool magnetBusyOrFailed,
}) {
  // 控制栏自己带着返回按钮；全屏靠 Esc / 单击唤出；锁屏有专门的解锁入口。
  if (screenLocked || fullScreen || controlsVisible) return false;
  return hasVideoController || magnetBusyOrFailed;
}
