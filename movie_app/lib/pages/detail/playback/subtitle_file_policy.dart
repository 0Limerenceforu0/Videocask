import 'subtitle_simplified_policy.dart' show ChineseVariant;

/// 种子内独立字幕文件的轻量契约。
///
/// 不直接依赖 `libtorrent_flutter` 的 `FileInfo`（那是 dart:ffi 实现，
/// Web 编不进去），把「选哪一条字幕」留在纯函数层，方便单测。
class TorrentSubtitleCandidate {
  const TorrentSubtitleCandidate({
    required this.index,
    required this.name,
    required this.size,
  });

  /// 文件在种子里的索引，直接喂给 `startStream(fileIndex:)`。
  final int index;

  /// 文件名（含路径），用于判语言与真实扩展名。
  final String name;

  /// 文件字节数。
  final int size;
}

/// S3 允许的字幕扩展名。ASS/SSA 保留原格式，不合成 SRT，避免丢特效。
const Set<String> subtitleFileExtensions = <String>{
  '.srt',
  '.ass',
  '.ssa',
  '.vtt',
  '.sub',
};

/// 单条字幕超过 16 MB 就不碰：防误选，也防止拖慢起播。
const int maxTorrentSubtitleBytes = 16 * 1024 * 1024;

/// 是否是字幕文件。
bool isSubtitleFileName(String name) {
  final n = name.trim().toLowerCase();
  return subtitleFileExtensions.any(n.endsWith);
}

/// 取真实扩展名（落盘时沿用，ASS 不能改成 .srt）。
String subtitleFileExtension(String name) {
  final n = name.trim().toLowerCase();
  for (final e in subtitleFileExtensions) {
    if (n.endsWith(e)) return e;
  }
  return '.srt';
}

/// 按文件名标记判简 / 繁 / 中文未分 / 非中文。
///
/// 用分词后的**精确 token**匹配，避免 `screen.srt` 里的 `sc` 被当成简体、
/// 或 `description.ass` 里的 `tc` 被当成繁体。中文标记用词包含判定。
ChineseVariant subtitleFileVariant(String name) {
  final tokens = name
      .toLowerCase()
      .replaceAll(RegExp(r'\.(srt|ass|ssa|vtt|sub)$'), '')
      .split(RegExp(r'[^a-z0-9\u4e00-\u9fa5]+'))
      .where((t) => t.isNotEmpty)
      .toList(growable: false);

  const simplified = <String>{
    'sc',
    'chs',
    'hans',
    'zhcn',
    'zhhans',
    'gb',
    'gbk',
    '简体',
    '简中',
    '简体中文',
    'simplified',
  };
  const traditional = <String>{
    'tc',
    'cht',
    'hant',
    'zhtw',
    'zhhant',
    'big5',
    '繁体',
    '繁體',
    '繁中',
    '繁體中文',
    'traditional',
  };

  var hasSimplified = false;
  var hasTraditional = false;
  for (final t in tokens) {
    if (simplified.contains(t) ||
        t.contains('简体') ||
        t.contains('简中') ||
        t.contains('简繁')) {
      hasSimplified = true;
    }
    if (traditional.contains(t) ||
        t.contains('繁体') ||
        t.contains('繁體') ||
        t.contains('繁中')) {
      hasTraditional = true;
    }
  }
  // 同时标简繁（如「简繁英双语」）按简体优先，满足「需要简体中文」。
  if (hasSimplified) return ChineseVariant.simplified;
  if (hasTraditional) return ChineseVariant.traditional;
  if (tokens.any((t) =>
      t == 'zh' ||
      t == 'zho' ||
      t == 'chi' ||
      t == 'chinese' ||
      t == 'cn' ||
      t.contains('中文') ||
      t.contains('中字'))) {
    return ChineseVariant.neutral;
  }
  return ChineseVariant.notChinese;
}

/// 排序权重：简体 0 < 中文未分 1 < 繁体 2；非中文直接排除。
int torrentSubtitleRank(String name) {
  switch (subtitleFileVariant(name)) {
    case ChineseVariant.simplified:
      return 0;
    case ChineseVariant.neutral:
      return 1;
    case ChineseVariant.traditional:
      return 2;
    case ChineseVariant.notChinese:
      return 3;
  }
}

/// 挑出最该挂载的一条中文字幕。
///
/// 返回 null 表示「种子里没有可用中文字幕」，调用方据此**不建第二个种子、
/// 不建第二条流**，纯视频种子零额外开销。非中文（含纯英文）字幕不在这里
/// 挂载，留给后续双语 / 机翻链路处理。
TorrentSubtitleCandidate? pickChineseSubtitleFile(
  Iterable<TorrentSubtitleCandidate> files,
) {
  final scored = <({TorrentSubtitleCandidate file, int rank})>[];
  for (final f in files) {
    if (!isSubtitleFileName(f.name)) continue;
    if (f.size <= 0 || f.size > maxTorrentSubtitleBytes) continue;
    final rank = torrentSubtitleRank(f.name);
    if (rank >= 3) continue;
    scored.add((file: f, rank: rank));
  }
  if (scored.isEmpty) return null;
  scored.sort((a, b) {
    final byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) return byRank;
    // 同权重挑小的：几百 KB 的字幕几秒读完，少占起播后的带宽。
    final bySize = a.file.size.compareTo(b.file.size);
    if (bySize != 0) return bySize;
    // 最终用索引兜底，保证排序稳定可测。
    return a.file.index.compareTo(b.file.index);
  });
  return scored.first.file;
}

/// 是否值得为字幕额外建流。
bool hasChineseSubtitleFile(Iterable<TorrentSubtitleCandidate> files) =>
    pickChineseSubtitleFile(files) != null;
