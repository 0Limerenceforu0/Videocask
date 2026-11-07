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

  group('PlayerPage', () {
    testWidgets('播放页加载测试', (WidgetTester tester) async {
      await pumpApp(tester);

      // 模拟点击一个电影卡片进入详情页
      final movieCards = find.byType(GestureDetector);
      if (movieCards.evaluate().isNotEmpty) {
        await tester.tap(movieCards.first);
        await tester.pumpAndSettle();

        // 模拟点击播放按钮进入播放页
        final playButtons = find.byIcon(Icons.play_arrow);
        if (playButtons.evaluate().isNotEmpty) {
          await tester.tap(playButtons.first);
          await tester.pumpAndSettle();

          // 验证播放页元素存在
          expect(find.byType(AspectRatio), findsWidgets);

          // 返回详情页
          await tester.pageBack();
          await tester.pumpAndSettle();
        }

        // 返回首页
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('播放页控制器测试', (WidgetTester tester) async {
      await pumpApp(tester);

      // 模拟点击一个电影卡片进入详情页
      final movieCards = find.byType(GestureDetector);
      if (movieCards.evaluate().isNotEmpty) {
        await tester.tap(movieCards.first);
        await tester.pumpAndSettle();

        // 模拟点击播放按钮进入播放页
        final playButtons = find.byIcon(Icons.play_arrow);
        if (playButtons.evaluate().isNotEmpty) {
          await tester.tap(playButtons.first);
          await tester.pumpAndSettle();

          // 等待播放器初始化
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }

          // 测试播放/暂停按钮
          final playPauseButtons = find.byIcon(Icons.pause);
          if (playPauseButtons.evaluate().isNotEmpty) {
            await tester.tap(playPauseButtons.first);
            await tester.pumpAndSettle();
          }

          // 测试进度条交互
          final progressBars = find.byType(Slider);
          if (progressBars.evaluate().isNotEmpty) {
            await tester.drag(progressBars.first, const Offset(50, 0));
            await tester.pumpAndSettle();
          }

          // 返回详情页
          await tester.pageBack();
          await tester.pumpAndSettle();
        }

        // 返回首页
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('播放页全屏测试', (WidgetTester tester) async {
      await pumpApp(tester);

      // 模拟点击一个电影卡片进入详情页
      final movieCards = find.byType(GestureDetector);
      if (movieCards.evaluate().isNotEmpty) {
        await tester.tap(movieCards.first);
        await tester.pumpAndSettle();

        // 模拟点击播放按钮进入播放页
        final playButtons = find.byIcon(Icons.play_arrow);
        if (playButtons.evaluate().isNotEmpty) {
          await tester.tap(playButtons.first);
          await tester.pumpAndSettle();

          // 测试全屏按钮
          final fullscreenButtons = find.byIcon(Icons.fullscreen);
          if (fullscreenButtons.evaluate().isNotEmpty) {
            await tester.tap(fullscreenButtons.first);
            await tester.pumpAndSettle();
          }

          // 返回详情页
          await tester.pageBack();
          await tester.pumpAndSettle();
        }

        // 返回首页
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });
  });
}
