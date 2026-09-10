import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'config/pending_deep_link.dart';
import 'services/error_handler.dart';
import 'utils/web_splash_stub.dart'
    if (dart.library.js_interop) 'utils/web_splash_web.dart' as web_splash;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorHandler().init();

  // media_kit 在 Web 上同样必须初始化（Web 后端映射到 HTML <video> + hls.js）。
  MediaKit.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    unawaited(_prepareDesktopWindow());
  }

  if (!kIsWeb) {
    PendingDeepLink.registerFromArguments(Platform.executableArguments);
  }

  runApp(const MovieApp());

  // Web 端：首帧渲染完成后移除 index.html 里的启动占位层（"正在加载..."）。
  // 该占位层若不摘除会一直盖在 Flutter 视图上方，表现为永久灰屏
  // （body 背景色 #121212 透出来），并且吞掉所有指针事件。
  if (kIsWeb) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      web_splash.removeWebSplash();
    });
  }
}

Future<void> _prepareDesktopWindow() async {
  await windowManager.waitUntilReadyToShow();
  await windowManager.show();
  await windowManager.focus();
}
