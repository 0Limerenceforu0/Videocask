import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../config/app_env.dart';
import '../config/routes.dart';

/// Android / iOS 上前台深度链接（`app_links`），与桌面 argv [PendingDeepLink] 互补。
class DeepLinkStreamService {
  DeepLinkStreamService._();

  static final DeepLinkStreamService instance = DeepLinkStreamService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// 在应用初始化完成后调用；测试模式下不注册。
  Future<void> start() async {
    if (kIsWeb || AppEnv.isTestMode) {
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    await _subscription?.cancel();
    final initial = await _appLinks.getInitialLink();
    if (initial != null) {
      await AppRoutes.handleDeepLinkForRouter(AppRoutes.router, initial);
    }
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(
        AppRoutes.handleDeepLinkForRouter(AppRoutes.router, uri),
      ),
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
