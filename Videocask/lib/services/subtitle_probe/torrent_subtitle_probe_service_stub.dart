/// Web 端占位实现：Web 没有 libtorrent / `dart:io`，磁力字幕真实探测不可用。
///
/// 与 `magnet_download_service.dart` 同样的条件导入范式：
/// `magnet_action_widgets.dart` 在非 Web 端加载真实现，Web 端加载本文件，
/// 从而避免把 `dart:ffi` 拖进 dart2js 编译单元（否则
/// `Only JS interop members may be 'external'` 会让 `flutter build web` 失败）。
///
/// 接口必须与 `torrent_subtitle_probe_service.dart` 保持一致，结论统一为
/// 「字幕未知」，不假装探测成功，也不提供深挖入口。
library;

import 'subtitle_probe_verdict.dart';

class TorrentSubtitleProbeService {
  TorrentSubtitleProbeService._();

  static final TorrentSubtitleProbeService instance =
      TorrentSubtitleProbeService._();

  /// Web 端没有本地缓存，恒返回 null，由共用 widget 走「字幕未知」展示。
  SubtitleProbeResult? cached(String magnetUri) => null;

  /// 快速层与深挖层都返回未知；`depth` 用默认值 deep，
  /// 使 `canDeepProbe` 为 false，避免用户点徽标后反复触发无效探测。
  Future<SubtitleProbeResult> probe(
    String magnetUri, {
    bool deep = false,
    int order = 0,
  }) async {
    return const SubtitleProbeResult(
      verdict: SubtitleProbeVerdict.unknown,
      reason: 'Web 端不支持磁力字幕探测',
    );
  }
}
