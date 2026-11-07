import 'dart:convert';

import 'subtitle_contract.dart';

/// 解析 mpv `track-list` 属性（JSON 字符串），只保留字幕轨。
///
/// 纯函数：空 / 非 JSON / 结构畸形一律返回空列表，绝不抛异常，
/// 这样 mpv 属性读取失败也不会把播放页打崩。
/// mpv 的 `id == 0` 表示「未选中」，不是真实轨，必须过滤。
List<SubtitleTrackInfo> parseMpvSubtitleTracks(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <SubtitleTrackInfo>[];
  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const <SubtitleTrackInfo>[];
  }
  if (decoded is! List) return const <SubtitleTrackInfo>[];

  final out = <SubtitleTrackInfo>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    if (item['type'] != 'sub') continue;
    final id = item['id'];
    if (id is! int || id <= 0) continue;

    final external = item['external'] == true;
    out.add(
      SubtitleTrackInfo(
        id: id,
        lang: item['lang'] is String ? item['lang'] as String : null,
        title: item['title'] is String ? item['title'] as String : null,
        codec: item['codec'] is String ? item['codec'] as String : '',
        isExternal: external,
        // 外挂轨默认归到「用户手选 / 本地文件」，在线匹配挂载后由调用方
        // 用 copyWith 改成 online，避免被当成片源自带。
        source: external
            ? SubtitleTrackSource.local
            : SubtitleTrackSource.embedded,
      ),
    );
  }
  return out;
}
