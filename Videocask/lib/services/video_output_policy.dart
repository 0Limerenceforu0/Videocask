/// 视频输出后端（mpv `--vo`）档位定义 + 与持久化键的互转（纯逻辑，可单测）。
///
/// ⚠️ 重要（2026-10-23 真机矩阵定论）：fd 泄漏只取决于「送显桥接」
/// （SurfaceProducer 漏 / SurfaceTexture 不漏），与 `--vo` 无关。本 App 已在
/// player_service 锁死 `enableAndroidSurfaceProducer: false`（SurfaceTexture），
/// 因此三种 `--vo` 都不会泄漏。本枚举现在只影响「渲染库 / 功能 / 黑屏风险」：
///   - gpu-next：libplacebo，功能最全，个别 GPU 首启可能短暂黑屏；
///   - gpu：mpv 旧版 GL，作为黑屏兜底；
///   - mediacodecEmbed：绕过 GL 渲染器，HW 直出，代价是字幕/滤镜/截图失效。
/// 默认 `gpu-next`；生效值由用户在设置页手动切换，App 不做自动换路。
library;

/// 可选的视频输出后端。
enum VideoOutputMode {
  /// mpv 传统 GPU 渲染（旧版 GL 路径）。
  ///
  /// 与 `gpu-next` 一样走 SurfaceTexture 防泄漏桥接，**不会**泄漏 fd（泄漏取决于
  /// 桥而非 vo）。作用：当 `gpu-next`（libplacebo）在个别 GPU 上黑屏时，用它兜底。
  /// 色彩 / 色调映射精度不如 gpu-next。
  gpu,

  /// mpv 新一代 GPU 渲染（libplacebo）。
  ///
  /// 默认推荐。功能最全（内嵌字幕 / OSD / 滤镜 / 截图均可用）。
  /// 个别 GPU / 驱动组合首启可能短暂黑屏（重开一次即恢复），与 fd 泄漏无关。
  gpuNext,

  /// Android MediaCodec 直出 `android.view.Surface`，**不经过 mpv 的 GL 渲染器**。
  ///
  /// 同样不泄漏（桥已锁死）；但必须配 `hwdec=mediacodec`（零拷贝），
  /// 软解下不可用，且绕开 mpv 渲染器（内嵌字幕/OSD/截图/滤镜失效、
  /// 旋转/全屏切换可能闪黑、HDR/10bit 兼容性差）。
  mediacodecEmbed,
}

/// `mediacodec_embed` 的已知代价（设置页与日志都引用，避免重复描述）。
const List<String> mediacodecEmbedDrawbacks = [
  '必须搭配 hwdec=mediacodec（零拷贝），软解不可用，会自动回落 gpu',
  '绕开 mpv 渲染器：内嵌字幕/图形字幕、OSD、截图、视频滤镜（旋转/缩放/裁切/去隔行）全部失效',
  '缩放与宽高比交给 Android Surface 布局，个别机型旋转/全屏切换会闪黑',
  '10-bit / HDR / Dolby Vision 等特殊格式兼容性差于 GL 路径',
];

/// 档位对应的 mpv `--vo` 属性值。
String mpvVoValue(VideoOutputMode mode) {
  switch (mode) {
    case VideoOutputMode.gpu:
      return 'gpu';
    case VideoOutputMode.gpuNext:
      return 'gpu-next';
    case VideoOutputMode.mediacodecEmbed:
      return 'mediacodec_embed';
  }
}

/// 持久化键 <-> 档位。
String encodeVideoOutputMode(VideoOutputMode mode) => mode.name;

VideoOutputMode videoOutputModeFromKey(String? key) {
  switch (key) {
    case 'gpu':
      return VideoOutputMode.gpu;
    case 'gpuNext':
      return VideoOutputMode.gpuNext;
    case 'mediacodecEmbed':
      return VideoOutputMode.mediacodecEmbed;
    default:
      return defaultVideoOutputMode;
  }
}

/// 默认档位：`gpu-next`（新版渲染）。
///
/// fd 泄漏已由 SurfaceTexture 桥接统一修复，与 vo 无关；选它主要因为其功能最全、
/// 且经多机型实测出画稳定。个别 GPU 首启短暂黑屏时可手动改 `gpu` 兜底。
/// 不改变 hwdec——硬解档位取决于用户的硬解开关。
const VideoOutputMode defaultVideoOutputMode = VideoOutputMode.gpuNext;

/// `mediacodec_embed` 只在硬解下有意义：软解时 mpv 不能走 Surface 直出。
bool voRequiresHardwareDecode(VideoOutputMode mode) =>
    mode == VideoOutputMode.mediacodecEmbed;
