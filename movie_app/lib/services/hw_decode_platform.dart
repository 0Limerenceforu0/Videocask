/// 硬件解码目标平台探测（按平台条件导出，Web 侧走 stub）。
///
/// 与 `player_mpv.dart` 同样的既有惯例：Web 上没有 `dart:io`，直接引用
/// `Platform` 会编译失败，因此按平台分发。
library;

export 'hw_decode_platform_stub.dart'
    if (dart.library.io) 'hw_decode_platform_io.dart';
