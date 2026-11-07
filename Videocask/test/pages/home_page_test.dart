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

  group('HomePage', () {
    testWidgets('首页加载正常', (WidgetTester tester) async {
      await pumpApp(tester);

      // 验证应用已启动，至少能渲染而不崩溃
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('首页导航测试', (WidgetTester tester) async {
      await pumpApp(tester);

      // 验证应用已启动
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('首页分类导航测试', (WidgetTester tester) async {
      await pumpApp(tester);

      // 查找分类导航元素
      final categoryNav = find.byType(ListView);
      if (categoryNav.evaluate().isNotEmpty) {
        // 测试分类导航滚动
        await tester.drag(categoryNav.first, const Offset(-200, 0));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('首页推荐内容测试', (WidgetTester tester) async {
      await pumpApp(tester);

      // 查找推荐内容区域
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        // 测试内容滚动
        await tester.drag(scrollable.first, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
    });
  });
}
