import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/widgets/hifi_desktop_toolbar.dart';

/// 顶栏图标组在手机 / 桌面两种形态下的行为自测。
///
/// 背景：手机（Android/iOS）顶栏曾并排 6 个图标，与标题争宽度导致
/// RenderFlex 右溢出（360dp 逻辑宽实测溢出 84px，release 下最右图标被裁切）。
/// 修复：手机端不再放与底部导航重复的「关注 / 我的」图标。
void main() {
  Widget wrapWithToolbar({required VoidCallback onToggleDenseMode}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Recommendations'),
            actions: HiFiDesktopToolbar.trailingActions(
              context,
              denseMode: false,
              onToggleDenseMode: onToggleDenseMode,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    '手机窄屏：顶栏不含与底栏重复的「关注/我的」图标，且不溢出',
    (tester) async {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      // 360dp × 800dp（1080×2280 @3x）：修复前 6 图标 + 标题必溢出。
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrapWithToolbar(onToggleDenseMode: () {}));
      await tester.pump();

      // 无 RenderFlex 溢出（摘掉修复即在此抛异常 → 红）。
      expect(tester.takeException(), isNull);

      // 搜索 / 设置 / 密度 / 主题 4 个图标保留。
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.byIcon(Icons.grid_view_outlined), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);

      // 「关注 / 我的」由底部导航承担，顶栏不重复放。
      expect(find.byIcon(Icons.subscriptions_outlined), findsNothing);
      expect(find.byIcon(Icons.person_outline), findsNothing);
      expect(find.byType(IconButton), findsNWidgets(4));

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    '桌面端：顶栏保留全部 6 个图标（无底部导航，关注/我的仅此处可入）',
    (tester) async {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrapWithToolbar(onToggleDenseMode: () {}));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(IconButton), findsNWidgets(6));
      expect(find.byIcon(Icons.subscriptions_outlined), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    },
  );
}
