import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'config/pending_deep_link.dart';
import 'services/app_lifecycle_logger.dart';
import 'services/debug_log.dart';
import 'services/error_handler.dart';
import 'services/playback_experiment.dart';
import 'services/subtitle_ai_service.dart';
import 'utils/web_splash_stub.dart'
    if (dart.library.js_interop) 'utils/web_splash_web.dart' as web_splash;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorHandler().init();

  // 诊断日志：先于 runApp 初始化，保证启动期异常也能被记录。
  await DebugLog.init();

  // 真机 A/B 实验台：仅当外部私有目录存在 experiment.json 时启用。
  await PlaybackExperiment.load();
  PlaybackExperiment.logStart();

  // media_kit 在 Web 上同样必须初始化（Web 后端映射到 HTML <video> + hls.js）。
  MediaKit.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    unawaited(_prepareDesktopWindow());
  }

  if (!kIsWeb) {
    PendingDeepLink.registerFromArguments(Platform.executableArguments);
  }

  // 触发 SubtitleAiService 单例，自动注册在线 / 离线(sherpa_onnx) / 浏览器三种后端。
  SubtitleAiService();

  runApp(const MovieApp());

  // 记录前后台切换，用于区分「系统杀后台」与「前台原生崩溃」。
  AppLifecycleLogger().attach();

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
