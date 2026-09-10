import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'config/pending_deep_link.dart';
import 'services/error_handler.dart';

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
}

Future<void> _prepareDesktopWindow() async {
  await windowManager.waitUntilReadyToShow();
  await windowManager.show();
  await windowManager.focus();
}
