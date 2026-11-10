/// 字幕渲染归属策略（纯逻辑，可单测）。
///
/// ## 背景：为什么会有「两个字幕 + 黑底」
///
/// 2026-11-08 真机取证（磁力《流浪地球》在线简中 SRT）：
///   1. `PlayerConfiguration.libass = true`（11-07 为修内封 PGS 而开）→
///      mpv 在**视频帧内**用 libass 把字幕画进画面（白字 + 细描边）；
///   2. `DetailComponents.buildSubtitleOverlay()` 又拿 mpv 的 `sub-text`
///      在 Flutter 层画了一遍，且自带 `Colors.black54` 半透明黑底。
/// 结果同一句台词上下叠两份，下面那份被黑框压住一半。
///
/// 11-07 之前 `libass = false`，mpv 只吐 `sub-text` 不绘制，画面上只有浮层
/// 一份 —— 所以这是打开 libass 时没有同步撤掉浮层造成的回归，不是历史行为。
///
/// ## 定案（用户 2026-11-08 拍板）
///
/// **单一渲染源 = mpv/libass。** 理由：
///   - 字幕画进视频帧 → 投屏、截图、录屏看到的内容与手机屏完全一致；
///   - PGS 这类图形字幕没有 `sub-text`，只有 mpv 能画，浮层永远拿不到；
///   - libass 自带描边/阴影，不需要半透明底板。
///
/// Flutter 浮层仅作兜底，用于 mpv 物理上画不了字幕的输出模式：
///   - Android `vo=mediacodec_embed`：绕开 mpv 渲染器，内嵌/图形字幕、OSD、
///     截图、滤镜全部失效（见 `video_output_policy.dart` 的已知代价）；
///   - Web：media_kit 的 web 实现字幕轨行为与原生不同，维持浮层。
library;

/// 字幕由谁渲染。
enum SubtitleRenderer {
  /// mpv/libass 画进视频帧 —— 唯一正式路径。
  mpv,

  /// Flutter 浮层绘制 —— 兜底。
  ///
  /// 字幕不进视频帧，因此投屏与截图看不到；且只支持有 `sub-text` 的文本
  /// 字幕（SRT / ASS），PGS 拿不到文本。
  flutterOverlay,
}

/// 按「mpv 当前能否绘制字幕」决定归属。
SubtitleRenderer resolveSubtitleRenderer({
  required bool mpvCanRenderSubtitle,
}) =>
    mpvCanRenderSubtitle
        ? SubtitleRenderer.mpv
        : SubtitleRenderer.flutterOverlay;

/// 要写给 mpv `sub-visibility` 的值。
///
/// 🔴 浮层兜底模式下也必须写 `yes`：mpv 因 vo 缺渲染器画不出来，但只有
/// `sub-visibility=yes` 时它才继续产出 `sub-text`，Flutter 浮层才有内容可画。
/// 关闭字幕时才写 `no` —— 此时 `sub-text` 也会变空，浮层一并消失，
/// 两条渲染路径的开关语义就此统一。
String subtitleVisibilityValue({required bool showSubtitles}) =>
    showSubtitles ? 'yes' : 'no';

/// Flutter 浮层是否应该显示。
///
/// 三个条件必须同时成立：用户要字幕 + 归属是浮层 + 有文本。
/// 🔴 `renderer == mpv` 时**哪怕 `sub-text` 有内容也必须返回 false** ——
/// 这一条就是「两个字幕」的直接开关，摘掉就会立刻复发。
bool shouldShowFlutterOverlay({
  required bool showSubtitles,
  required SubtitleRenderer renderer,
  required String subtitleText,
}) =>
    showSubtitles &&
    renderer == SubtitleRenderer.flutterOverlay &&
    subtitleText.isNotEmpty;
