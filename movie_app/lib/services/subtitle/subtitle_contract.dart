/// 字幕轨统一契约。
///
/// Native 端来自 mpv `track-list`；Web 端由双语合成器用序号模拟。
/// 这里只放数据类与枚举，不依赖 Flutter / mpv，便于纯函数单测。
class SubtitleTrackInfo {
  const SubtitleTrackInfo({
    required this.id,
    this.lang,
    this.title,
    this.codec = '',
    this.source = SubtitleTrackSource.embedded,
    this.isExternal = false,
  });

  /// mpv 的 track id；Web 端用递增序号，必须 > 0。
  final int id;
  final String? lang;
  final String? title;
  final String codec;
  final SubtitleTrackSource source;
  final bool isExternal;
}

enum SubtitleTrackSource { embedded, torrent, local, online }

/// 来源优先级：本地内封 > 种子内 > 用户手选 > 在线。
/// 「默认中文优先」挑主轨时按此排序，避免在线字幕盖过片源自带的中文轨。
int subtitleSourceRank(SubtitleTrackSource source) {
  switch (source) {
    case SubtitleTrackSource.embedded:
      return 0;
    case SubtitleTrackSource.torrent:
      return 1;
    case SubtitleTrackSource.local:
      return 2;
    case SubtitleTrackSource.online:
      return 3;
  }
}

enum SubtitleDisplayMode { chineseOnly, englishOnly, bilingual, none }

/// 编排器的输出：挂哪条主轨、哪条副轨、是否还要继续找在线中文。
class SubtitleDecision {
  const SubtitleDecision({
    required this.mode,
    this.primaryId,
    this.secondaryId,
    this.needOnlineChinese = false,
    required this.reason,
  });

  final SubtitleDisplayMode mode;
  final int? primaryId;
  final int? secondaryId;
  final bool needOnlineChinese;

  /// 给用户与 DebugLog 看的中文原因，失败必须可见。
  final String reason;
}
