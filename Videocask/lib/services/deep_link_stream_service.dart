import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import '../config/app_env.dart';
import '../config/routes.dart';

/// Android / iOS 上前台深度链接（`app_links`），与桌面 argv [PendingDeepLink] 互补。
class DeepLinkStreamService {
  DeepLinkStreamService._();

  static final DeepLinkStreamService instance = DeepLinkStreamService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// 幂等守卫：dispose 可能被应用退出路径与测试析构多次调用。
  bool _released = false;

  /// 在应用初始化完成后调用；测试模式下不注册。
  Future<void> start() async {
    if (kIsWeb || AppEnv.isTestMode) {
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    await _subscription?.cancel();
    // 畸形深链（例如带前导空格/换行的 URI）会让 app_links 内部的 Uri.parse 抛
    // `FormatException: Scheme not starting with alphabetic character`。
    // 绝不能让一条坏链接把整个 App 打成 Flutter 红屏：这里兜住异常，只记日志忽略。
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        await AppRoutes.handleDeepLinkForRouter(AppRoutes.router, initial);
      }
    } catch (e, st) {
      debugPrint('[deeplink] 初始链接解析/处理失败（已忽略）: $e');
      debugPrint('$st');
    }
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(
        () async {
          try {
            await AppRoutes.handleDeepLinkForRouter(AppRoutes.router, uri);
          } catch (e, st) {
            debugPrint('[deeplink] 链接处理失败（已忽略）: $e');
            debugPrint('$st');
          }
        }(),
      ),
      onError: (Object e) {
        debugPrint('[deeplink] 链接流错误（已忽略）: $e');
      },
    );
  }

  Future<void> dispose() async {
    if (_released) return;
    _released = true;
    await _subscription?.cancel();
    _subscription = null;
  }
}
