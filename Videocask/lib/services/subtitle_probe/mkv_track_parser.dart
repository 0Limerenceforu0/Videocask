/// 从 MKV（EBML）文件头部字节里读出轨道信息。
///
/// 为什么需要它：磁力资源大多只有一个 `.mkv` 文件，内封字幕**不在文件列表里**，
/// 光看种子元数据判不出来。但 MKV 的 `Tracks` 元素在文件开头（一般在首个 1–2 MB
/// 内），所以只要读到文件头就能知道有几条字幕轨、什么语言。
///
/// 实现取向：不做完整 EBML 树解析（Segment 常是 unknown-size，递归容易踩坑），
/// 改为在字节流里定位 `Tracks` 元素 ID 后解析其直接子元素。轨道类型会做合法性
/// 校验（1–17），误命中概率极低。
library;

import 'dart:typed_data';

/// 一条轨道。
class MkvTrack {
  const MkvTrack({
    required this.number,
    required this.type,
    required this.codecId,
    required this.language,
    this.name,
  });

  /// 轨道号（`TrackNumber`）。
  final int number;

  /// 轨道类型：1=视频 2=音频 17=字幕。
  final int type;

  /// 编码格式，如 `S_TEXT/UTF8`、`S_HDMV/PGS`。
  final String codecId;

  /// 语言标签（两位 ISO639-2 或 IETF），可能为空。
  final String language;

  /// 轨道名，可能为空。
  final String? name;

  bool get isSubtitle => type == 17;

  /// 是否是**文本**字幕轨（能取到台词文本）。PGS/VobSub 是图形字幕，只能画不能取文本。
  bool get isTextSubtitle =>
      isSubtitle && !codecId.contains('PGS') && !codecId.contains('VOBSUB');

  /// 语言是否可判定为中文。`und`/空 时再看轨道名兜底。
  ///
  /// `zho` 是 ISO639-2 对中文的统称；`chi` 是旧码；`zh` 系是 IETF。
  /// 🔴 2026-11-08：语言常写成 `und`，但 TrackName 里明明白白写着
  /// 「简体中文」「Chinese (Simplified)」，以前这路信息被整个丢掉了。
  bool get isChinese {
    final l = language.trim().toLowerCase();
    if (l.isEmpty || l == 'und') return _nameLooksChinese();
    if (l == 'zho' ||
        l == 'chi' ||
        l == 'zh' ||
        l.startsWith('zh-') ||
        l == 'chs' ||
        l == 'cht' ||
        l == 'chi(s)') {
      return true;
    }
    return _nameLooksChinese();
  }

  bool _nameLooksChinese() {
    final n = (name ?? '').toLowerCase().trim();
    if (n.isEmpty) return false;
    if (n.contains('简体') ||
        n.contains('简中') ||
        n.contains('繁体') ||
        n.contains('繁中') ||
        n.contains('中文') ||
        n.contains('中字') ||
        n.contains('chinese')) {
      return true;
    }
    return RegExp(r'(^|[^a-z])(chs|cht|zho|chi)([^a-z]|$)').hasMatch(n);
  }

  @override
  String toString() =>
      'MkvTrack(#$number type=$type codec=$codecId lang=$language name=$name)';
}

/// 解析结果。`tracks` 为空且 [foundTracksElement] 为 true 表示「确实没有轨道」
/// （几乎不可能），为 false 表示**没找到 Tracks 元素**（数据不够 / 不是 MKV）。
class MkvTrackParseResult {
  const MkvTrackParseResult({
    required this.tracks,
    required this.foundTracksElement,
  });

  final List<MkvTrack> tracks;
  final bool foundTracksElement;

  static const empty = MkvTrackParseResult(
    tracks: <MkvTrack>[],
    foundTracksElement: false,
  );

  List<MkvTrack> get subtitleTracks =>
      tracks.where((t) => t.isSubtitle).toList(growable: false);

  bool get hasChineseSubtitle => subtitleTracks.any((t) => t.isChinese);
}

const int _idTracks = 0x1654AE6B;
const int _idTrackEntry = 0xAE;
const int _idTrackNumber = 0xD7;
const int _idTrackType = 0x83;
const int _idCodecId = 0x86;
const int _idLanguage = 0x22B59C;
const int _idLanguageIetf = 0x22B59D;
const int _idName = 0x536E;

/// 在 [bytes] 里查找第一个 `Tracks` 元素并解析。
///
/// [bytes] 应是文件开头的连续字节（建议 ≥ 1 MB）。
MkvTrackParseResult parseMkvTracks(Uint8List bytes) {
  final start = _indexOfId(bytes, _idTracks);
  if (start < 0) return MkvTrackParseResult.empty;

  var pos = start + 4; // 跳过 4 字节 ID
  final size = _readVintSize(bytes, pos);
  if (size == null) return MkvTrackParseResult.empty;
  pos = size.next;

  var end = bytes.length;
  if (!size.isUnknown) {
    final declared = pos + size.value;
    if (declared > pos && declared < bytes.length) end = declared;
  }

  final tracks = <MkvTrack>[];
  while (pos < end) {
    final id = _readVintId(bytes, pos);
    if (id == null) break;
    final elemSize = _readVintSize(bytes, id.next);
    if (elemSize == null) break;
    final bodyStart = elemSize.next;
    var bodyEnd = bytes.length;
    if (!elemSize.isUnknown) {
      bodyEnd = bodyStart + elemSize.value;
      if (bodyEnd > bytes.length) break; // 截断，停止
    }
    if (id.value == _idTrackEntry) {
      final track = _parseTrackEntry(bytes, bodyStart, bodyEnd);
      if (track != null) tracks.add(track);
    }
    pos = bodyEnd;
    if (elemSize.isUnknown) break;
  }

  return MkvTrackParseResult(tracks: tracks, foundTracksElement: true);
}

MkvTrack? _parseTrackEntry(Uint8List bytes, int start, int end) {
  int? number;
  int? type;
  var codec = '';
  var language = '';
  var languageIetf = '';
  String? name;

  var pos = start;
  while (pos < end) {
    final id = _readVintId(bytes, pos);
    if (id == null) break;
    final size = _readVintSize(bytes, id.next);
    if (size == null) break;
    final bodyStart = size.next;
    if (size.isUnknown) break;
    final bodyEnd = bodyStart + size.value;
    if (bodyEnd > end || bodyEnd < bodyStart) break;

    switch (id.value) {
      case _idTrackNumber:
        number = _readUint(bytes, bodyStart, bodyEnd);
        break;
      case _idTrackType:
        type = _readUint(bytes, bodyStart, bodyEnd);
        break;
      case _idCodecId:
        codec = _readString(bytes, bodyStart, bodyEnd);
        break;
      case _idLanguage:
        language = _readString(bytes, bodyStart, bodyEnd);
        break;
      case _idLanguageIetf:
        languageIetf = _readString(bytes, bodyStart, bodyEnd);
        break;
      case _idName:
        name = _readString(bytes, bodyStart, bodyEnd);
        break;
    }
    pos = bodyEnd;
  }

  if (type == null || type < 1 || type > 17) return null;
  return MkvTrack(
    number: number ?? -1,
    type: type,
    codecId: codec,
    // IETF 语言（如 zh-Hans）比传统两位码更精确，优先采用。
    language: languageIetf.isNotEmpty ? languageIetf : language,
    name: name,
  );
}

int _indexOfId(Uint8List bytes, int id) {
  final b0 = (id >> 24) & 0xFF;
  final b1 = (id >> 16) & 0xFF;
  final b2 = (id >> 8) & 0xFF;
  final b3 = id & 0xFF;
  for (var i = 0; i + 3 < bytes.length; i++) {
    if (bytes[i] == b0 &&
        bytes[i + 1] == b1 &&
        bytes[i + 2] == b2 &&
        bytes[i + 3] == b3) {
      return i;
    }
  }
  return -1;
}

class _Vint {
  const _Vint(this.value, this.next, {this.isUnknown = false});

  /// 去掉长度标记位后的值。
  final int value;

  /// 该 VINT 之后的下一个字节下标。
  final int next;

  /// `0x01FFFFFFFFFFFFFF` 这类 unknown-size 标记。
  final bool isUnknown;
}

/// 读元素 ID（**保留**标记位，EBML ID 就是这么定义的）。
_Vint? _readVintId(Uint8List bytes, int pos) {
  if (pos >= bytes.length) return null;
  final first = bytes[pos];
  if (first == 0) return null;
  var length = 1;
  var mask = 0x80;
  while (length <= 4 && (first & mask) == 0) {
    mask >>= 1;
    length++;
  }
  if (length > 4 || pos + length > bytes.length) return null;
  var value = 0;
  for (var i = 0; i < length; i++) {
    value = (value << 8) | bytes[pos + i];
  }
  return _Vint(value, pos + length);
}

/// 读元素 size（**去掉**标记位）。
_Vint? _readVintSize(Uint8List bytes, int pos) {
  if (pos >= bytes.length) return null;
  final first = bytes[pos];
  if (first == 0) return null;
  var length = 1;
  var mask = 0x80;
  while (length <= 8 && (first & mask) == 0) {
    mask >>= 1;
    length++;
  }
  if (length > 8 || pos + length > bytes.length) return null;

  var value = first & (mask - 1);
  var allOnes = value == (mask - 1);
  for (var i = 1; i < length; i++) {
    final b = bytes[pos + i];
    value = (value << 8) | b;
    if (b != 0xFF) allOnes = false;
  }
  return _Vint(value, pos + length, isUnknown: allOnes);
}

int? _readUint(Uint8List bytes, int start, int end) {
  if (end <= start) return null;
  var v = 0;
  for (var i = start; i < end; i++) {
    v = (v << 8) | bytes[i];
  }
  return v;
}

String _readString(Uint8List bytes, int start, int end) {
  if (end <= start) return '';
  final slice = bytes.sublist(start, end);
  var stop = slice.indexOf(0);
  if (stop < 0) stop = slice.length;
  return String.fromCharCodes(slice.sublist(0, stop)).trim();
}
