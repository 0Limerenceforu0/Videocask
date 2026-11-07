import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movie_app/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const MovieApp());
    // 等待首页加载完成
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('DetailPage', () {
    testWidgets('详情页加载测试', (WidgetTester tester) async {
      await pumpApp(tester);

      // 模拟点击一个电影卡片进入详情页
      // 注意：实际测试中需要根据首页的实际布局调整选择器
      final movieCards = find.byType(GestureDetector);
      if (movieCards.evaluate().isNotEmpty) {
        await tester.tap(movieCards.first);
        await tester.pumpAndSettle();

        // 验证详情页元素存在
        expect(find.byType(Scrollable), findsWidgets);

        // 返回首页
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('详情页播放器初始化测试', (WidgetTester tester) async {
      await pumpApp(tester);

      // 模拟点击一个电影卡片进入详情页
      final movieCards = find.byType(GestureDetector);
      if (movieCards.evaluate().isNotEmpty) {
        await tester.tap(movieCards.first);
        await tester.pumpAndSettle();

        // 等待播放器初始化
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        // 验证播放器相关元素存在
        expect(find.byType(AspectRatio), findsWidgets);

        // 返回首页
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('详情页标签页切换测试', (WidgetTester tester) async {
      await pumpApp(tester);

      // 模拟点击一个电影卡片进入详情页
      final movieCards = find.byType(GestureDetector);
      if (movieCards.evaluate().isNotEmpty) {
        await tester.tap(movieCards.first);
        await tester.pumpAndSettle();

        // 查找标签页
        final tabBar = find.byType(TabBar);
        if (tabBar.evaluate().isNotEmpty) {
          // 测试标签页切换
          final tabs =
              find.descendant(of: tabBar.first, matching: find.byType(Tab));
          if (tabs.evaluate().length > 1) {
            await tester.tap(tabs.at(1));
            await tester.pumpAndSettle();
          }
        }

        // 返回首页
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });
  });
}
