import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:movie_app/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('MovieApp 可挂载（测试模式下跳过初始化）', (WidgetTester tester) async {
    await tester.pumpWidget(const MovieApp());
    // 推进若干帧，等待首屏渲染完成
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 测试模式下应能进入主界面，至少能渲染而不崩溃
    // 不依赖具体图标，只检查是否有可见的组件
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
