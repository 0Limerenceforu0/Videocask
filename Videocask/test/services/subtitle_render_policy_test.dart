import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/subtitle_render_policy.dart';

/// 字幕渲染归属策略回归测试（2026-11-08）。
///
/// 锁死用户拍板的「单一渲染源 = mpv」：
///   - mpv 能画 → 只能 mpv 画，Flutter 浮层**不得**再叠一份；
///   - mpv 画不了（vo=mediacodec_embed / Web）→ 才允许浮层兜底；
///   - `sub-visibility` 打开恒 yes —— 浮层兜底模式下也必须 yes，
///     否则 mpv 不产出 `sub-text`，浮层没内容可显示；
///   - 关闭字幕写 no，两条渲染路径一起消失。
void main() {
  group('字幕渲染归属', () {
    test('mpv 能画时唯一渲染源是 mpv', () {
      expect(
        resolveSubtitleRenderer(mpvCanRenderSubtitle: true),
        SubtitleRenderer.mpv,
      );
    });

    test('mpv 画不了时回落 Flutter 浮层', () {
      expect(
        resolveSubtitleRenderer(mpvCanRenderSubtitle: false),
        SubtitleRenderer.flutterOverlay,
      );
    });
  });

  group('Flutter 浮层是否显示', () {
    test('mpv 模式即使有 sub-text 也不显示浮层（双字幕的直接开关）', () {
      expect(
        shouldShowFlutterOverlay(
          showSubtitles: true,
          renderer: SubtitleRenderer.mpv,
          subtitleText: '在地球表面建造了一万座行星发动机',
        ),
        isFalse,
      );
    });

    test('浮层兜底模式 + 开关打开 + 有文本 → 显示', () {
      expect(
        shouldShowFlutterOverlay(
          showSubtitles: true,
          renderer: SubtitleRenderer.flutterOverlay,
          subtitleText: '在地球表面建造了一万座行星发动机',
        ),
        isTrue,
      );
    });

    test('浮层兜底模式但用户关了字幕 → 不显示', () {
      expect(
        shouldShowFlutterOverlay(
          showSubtitles: false,
          renderer: SubtitleRenderer.flutterOverlay,
          subtitleText: '台词',
        ),
        isFalse,
      );
    });

    test('浮层兜底模式但没有文本（PGS / 空档）→ 不显示', () {
      expect(
        shouldShowFlutterOverlay(
          showSubtitles: true,
          renderer: SubtitleRenderer.flutterOverlay,
          subtitleText: '',
        ),
        isFalse,
      );
    });
  });

  group('sub-visibility 写入值', () {
    test('打开字幕写 yes（浮层兜底模式同样需要 yes 才有 sub-text）', () {
      expect(subtitleVisibilityValue(showSubtitles: true), 'yes');
    });

    test('关闭字幕写 no', () {
      expect(subtitleVisibilityValue(showSubtitles: false), 'no');
    });
  });
}
