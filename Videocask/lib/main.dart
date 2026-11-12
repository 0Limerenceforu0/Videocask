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

/// 桌面端把 `windows/runner/main.cpp` 里 `set_dart_entrypoint_arguments` 传进来的
/// 启动参数交给 [args]（Flutter 会调用带参数的 main）。
///
/// 🔴 不能只读 `Platform.executableArguments`：在 Flutter 桌面它返回的是 **Dart VM
/// 的参数**，不包含应用命令行参数，所以 `PendingDeepLink.registerFromArguments`
/// 一直拿到空数组 —— 注释里写的「桌面端用启动参数传 magnet 链接」实际从未生效，
/// 自动化冒烟也因此无法一键起播。这里优先用入口参数，VM 参数只作兜底。
/// 可选位置参数保证 Web / 移动端引擎调用无参 `main()` 时仍可编译运行。
void main([List<String> args = const <String>[]]) async {
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
    final startupArgs = args.isNotEmpty ? args : Platform.executableArguments;
    PendingDeepLink.registerFromArguments(startupArgs);
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
