/// 字幕视觉样式策略（纯逻辑，可单测）。
///
/// ## 目标：让 App「生成/外挂」的软字幕长得像片源烧录进帧的硬字幕
///
/// 2026-11-11 用 `screencap` 原图（1080x2400）量化了 `Hi Mom 2021 720p`
/// 的片源硬字幕：视频画面区 y=160..610（高 450，2.39:1），中文行字高约
/// 14px（= 画面高 3.1%）、英文行约 12px、字幕块底边距画面底约 32px
/// （= 7.1%）；白字、约 1px 细黑描边、无阴影、无底板、非粗体、居中靠下。
///
/// 🔴 硬字幕本身是视频像素，mpv / Flutter 都改不了它；这里能对齐的只有
/// **软字幕**（在线匹配 SRT、外挂 SRT、内封文本轨、本地离线生成）的观感。
/// 以前把软字幕放大到 `sub-scale=1.4`（字高约 10%）+ 2.5 粗描边 + 阴影，
/// 与硬字幕差 3 倍，一眼就能看出是「外挂上去的」。
///
/// ## sub-scale 必须用真机 A/B 定标，不能按理论公式推算
///
/// 第一版按 mpv 文档推 `0.85 * 55 / 720 * sub-scale`，得出 0.46，
/// 结果 8114 真机上软字幕**缩到几乎看不见**（同帧只剩硬字幕）。
/// 8114 实测（screencap 原图 1080x2400，视频画面高 450，1:1 裁剪对比）：
///   - `sub-scale=1.4`（放大档）→ 软字幕字高约 20px；
///   - 片源硬字幕中文行约 14~16px；
///   - 线性定标 `1.4 * 14 / 20 ≈ 0.98` → 取 **1.0**（mpv 出厂值）。
/// 也就是说 mpv 默认字号本来就与硬字幕相当，之前「放大到 1.4」才是
/// 与片源不一致的根因。`sub-border-size` / `sub-shadow-offset` 同样是
/// 720 高基准下的相对量，会随画面尺寸自动缩放。
library;

/// 字幕样式档位。
enum SubtitleStylePreset {
  /// 片源同款（默认）：与烧录进帧的硬字幕一致 —— 白字、细黑边、无阴影、
  /// 非粗体、字高约画面高 3.1%（450 高画面约 14px）、贴画面底。
  burnedIn,

  /// 放大易读：2026-11-11 8113 版的行为，实测字高约 20px（约 4.4%），
  /// 粗描边 + 阴影。保留它作为可选档，用户觉得「片源同款」偏小时
  /// 可在字幕面板一键切回。
  enlarged,
}

/// 出厂默认档位。
const SubtitleStylePreset kDefaultSubtitleStylePreset =
    SubtitleStylePreset.burnedIn;

/// 档位的中文名（字幕面板显示用，UI 固定中文）。
String subtitleStylePresetLabel(SubtitleStylePreset preset) =>
    preset == SubtitleStylePreset.burnedIn ? '片源同款' : '放大易读';

/// 档位的说明文案。
String subtitleStylePresetHint(SubtitleStylePreset preset) => preset ==
        SubtitleStylePreset.burnedIn
    ? '白字细黑边，与影片自带字幕一致'
    : '字号更大、描边更粗，弱光下更清楚';

/// 下发给 mpv/libass 的字幕属性表。
///
/// 只写会被 `setMpvProperty` 接受的字符串值；不指定 `sub-font`，避免落到
/// 设备上不存在的字体名导致更丑的回退（2026-11-11 实机教训）。
Map<String, String> mpvSubtitleStyle(SubtitleStylePreset preset) {
  final burnedIn = preset == SubtitleStylePreset.burnedIn;
  return <String, String>{
    // 真机 A/B 定标：1.0 -> 约 14px，与硬字幕同尺寸；1.4 -> 约 20px。
    // 绝不能再按理论公式压到 0.46（8114 实测软字幕直接看不见）。
    'sub-scale': burnedIn ? '1.0' : '1.4',
    'sub-color': '#FFFFFF',
    'sub-border-color': '#000000',
    // 1px @450 高画面折到 720 基准约 1.6；放大档沿用 8113 的 2.5。
    'sub-border-size': burnedIn ? '1.4' : '2.5',
    'sub-shadow-color': '#000000',
    // 硬字幕没有投影，片源同款必须关掉。
    'sub-shadow-offset': burnedIn ? '0' : '1.5',
    'sub-bold': 'no',
    // 8114 实测：sub-pos=100 时软字幕与硬字幕都落在画面底部同一带；
    // 改成 94 反而上移约 27px 与硬字幕错开，故两档都保持 100。
    'sub-pos': '100',
  };
}

/// Flutter 浮层兜底路径的样式参数。
///
/// 只在 `vo=mediacodec_embed` / Web（mpv 画不了字幕）时生效，但必须与
/// mpv 路径同一档位，否则同一句台词换个输出模式就变样。
class SubtitleOverlayStyle {
  const SubtitleOverlayStyle({
    required this.baseFontSize,
    required this.minFontSize,
    required this.maxFontSize,
    required this.fontWeightIndex,
    required this.shadowCount,
    required this.bottomInset,
  });

  /// 基准 420 逻辑宽下的字号。
  final double baseFontSize;
  final double minFontSize;
  final double maxFontSize;

  /// `FontWeight` 的 index（w400 = 4，w500 = 5），纯逻辑不引 Flutter。
  final int fontWeightIndex;

  /// 阴影层数：1 = 细黑边近似，2 = 8113 的双层重阴影。
  final int shadowCount;

  /// 距容器底部的额外内缩（逻辑像素）。
  final double bottomInset;
}

/// 取浮层兜底样式。
SubtitleOverlayStyle overlaySubtitleStyle(SubtitleStylePreset preset) =>
    preset == SubtitleStylePreset.burnedIn
        ? const SubtitleOverlayStyle(
            baseFontSize: 18,
            minFontSize: 14,
            maxFontSize: 30,
            fontWeightIndex: 4,
            shadowCount: 1,
            bottomInset: 8,
          )
        : const SubtitleOverlayStyle(
            baseFontSize: 22,
            minFontSize: 18,
            maxFontSize: 40,
            fontWeightIndex: 5,
            shadowCount: 2,
            bottomInset: 0,
          );

/// 浮层字号：按屏幕宽度自适应，边界由档位决定。
double overlaySubtitleFontSize({
  required double screenWidth,
  required SubtitleStylePreset preset,
}) {
  final s = overlaySubtitleStyle(preset);
  final w = screenWidth.isFinite && screenWidth > 0 ? screenWidth : 420.0;
  return (s.baseFontSize * (w / 420)).clamp(s.minFontSize, s.maxFontSize);
}
