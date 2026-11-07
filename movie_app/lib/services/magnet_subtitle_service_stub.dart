/// Web 占位：与原生实现保持同一套 API，让字幕编排器在 Web 上也能编译。
///
/// Web 端没有 libtorrent FFI session，也没有 mpv `track-list`，
/// 种子内独立字幕这一层在 Web 恒不可用，由编排器继续走在线字幕。
class MagnetSubtitleService {
  MagnetSubtitleService._();

  static final MagnetSubtitleService instance = MagnetSubtitleService._();

  factory MagnetSubtitleService() => instance;

  Future<String?> fetchChineseSubtitle({
    required String magnetUri,
  }) async =>
      null;

  void cancel() {}
}
