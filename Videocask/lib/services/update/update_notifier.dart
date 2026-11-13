import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'update_download_manager.dart';

/// 应用内更新的系统通知层（仅 Android 真正弹出通知，其它平台为 no-op）。
///
/// 设计目标（用户要的「系统通知式后台下载」）：
/// - 下载进行中：通知栏显示一条带进度条（0~100%）的常驻通知，切到微信/浏览器也能看到；
/// - 下载完成：通知变成「点击安装」，点通知回安装页；
/// - 失败：通知变成「下载失败，点击重试」。
///
/// 通知点击统一交给 [UpdateDownloadManager.onNotificationTap] 处理（重开更新弹窗 /
/// 直接触发安装），本文件只负责「画通知」。
class UpdateNotifier {
  UpdateNotifier._();

  static final UpdateNotifier instance = UpdateNotifier._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _notifyId = 90909;
  static const String _channelId = 'videocask_update';
  static const String _channelName = '应用更新';
  static const String _channelDesc = '下载并安装新版本';
  static const String _icon = '@mipmap/ic_launcher';

  /// 通知栏「取消下载」动作的 id，[init] 的回调据此区分「点通知主体」与「点动作按钮」。
  static const String cancelActionId = 'videocask_update_cancel';

  bool _initialized = false;

  /// 初始化插件并注册「通知点击」回调。幂等，可多次调用。
  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings(_icon);
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onTap,
    );
    _initialized = true;
  }

  /// 请求通知权限（Android 13+ 必需，用户拒绝则常驻通知不可见）。
  /// 仅在真正要弹下载通知前调用，避免启动时就打扰用户。返回 null 表示该平台无需授权。
  Future<bool?> requestPermission() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return androidImpl?.requestNotificationsPermission();
  }

  /// 下载进度通知（常驻、带进度条）。[percent] 取 0~100。
  Future<void> showProgress({
    required int percent,
    required String title,
    required String text,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        showProgress: true,
        maxProgress: 100,
        progress: percent.clamp(0, 100),
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        icon: _icon,
        // 中止下载的唯一入口放在通知栏：弹窗里只保留「关闭」，两者不再混淆。
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            cancelActionId,
            '取消下载',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      ),
    );
    await _plugin.show(_notifyId, title, text, details,
        payload: 'videocask_update_progress');
  }

  /// 下载完成通知（可点击 → 回到安装页）。
  Future<void> showComplete({
    required String title,
    required String text,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        ongoing: false,
        autoCancel: true,
        playSound: true,
        icon: _icon,
      ),
    );
    await _plugin.show(_notifyId, title, text, details,
        payload: 'videocask_update_install');
  }

  /// 失败通知（可点击 → 重试）。
  Future<void> showError({
    required String title,
    required String text,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        ongoing: false,
        autoCancel: true,
        playSound: true,
        icon: _icon,
      ),
    );
    await _plugin.show(_notifyId, title, text, details,
        payload: 'videocask_update_error');
  }

  /// 撤掉下载/完成/失败相关通知（如用户已在弹窗内完成安装）。
  Future<void> cancel() async {
    await _plugin.cancel(_notifyId);
  }

  void _onTap(NotificationResponse response) {
    // 通知栏「取消下载」动作：真正中止下载并撤掉通知。
    if (response.actionId == cancelActionId) {
      UpdateDownloadManager.instance.cancel();
      return;
    }
    UpdateDownloadManager.instance.onNotificationTap();
  }
}
