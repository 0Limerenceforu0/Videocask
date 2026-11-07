import 'package:flutter/widgets.dart';

/// 应用根导航 key。
///
/// 单独拆成一个文件，是为了让「非页面层」也能拿到根 context
/// （例如启动后的静默更新检查需要弹窗），而**不必 import `routes.dart`**。
/// `routes.dart` 已经 import 了 `settings_page.dart`，若更新弹窗再反向
/// import 路由文件，就会形成循环依赖。
final GlobalKey<NavigatorState> appRootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'appRootNavigator');
