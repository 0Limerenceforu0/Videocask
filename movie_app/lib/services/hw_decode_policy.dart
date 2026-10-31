/// 硬件解码档位定义与持久化互转（**纯逻辑**，不触碰平台/IO，全部可单测）。
///
/// 硬解档位由用户在设置页**手动**选择；App 不再根据运行时探测或崩溃自动改档。
/// 不同机型的 MediaCodec 兼容性差异由用户自行决定开/关硬解。
library;

/// 硬件解码档位。
enum HwDecodeMode {
  /// 关闭硬解，纯软件解码（lavc）。
  disabled,

  /// mpv `auto-safe`：由 mpv 自行挑选已知稳定的后端。
  autoSafe,

  /// Android MediaCodec **拷贝式**：硬件解码 + 拷回 CPU 渲染，兼容性最好。
  mediaCodecCopy,

  /// Android MediaCodec **零拷贝**：性能与功耗最优，但部分机型会卡死/闪退。
  mediaCodecZeroCopy,
}

/// 目标平台（抽象成枚举以便单测，不直接依赖 `dart:io`）。
enum HwDecodePlatform {
  android,
  desktop,
  web,
}

/// 档位对应的 mpv `hwdec` 属性值。
String mpvHwDecValue(HwDecodeMode mode) {
  switch (mode) {
    case HwDecodeMode.disabled:
      return 'no';
    case HwDecodeMode.autoSafe:
      return 'auto-safe';
    case HwDecodeMode.mediaCodecCopy:
      return 'mediacodec-copy';
    case HwDecodeMode.mediaCodecZeroCopy:
      return 'mediacodec';
  }
}

/// 平台对应的默认档位。
///
/// - Android 默认 `mediacodec-copy`：硬解照开，但走兼容性最好的拷贝路径；
/// - 桌面默认 `auto-safe`：交给 mpv 挑；
/// - Web 无 mpv 后端，只能软解。
HwDecodeMode defaultHwDecodeMode(HwDecodePlatform platform) {
  switch (platform) {
    case HwDecodePlatform.android:
      return HwDecodeMode.mediaCodecCopy;
    case HwDecodePlatform.desktop:
      return HwDecodeMode.autoSafe;
    case HwDecodePlatform.web:
      return HwDecodeMode.disabled;
  }
}

/// 档位 ↔ 持久化键（存设置用）。
String encodeHwDecodeMode(HwDecodeMode mode) => mode.name;

/// 从持久化键还原档位；未知/空值回落到平台默认。
HwDecodeMode hwDecodeModeFromKey(
  String? key, {
  required HwDecodePlatform platform,
}) {
  if (key == null || key.isEmpty) return defaultHwDecodeMode(platform);
  for (final mode in HwDecodeMode.values) {
    if (mode.name == key) return mode;
  }
  return defaultHwDecodeMode(platform);
}

/// 档位的用户可读名称（诊断与设置页展示；正式文案走 l10n）。
String hwDecodeModeLabel(HwDecodeMode mode) {
  switch (mode) {
    case HwDecodeMode.disabled:
      return '关闭（软件解码）';
    case HwDecodeMode.autoSafe:
      return '自动（由播放器选择）';
    case HwDecodeMode.mediaCodecCopy:
      return '兼容（硬件解码·拷贝）';
    case HwDecodeMode.mediaCodecZeroCopy:
      return '高性能（硬件解码·零拷贝）';
  }
}
