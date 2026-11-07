import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../config/pending_deep_link.dart';
import '../config/routes.dart';

/// 包在 [MaterialApp.router] 的 [WidgetBuilder] 子树上，首帧消费 [PendingDeepLink]。
class MaterialAppDeepLinkChild extends StatefulWidget {
  const MaterialAppDeepLinkChild({super.key, required this.child});

  final Widget? child;

  @override
  State<MaterialAppDeepLinkChild> createState() =>
      _MaterialAppDeepLinkChildState();
}

class _MaterialAppDeepLinkChildState extends State<MaterialAppDeepLinkChild> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final uri = PendingDeepLink.takePending();
      if (uri == null) {
        return;
      }
      unawaited(AppRoutes.handleDeepLinkForRouter(AppRoutes.router, uri));
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child ?? const SizedBox.shrink();
  }
}
