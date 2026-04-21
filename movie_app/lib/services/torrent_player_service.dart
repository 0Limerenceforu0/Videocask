/// 磁力播放：IO 平台使用 libtorrent；Web 使用占位实现（无 FFI）。
library;

export 'torrent_player_models.dart';
export 'torrent_player_service_stub.dart'
    if (dart.library.io) 'torrent_player_service_io.dart';
