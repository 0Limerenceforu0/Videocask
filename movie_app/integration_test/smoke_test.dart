import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:movie_app/app.dart';

/// 说明：
/// - 这是“全功能可运行性”的自动化冒烟测试（不覆盖所有业务正确性）。
/// - 配合 `--dart-define=APP_TEST_MODE=true`，可在无网络/无播放引擎可用时稳定跑通页面与路由。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('主要页面可进入且不崩溃', (tester) async {
    await tester.pumpWidget(const MovieApp());

    // 初始化阶段可能会有动画/异步，这里用有限次数的 pump 推进。
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 首页 AppBar 上的按钮：搜索 / 我的 / 设置
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // 进入设置
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('设置'), findsWidgets);

    // 返回首页
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 进入个人中心
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // 个人中心页面标题在不同布局下可能不同，至少确保页面未崩溃并存在可滚动区域
    expect(find.byType(Scrollable), findsWidgets);

    // 返回首页
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 进入搜索
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(TextField), findsWidgets);

    // 输入关键词并触发搜索（只验证不崩溃与能渲染列表）
    await tester.enterText(find.byType(TextField).first, '三体');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 返回
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });
}

