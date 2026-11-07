import 'dart:js_interop';

/// 移除 Web 端启动占位层（`web/index.html` 中的 `#flutter-splash`）。
///
/// 该占位层若不在首帧后摘除，会一直铺在 Flutter 视图上方，
/// 表现为整页深灰（"灰屏"）且吞掉所有指针事件。
///
/// 优先调用页面上的 `window.__removeFlutterSplash`（它在 index.html 里定义，
/// 自带 3 秒硬兜底）；若页面未更新到新版本，则退化为按 id 直接摘除。
void removeWebSplash() {
  try {
    _evalJs('''
      (function () {
        if (typeof window.__removeFlutterSplash === 'function') {
          window.__removeFlutterSplash();
          return;
        }
        var el = document.getElementById('flutter-splash');
        if (el) { el.remove(); }
      })();
    ''');
  } catch (_) {
    // 忽略：index.html 结构变化不应影响启动主流程。
  }
}

@JS('eval')
external void _evalJs(String code);
