/// 非 Web 平台占位（浏览器全屏无操作）。
bool get browserFullscreenSupported => false;

Future<void> setBrowserFullscreen(bool enter) async {}
