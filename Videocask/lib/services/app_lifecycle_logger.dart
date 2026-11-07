import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart';

import 'debug_log.dart';

/// 应用生命周期记录器：把前后台切换 / 进程分离写进诊断日志。
///
/// 用途：区分「闪退」的两种成因——
/// - 看到 paused/inactive 后长时间真空再重启 → 大概率是 Android 系统把后台应用杀掉（LMK/Doze/待机）
/// - 没有任何 paused 直接真空 → 前台原生崩溃（libmpv / media_kit 等 Dart 抓不到）
class AppLifecycleLogger with WidgetsBindingObserver {
  static final AppLifecycleLogger _instance = AppLifecycleLogger._();
  factory AppLifecycleLogger() => _instance;

  AppLifecycleLogger._();

  bool _attached = false;

  void attach() {
    if (_attached) return;
    WidgetsBinding.instance.addObserver(this);
    _attached = true;
    DebugLog.log('Lifecycle', 'observer attached');
  }

  void detach() {
    if (!_attached) return;
    WidgetsBinding.instance.removeObserver(this);
    _attached = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    DebugLog.log('Lifecycle', 'state=$state');
    // 进程即将被分离（被系统回收 / 用户划掉）时尽量把缓冲落盘。
    if (state == AppLifecycleState.detached) {
      // 记录「正常退出」标记，供下次启动区分正常关闭与异常死亡（被系统 LMK 杀死等）
      DebugLog.markCleanShutdown();
      unawaited(DebugLog.close());
    }
  }
}
