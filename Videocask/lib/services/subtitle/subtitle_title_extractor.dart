/// 从磁力详情页的片名 / release 名里，抽出可用于 IMDb 联想查询的干净片名。
///
/// 纯函数，无 Flutter / 网络 / dart:io 依赖，便于单测。
/// 真机实测输入（此前整串丢给 IMDb，命中率为 0）：
/// ```text
/// [DBD-Raws][流浪地球/The.Wandering.Earth.][1080P][BDRip][HEVC-10bit][简体内封][FLAC][MKV]
/// ```
/// 期望输出：中文 `流浪地球`、英文 `The Wandering Earth`。
///
/// 也覆盖无方括号的常规 release 名：
/// `The.Wandering.Earth.2019.1080p.BluRay.x264-CHD.mkv`
library;

/// 清洗结果。[local] 为中文片名，[english] 为拉丁片名，二者都可能为空。
class SubtitleTitleQuery {
  const SubtitleTitleQuery({
    required this.local,
    required this.english,
    this.year,
  });

  final String local;
  final String english;
  final String? year;

  bool get isEmpty => local.isEmpty && english.isEmpty;
}

final RegExp _cjk = RegExp(r'[\u3400-\u9fff]');
final RegExp _latin = RegExp(r'[A-Za-z]');
final RegExp _bracket = RegExp(r'[\[\(]([^\[\]\(\)]*)[\)\]]');
final RegExp _splitter = RegExp(r'[/／|]');

/// 发布组 / 音视频规格噪声词。命中即整词丢弃（只在拉丁片名清洗里用）。
const Set<String> _noiseWords = <String>{
  '1080p', '1080i', '720p', '720i', '2160p', '4320p', '4k', '8k',
  'hdr10', 'hdr', 'sdr', '10bit', '8bit', '12bit',
  'x264', 'x265', 'h264', 'h265', 'hevc', 'avc', 'vc1', 'av1',
  'bdrip', 'bluray', 'blueray', 'brrip', 'webdl', 'web-dl', 'webrip',
  'dvdrip', 'remux', 'hdtv', 'hdcam', 'cam', 'ts', 'tc', 'dvdscr',
  'aac', 'flac', 'ddp', 'dd', 'atmos', 'truehd', 'dts', 'dts-hd',
  'mkv', 'mp4', 'avi', 'iso', 'm2ts', 'wmv', 'mov',
  'chs', 'cht', 'gb', 'big5', 'cn', 'tw', 'hk', 'jpsc', 'sc',
  'dbd-raws', 'raws', 'chd', 'wiki', 'frds', 'cmct', 'ourtv', 'yyets',
  '5.1', '7.1', 'ma', 'ddp5', 'ac3', 'eac3', 'lpcm', 'pcm',
  'sub', 'subs', 'subtitle', 'subtitles', 'movie', 'video',
  // 真机 2026-11-11：`Hi Mom 2021 720p Chinese HDRip HC H264 BONE`
  // 清洗成 `Hi Mom Chinese HDRip HC BONE`，IMDb 三路全 null。
  // 这些是压制组/规格词，不是片名。
  'hdrip', 'hdrips', 'hc', 'bone', 'chinese', 'english', 'eng',
  'dub', 'dubbed', 'subbed', 'hardsub', 'softsub', 'web', 'hdtvrip',
  'proper', 'repack', 'internal', 'limited', 'unrated', 'extended',
  'remastered', 'imax', 'dv', 'dolby', 'vision', 'hdr10plus',
  'dvdr', 'bd', 'uhd', 'fhd', 'hd', 'sd', '3d', 'pdtv', 'camrip',
};

/// 「技术标签起点」：release 名的通用格式是
/// `片名 年份 分辨率 片源 编码 压制组`，一旦出现第一个规格标签，
/// 后面的词全都是标签，直接截断比逐个列黑名单可靠。
///
/// 之前只靠 [_noiseWords] 逐词过滤，`Chinese / HC / BONE` 这些
/// 没进词表的词就混进片名，导致 IMDb 联想命中率为 0。
const Set<String> _releaseTagStarters = <String>{
  '480p', '540p', '576p', '720p', '720i', '1080p', '1080i', '1440p',
  '2160p', '4320p', '4k', '8k', 'uhd', 'fhd',
  'hdrip', 'bdrip', 'brrip', 'webdl', 'web-dl', 'webrip', 'dvdrip',
  'hdtv', 'hdtvrip', 'remux', 'hdcam', 'camrip', 'pdtv', 'dvdscr',
  'x264', 'x265', 'h264', 'h265', 'hevc', 'avc', 'av1', 'vc1',
  'bluray', 'blueray', 'hdr', 'hdr10', 'hdr10plus', 'sdr', '10bit',
  'mkv', 'mp4', 'avi', 'iso', 'm2ts',
};

/// 中文片名里的噪声短语（不会误伤片名本身）。
final RegExp _localNoise = RegExp(
  r'简体内封|简体中字|简体|繁体中字|繁体|内封|外挂|中文字幕|中字|字幕|双语|'
  r'国粤|国语|粤语|原盘|收藏版|导演剪辑版|未删减|完整版|高清|蓝光|'
  r'第[0-9一二三四五六七八九十百]+季|第[0-9一二三四五六七八九十百]+集|'
  r'S\d{1,2}E\d{1,3}|EP?\d{1,3}',
  caseSensitive: false,
);

/// 分辨率样的四位数，不能当上映年份。
const Set<String> _notYears = <String>{
  '1080', '1920', '2048', '2160', '2560', '3840', '1440', '4320',
};

String? _extractYear(String text) {
  final re = RegExp(r'(?<!\d)((?:19|20)\d{2})(?!\d)');
  for (final m in re.allMatches(text)) {
    final y = m.group(1)!;
    if (_notYears.contains(y)) continue;
    return y;
  }
  return null;
}

bool _looksLikeTag(String group) {
  final t = group.toLowerCase().trim();
  if (t.isEmpty) return true;
  if (RegExp(r'^\d{3,4}[pi]$').hasMatch(t)) return true;
  if (RegExp(r'^\d+(?:bit|fps|ch)?$').hasMatch(t)) return true;
  if (_noiseWords.contains(t)) return true;
  if (RegExp(r'简体内封|内封|外挂|中字|字幕|双语|国配|国语|粤语|特效').hasMatch(group)) {
    return true;
  }
  // `MKV` / `FLAC` / `10bit` 这类短标签，长度 ≤4 且非中文一律视为标签。
  if (t.length <= 4 && !_cjk.hasMatch(group)) return true;
  return false;
}

/// 清洗拉丁片名：分隔符归一 → 去括号组 → 去年份/季集/分辨率 → 去噪声词。
String _cleanLatin(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  s = s.replaceAll(_bracket, ' ');
  s = s.replaceAll(RegExp(r'[._\-]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

  // 🔴 截断必须发生在「删分辨率」之前。`2160p` / `1080p` 会被下面的
  // `\b\d{3,4}[pi]\b` 直接抹掉，等抹完再找标签起点就找不到了
  // （单测 `Dune...2160p.WEB-DL...` 曾漏出 `DL` 就是这么来的）。
  final tokens = s.split(' ');
  final cut = tokens.indexWhere(
    (w) => _releaseTagStarters.contains(w.toLowerCase()),
  );
  if (cut >= 0) tokens.removeRange(cut, tokens.length);
  s = tokens.join(' ');

  s = s.replaceAll(RegExp(r'\b(?:19|20)\d{2}\b'), ' ');
  s = s.replaceAll(RegExp(r'\b\d{3,5}x\d{3,5}\b', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'\bS\d{1,2}E\d{1,3}\b', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'\b\d{3,4}[pi]\b', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'\b\d+bit\b', caseSensitive: false), ' ');
  final kept = <String>[];
  for (final word in s.split(' ')) {
    final w = word.trim();
    if (w.isEmpty) continue;
    if (RegExp(r'^\d+$').hasMatch(w)) continue;
    final lw = w.toLowerCase();
    // 🔴 规格标签一旦出现，后面整段都是压制组信息，直接停。
    // `Hi Mom 2021 720p Chinese HDRip HC H264 BONE` -> `Hi Mom`。
    if (_releaseTagStarters.contains(lw)) break;
    if (_noiseWords.contains(lw)) continue;
    if (!_latin.hasMatch(w)) continue;
    kept.add(w);
  }
  return kept.join(' ').trim();
}

/// 清洗中文片名：去括号组 / 噪声短语 / 年份 / 季集 / 分隔符。
String _cleanLocal(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  s = s.replaceAll(_bracket, ' ');
  s = s.replaceAll(_localNoise, ' ');
  s = s.replaceAll(RegExp(r'\b(?:19|20)\d{2}\b'), ' ');
  s = s.replaceAll(RegExp(r'[._\-/|]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  // 只保留中文、拉丁字母、数字与少量常见标点。
  s = s.replaceAll(RegExp(r'[^\u3400-\u9fffA-Za-z0-9 !?:：!！&]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  // 🔴 纯拉丁/数字残渣（`mkv`、`mp4`、哈希碎片）不是中文片名。
  // 真机 2026-11-08 磁力日志出现过 `中文=mkv`，就是这一步没挡住。
  if (!_cjk.hasMatch(s)) return '';
  return s;
}

/// 纯哈希 / btih / 内部 ID：不是片名，喂给 IMDb 只会命中错误条目。
///
/// 真机 2026-11-08：磁力详情页把 40 位 btih
/// `9a384d74548884dc4ae9c4ebe1911c402251135a` 当成 `Movie.name`，
/// 清洗器从中抽出 `年份=1911`、英文=整串哈希，IMDb 解析到 `tt0230911`
/// → 「在线源无中文字幕」。磁力线路因此拿不到任何在线字幕。
bool _looksLikeOpaqueId(String text) {
  final t = text.trim();
  if (t.length < 24) return false;
  final joined = t.replaceAll(RegExp(r'[\s.\-_:/\[\]]+'), '');
  if (joined.length < 24) return false;
  return RegExp(r'^[0-9a-fA-F]+$').hasMatch(joined);
}

/// 入口：从片名与种子文件名里抽出中英片名 + 年份。
SubtitleTitleQuery extractSubtitleTitleQuery({
  required String primary,
  String releaseName = '',
}) {
  // btih / 内部 ID 不是片名：整串忽略，让下面的 releaseName 兜底生效。
  final raw = _looksLikeOpaqueId(primary) ? '' : primary.trim();
  final rel = releaseName.trim();
  final year = _extractYear('$raw $rel');
  // main 片名被判成 btih 哈希时（raw=''），方括号组改从 releaseName 里取，
  // 否则 D 步只会拿到清洗过的整串，丢掉 `[流浪地球/The.Wandering.Earth.]`
  // 这种最有价值的中英并列组。
  final groups = _bracket
      .allMatches(raw.isNotEmpty ? raw : rel)
      .map((m) => (m.group(1) ?? '').trim())
      .where((g) => g.isNotEmpty)
      .toList();

  var local = '';
  var english = '';

  // A. 最可靠：方括号组里中英并列，如 `流浪地球/The.Wandering.Earth.`。
  for (final g in groups) {
    if (!_splitter.hasMatch(g)) continue;
    var l = '';
    var e = '';
    for (final part in g.split(_splitter)) {
      if (_cjk.hasMatch(part)) {
        final c = _cleanLocal(part);
        if (c.length > l.length) l = c;
      } else {
        final c = _cleanLatin(part);
        if (c.length > e.length) e = c;
      }
    }
    if (l.isNotEmpty || e.length >= 3) {
      local = l;
      english = e;
      break;
    }
  }

  // B. 方括号组里分别找中文名与拉丁名，跳过规格标签。
  if (local.isEmpty) {
    for (final g in groups) {
      if (!_cjk.hasMatch(g) || _looksLikeTag(g)) continue;
      final c = _cleanLocal(g);
      if (c.length >= 2 && c.length <= 40) {
        local = c;
        break;
      }
    }
  }
  if (english.isEmpty) {
    for (final g in groups) {
      if (_cjk.hasMatch(g) || _looksLikeTag(g)) continue;
      final c = _cleanLatin(g);
      if (c.length >= 3) {
        english = c;
        break;
      }
    }
  }

  // C. 没有方括号（或方括号里全是标签）：直接清洗整串。
  if (local.isEmpty && english.isEmpty) {
    final stripped = raw.replaceAll(_bracket, ' ');
    if (_cjk.hasMatch(stripped) && !stripped.contains('/')) {
      local = _cleanLocal(stripped);
    } else {
      english = _cleanLatin(stripped);
    }
  }

  // D. 种子文件名兜底：常见形态 `The.Wandering.Earth.2019...mkv`。
  if (english.isEmpty && rel.isNotEmpty && !_cjk.hasMatch(rel)) {
    english = _cleanLatin(rel);
  }
  if (local.isEmpty && rel.isNotEmpty && _cjk.hasMatch(rel)) {
    final c = _cleanLocal(rel);
    if (c.length >= 2 && c.length <= 40) local = c;
  }

  // E. 中文名里混了拉丁词时再拆一次，避免把 `流浪地球 The` 当整体去查。
  if (local.isNotEmpty && _cjk.hasMatch(local) && _latin.hasMatch(local)) {
    final words = local.split(RegExp(r'\s+'));
    final cjkWords = words.where((w) => _cjk.hasMatch(w)).toList();
    final enWords = words.where((w) => !_cjk.hasMatch(w) && _latin.hasMatch(w));
    local = cjkWords.join('');
    if (english.isEmpty && enWords.isNotEmpty) {
      english = _cleanLatin(enWords.join(' '));
    }
  }

  return SubtitleTitleQuery(
    local: local,
    english: english,
    year: year,
  );
}
