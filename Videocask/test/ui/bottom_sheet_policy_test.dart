import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 静态兜底：防止「底部弹窗内容被屏幕底边裁掉」第三次复发。
///
/// 2026-11-11 实测：字幕面板的 `showModalBottomSheet` 没带
/// `isScrollControlled`，也没有滚动容器，结果「字幕延时」整行
/// 根本没渲染出来、UI 层级里都找不到。之前另外两个页面各自修过一次，
/// 但没有全局约束，所以同一个问题又冒出来了。
///
/// 这里不依赖 widget 环境，直接扫源码：任何直接调用
/// `showModalBottomSheet` 的地方，后续 15 行内必须出现
/// `isScrollControlled: true`。固定内容的弹窗应改用
/// `widgets/app_bottom_sheet.dart` 的 `showAppBottomSheet`。
void main() {
  test('所有直接调用的 showModalBottomSheet 都必须允许滚动', () {
    final lib = Directory('lib');
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'flutter test 必须在 package 根目录运行',
    );

    final offenders = <String>[];
    final dartFiles = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in dartFiles) {
      final lines = f.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final t = line.trimLeft();
        // 文档注释里的引用（例如「用 [showModalBottomSheet] 弹出」）不算调用。
        if (t.startsWith('//') || t.startsWith('*')) continue;
        if (!line.contains('showModalBottomSheet')) continue;
        final window = lines.skip(i).take(15).join('\n');
        if (!window.contains('isScrollControlled: true')) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '以下弹窗缺少 isScrollControlled: true，内容会被屏幕底边裁掉：\n'
          '${offenders.join('\n')}\n'
          '请改用 showAppBottomSheet，或补上 isScrollControlled + constraints。',
    );
  });

  test('公共底部弹窗同时提供限高、滚动、安全区与键盘避让', () {
    final src = File('lib/widgets/app_bottom_sheet.dart').readAsStringSync();
    expect(src.contains('isScrollControlled: true'), isTrue);
    expect(src.contains('constraints: BoxConstraints'), isTrue);
    expect(src.contains('SingleChildScrollView'), isTrue);
    expect(src.contains('SafeArea'), isTrue);
    expect(src.contains('viewInsetsOf'), isTrue);
  });
}
