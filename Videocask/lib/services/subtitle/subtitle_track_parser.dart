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

/// 取出所有外挂字幕轨的 mpv 轨道 id，供 `sub-remove <id>` 精确卸载。
///
/// 只认 `external == true` 的 `sub` 轨：内封轨必须原样留着，否则
/// 「恢复内嵌轨」就无从谈起。纯函数，track-list 读失败时返回空列表。
List<int> externalSubtitleTrackIds(String? raw) => parseMpvSubtitleTracks(raw)
    .where((t) => t.isExternal)
    .map((t) => t.id)
    .toList(growable: false);

/// 把 mpv `track-list` 压成「每条轨一行」的短摘要。
///
/// DebugLog 单条会被截断到约 1000 字符，而完整 track-list 动辄 3~6KB：
/// 之前只打 `tracks=...substring(0, 900)`，字幕轨永远落在被截掉的部分，
/// 导致「候选里有中文轨、但 sid 设不上」这个矛盾查不下去。
/// 这里逐条输出关键字段，保证内封 / 外挂字幕轨一定可见。
List<String> describeMpvTracks(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <String>['<empty>'];
  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return <String>['<非 JSON>'];
  }
  if (decoded is! List) return <String>['<非数组>'];
  if (decoded.isEmpty) return const <String>['<无轨道>'];

  final out = <String>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    out.add(
      'id=${item['id']} type=${item['type']} '
      'lang=${item['lang'] ?? '-'} src=${item['src-id'] ?? '-'} '
      'sel=${item['selected'] ?? '-'} ext=${item['external'] ?? '-'} '
      'codec=${item['codec'] ?? '-'} title=${item['title'] ?? '-'}',
    );
  }
  return out;
}
