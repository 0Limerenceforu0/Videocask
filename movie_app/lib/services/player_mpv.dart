/// mpv（NativePlayer）专有能力的平台适配入口。
///
/// Web 上 media_kit 的 `NativePlayer` 是空壳类型，没有
/// `getProperty` / `setProperty` / `command`，直接调用会编译失败。
/// 因此按平台条件导出：非 Web 走 io 实现，Web 走空实现。
library;

export 'player_mpv_stub.dart' if (dart.library.io) 'player_mpv_io.dart';
