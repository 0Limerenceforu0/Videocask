// Web-only fullscreen helpers; `dart:html` until migrated to `package:web`.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

/// 当前引擎是否支持 `requestFullscreen`。
bool get browserFullscreenSupported => html.document.documentElement != null;

Future<void> setBrowserFullscreen(bool enter) async {
  final el = html.document.documentElement;
  if (el == null) return;
  try {
    if (enter) {
      await el.requestFullscreen();
    } else {
      if (html.document.fullscreenElement != null) {
        html.document.exitFullscreen();
      }
    }
  } catch (_) {
    // 用户拒绝全屏或浏览器限制：静默失败
  }
}
