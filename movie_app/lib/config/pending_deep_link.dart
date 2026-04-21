/// 进程启动时由 `main` 注入的 `movieapp://…` DeepLink（见 `MaterialAppDeepLinkChild`）。
abstract final class PendingDeepLink {
  PendingDeepLink._();

  static Uri? _pending;

  /// 扫描 `argv` 中的 `movieapp://…`（Windows / Linux / macOS 启动参数）。
  static void registerFromArguments(List<String> arguments) {
    for (final raw in arguments) {
      final uri = Uri.tryParse(raw.trim());
      if (uri != null && uri.scheme == 'movieapp') {
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
