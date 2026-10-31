/// 进程启动时由 `main` 注入的 `movieapp://…` DeepLink（见 `MaterialAppDeepLinkChild`）。
abstract final class PendingDeepLink {
  PendingDeepLink._();

  static Uri? _pending;

  /// 扫描 `argv` 中的 `movieapp://…` / `magnet:?…`（Windows / Linux / macOS 启动参数）。
  ///
  /// magnet 也收：桌面端用户可能用脚本/快捷方式把磁力链接作为启动参数传入，
  /// 与 Android 的 `magnet:` intent-filter 行为对齐（见
  /// `AppRoutes.handleDeepLinkForRouter` 的 magnet 分支）。
  static void registerFromArguments(List<String> arguments) {
    for (final raw in arguments) {
      final uri = Uri.tryParse(raw.trim());
      if (uri != null &&
          (uri.scheme == 'movieapp' || uri.scheme == 'magnet')) {
        _pending = uri;
        return;
      }
    }
  }

  /// 取出待处理 URI（单次取出后清空）。
  static Uri? takePending() {
    final u = _pending;
    _pending = null;
    return u;
  }
}
