import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:movie_app/app.dart';
import 'package:movie_app/config/app_env.dart';
import 'package:movie_app/widgets/hifi_channel_nav_row.dart';

/// Windows + 宽 View（≥900）下首页宽顶栏与 `CategoryPortalModuleRow` 宽布局自测。
///
/// 依赖 `APP_TEST_MODE` 跳过完整初始化（与 [AppEnv.isTestMode] 一致）。
/// 默认 `flutter test` 会跳过本用例；CI 见 `.github/workflows/flutter_ci.yml` 中
/// `Test wide top bar (test mode)` 步骤。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets(
    'Windows 宽屏：顶栏频道行与滚动（APP_TEST_MODE）',
    (tester) async {
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MovieApp());

      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      expect(find.byType(HiFiChannelNavRow), findsOneWidget);
      expect(find.byType(CustomScrollView), findsWidgets);

      debugDefaultTargetPlatformOverride = null;
    },
    skip: !AppEnv.isTestMode,
  );
}
