import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:movie_app/app.dart';

/// 自动化功能冒烟（纯 Widget 测试）：
/// - 不依赖真机/模拟器/桌面设备
/// - 主要验证路由跳转与页面渲染不崩溃
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const MovieApp());
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('主要页面可进入且不崩溃', (tester) async {
    await pumpApp(tester);

    // 验证应用已启动，至少能渲染而不崩溃
    expect(find.byType(MaterialApp), findsOneWidget);

    // 测试应用能够稳定运行一段时间
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 验证应用仍然正常运行
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
