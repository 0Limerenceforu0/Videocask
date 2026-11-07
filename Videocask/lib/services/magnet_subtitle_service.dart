/// S3：读取种子内独立的中文字幕文件。
///
/// 原生端用第二个短命磁力任务取字节，Web 端用占位实现（无 FFI）。
/// 与 `magnet_download_service.dart` 同构的条件导出，避免 Web 构建把
/// `dart:ffi` / `dart:io` 一起编进去。
library;

export 'magnet_subtitle_service_stub.dart'
    if (dart.library.io) 'magnet_subtitle_service_io.dart';
