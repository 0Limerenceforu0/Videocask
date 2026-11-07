/// 磁力「直接下载」：原生端走 libtorrent 写盘，Web 端用占位实现（无 FFI）。
///
/// 与 `torrent_player_service.dart` 同样的条件导出，避免 Web 构建把
/// `dart:ffi` / `dart:io` 的原生实现一起编进去。
library;

export 'magnet_download_service_stub.dart'
    if (dart.library.io) 'magnet_download_service_io.dart';
