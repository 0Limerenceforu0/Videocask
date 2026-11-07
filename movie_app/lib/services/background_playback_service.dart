import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 后台播放的前台服务（仅 Android）。
///
/// 服务在原生侧只做两件事：把进程钉在 foreground 优先级、显示一条常驻通知。
/// 播放器本身仍在 Dart 侧，所以这里**不涉及任何播放控制**。
///
/// 为什么必须要有：Android 12+ 退到后台约 10 秒后进程被 freeze，
/// libmpv 的解码线程一起停摆，声音就断了。
class BackgroundPlaybackService {
  BackgroundPlaybackService._();

  static const MethodChannel _channel = MethodChannel('guanzi/playbackService');

  static bool _running = false;

  static bool get isRunning => _running;

  /// 启动（或更新通知文案）。重复调用是安全的。
  static Future<void> start({String? title, String? text}) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<bool>('start', <String, dynamic>{
        if (title != null && title.isNotEmpty) 'title': title,
        if (text != null && text.isNotEmpty) 'text': text,
      });
      _running = true;
    } catch (e) {
      // 桌面平台没有这个通道；ROM 限制前台服务也可能抛异常。
      // 失败不该影响播放本身——只是后台被冻结的概率变高。
      debugPrint('[BackgroundPlayback] start failed: $e');
    }
  }

  static Future<void> stop() async {
    if (kIsWeb || !_running) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (e) {
      debugPrint('[BackgroundPlayback] stop failed: $e');
    }
    _running = false;
  }
}
