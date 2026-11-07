import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/player_fit_policy.dart';

void main() {
  group('resolvePlayerFit', () {
    test('默认（两者都 false）= contain（原始比例、对称留边、不裁切）', () {
      expect(
        resolvePlayerFit(cropFill: false, fitCover: false),
        BoxFit.contain,
      );
    });

    test('旧「全屏裁剪」选项为真 = cover（铺满、裁切溢出）', () {
      expect(
        resolvePlayerFit(cropFill: true, fitCover: false),
        BoxFit.cover,
      );
    });

    test('用户手动「铺满」为真 = cover', () {
      expect(
        resolvePlayerFit(cropFill: false, fitCover: true),
        BoxFit.cover,
      );
    });

    test('两个铺满信号同时为真仍为 cover', () {
      expect(
        resolvePlayerFit(cropFill: true, fitCover: true),
        BoxFit.cover,
      );
    });

    test('回归保护：绝不能回到无条件 fitWidth（会纵向溢出裁切）', () {
      // 非全屏、片源比槽「高」时，旧逻辑走 fitWidth 会裁切；新策略必须 contain。
      final fitWhenTallContentInWideSlot =
          resolvePlayerFit(cropFill: false, fitCover: false);
      expect(fitWhenTallContentInWideSlot, isNot(BoxFit.fitWidth));
      expect(fitWhenTallContentInWideSlot, BoxFit.contain);
    });
  });
}
