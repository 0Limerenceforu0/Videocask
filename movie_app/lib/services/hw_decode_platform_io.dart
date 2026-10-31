import 'dart:io';

import 'hw_decode_policy.dart';

/// 探测当前运行平台对应的硬解策略平台。
HwDecodePlatform detectHwDecodePlatform() {
  if (Platform.isAndroid) return HwDecodePlatform.android;
  // iOS / macOS / Windows / Linux 都走 mpv 的通用后端（videotoolbox / d3d11va /
  // vaapi），策略上同属 desktop。
  return HwDecodePlatform.desktop;
}
