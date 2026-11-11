import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/subtitle_style_policy.dart';

/// 字幕视觉样式策略回归测试（2026-11-11）。
///
/// 依据：screencap 原图量化的片源硬字幕（1080x2400，视频画面高 450，
/// 字高约 14px = 3.1%，白字 + 约 1px 细黑边、无阴影、无底板、非粗体、
/// 居中靠下留白约 7%）。锁死「软字幕与硬字幕同款」，同时保留放大档。
void main() {
  group('默认档位', () {
    test('出厂默认就是片源同款', () {
      expect(
        kDefaultSubtitleStylePreset,
        SubtitleStylePreset.burnedIn,
      );
    });

    test('档位名与说明文案非空且两档不同', () {
      expect(subtitleStylePresetLabel(SubtitleStylePreset.burnedIn), '片源同款');
      expect(subtitleStylePresetLabel(SubtitleStylePreset.enlarged), '放大易读');
      expect(
        subtitleStylePresetHint(SubtitleStylePreset.burnedIn),
        isNot(subtitleStylePresetHint(SubtitleStylePreset.enlarged)),
      );
    });
  });

  group('mpv 样式表：片源同款', () {
    final burned = mpvSubtitleStyle(SubtitleStylePreset.burnedIn);
    final enlarged = mpvSubtitleStyle(SubtitleStylePreset.enlarged);

    test('片源同款按 8114 真机 A/B 定标为 1.0，不再按理论公式压到 0.46', () {
      // 实测：sub-scale=1.4 -> 软字幕约 20px，硬字幕中文行 14~16px，
      // 线性定标 1.4*14/20 ≈ 0.98，取整为 1.0（mpv 出厂值）。
      final scale = double.parse(burned['sub-scale']!);
      expect(scale, greaterThan(0.90));
      expect(scale, lessThan(1.15));
      // 放大档仍是 8113 版行为，明显大于片源同款。
      expect(double.parse(enlarged['sub-scale']!), 1.4);
      expect(scale, lessThan(double.parse(enlarged['sub-scale']!)));
      // 锁死 8114 的失败值：0.46 会让软字幕缩到看不见。
      expect(scale, isNot(0.46));
    });

    test('白字 + 黑细边，和硬字幕一致', () {
      expect(burned['sub-color'], '#FFFFFF');
      expect(burned['sub-border-color'], '#000000');
      expect(burned['sub-bold'], 'no');
      expect(
        double.parse(burned['sub-border-size']!),
        lessThan(double.parse(enlarged['sub-border-size']!)),
      );
    });

    test('硬字幕没有投影，片源同款必须关掉阴影', () {
      expect(burned['sub-shadow-offset'], '0');
      expect(enlarged['sub-shadow-offset'], isNot('0'));
    });

    test('两档位置一致（sub-pos=100），与硬字幕落在画面底部同一带', () {
      // 8114 实测：改成 94 会让软字幕上移约 27px 与硬字幕错开。
      expect(burned['sub-pos'], '100');
      expect(enlarged['sub-pos'], '100');
    });

    test('两档都不指定 sub-font（避免设备无该字体导致更丑的回退）', () {
      expect(burned.containsKey('sub-font'), isFalse);
      expect(enlarged.containsKey('sub-font'), isFalse);
    });

    test('两档属性集合完全一致，只改数值（幂等重发不会漏项）', () {
      expect(burned.keys.toSet(), enlarged.keys.toSet());
      expect(burned.length, greaterThanOrEqualTo(8));
    });
  });

  group('Flutter 浮层兜底样式', () {
    test('片源同款是细体 + 单层细阴影，放大档是粗体 + 双层重阴影', () {
      final a = overlaySubtitleStyle(SubtitleStylePreset.burnedIn);
      final b = overlaySubtitleStyle(SubtitleStylePreset.enlarged);
      expect(a.fontWeightIndex, 4); // w400
      expect(a.shadowCount, 1);
      expect(b.fontWeightIndex, 5); // w500
      expect(b.shadowCount, 2);
      expect(a.baseFontSize, lessThan(b.baseFontSize));
    });

    test('字号随屏宽自适应，且片源同款恒小于放大档', () {
      for (final w in <double>[360, 420, 768, 1200]) {
        final a = overlaySubtitleFontSize(
          screenWidth: w,
          preset: SubtitleStylePreset.burnedIn,
        );
        final b = overlaySubtitleFontSize(
          screenWidth: w,
          preset: SubtitleStylePreset.enlarged,
        );
        expect(a, lessThan(b), reason: 'width=$w');
        expect(a, greaterThanOrEqualTo(14));
        expect(b, lessThanOrEqualTo(40));
      }
    });

    test('异常屏宽回退到 420，不产生 NaN / 负数', () {
      for (final w in <double>[0, -1, double.nan, double.infinity]) {
        final size = overlaySubtitleFontSize(
          screenWidth: w,
          preset: SubtitleStylePreset.burnedIn,
        );
        expect(size.isFinite, isTrue);
        expect(size, greaterThan(0));
      }
    });
  });
}
