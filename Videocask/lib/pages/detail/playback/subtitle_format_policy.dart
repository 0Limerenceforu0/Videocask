// 字幕文件名 / 编码 / 季集策略层（S5），全部为纯函数，可单测。
//
// 事实约束：项目没有引入 GBK/BIG5 解码包（pubspec 无 charset 类依赖），
// Dart 自带的 dart:convert 只提供 utf8 / latin1 / ascii。所以非 UTF-8 字节
// **不做虚假转码**：保留原始字节原样落盘，并给出明确标记，由调用方写日志
// 提示「疑似 GBK/BIG5」。强行 latin1 解码再 utf8 写出只会把双字节汉字拆成
// 两个 U+00XX，反而彻底破坏字幕。

import 'dart:convert';

/// 从字幕文件名或下载 URL 推断真实扩展名。
///
/// Stremio 免费源返回的多数是 SRT，但文件名可能带 `.ass/.ssa/.vtt`，
/// 下载端点也可能写成 `.srt.gz`。之前一律落 `.srt`，会丢掉 ASS 特效与
/// VTT 的 cue 设置。这里返回带点的扩展名（含默认 `.srt`）。
String subtitleExtensionFor({String? fileName, String? url}) {
  final raw = '${fileName ?? ''} ${url ?? ''}'.toLowerCase();
  final noQuery = raw.split('?').first;
  final re = RegExp(r'\.(srt|ass|ssa|vtt|sub)(?:\.gz)?(?:$|[^a-z0-9])');
  final m = re.firstMatch(noQuery);
  final ext = m?.group(1) ?? 'srt';
  return '.$ext';
}

/// 字幕文本的编码判定结果。
enum SubtitleEncoding {
  utf8,
  utf8Bom,
  utf16Le,
  utf16Be,

  /// 既不是合法 UTF-8、也不像 UTF-16：大概率 GBK / BIG5。
  nonUtf8,
}

/// 解码结果：[text] 为可安全做文本处理（繁→简等）的内容，null 表示
/// 必须原样写字节；[rawBytes] 始终是输入字节，供原样落盘使用。
class SubtitleDecoded {
  const SubtitleDecoded({
    required this.text,
    required this.rawBytes,
    required this.encoding,
    required this.hasBom,
  });

  final String? text;
  final List<int> rawBytes;
  final SubtitleEncoding encoding;
  final bool hasBom;

  bool get isText => text != null;

  String get label {
    switch (encoding) {
      case SubtitleEncoding.utf8:
        return 'UTF-8';
      case SubtitleEncoding.utf8Bom:
        return 'UTF-8 BOM';
      case SubtitleEncoding.utf16Le:
        return 'UTF-16LE';
      case SubtitleEncoding.utf16Be:
        return 'UTF-16BE';
      case SubtitleEncoding.nonUtf8:
        return '非 UTF-8（疑似 GBK/BIG5）';
    }
  }
}

int _u16(List<int> b, int i, bool little) =>
    little ? (b[i] | (b[i + 1] << 8)) : ((b[i] << 8) | b[i + 1]);

String _decodeUtf16(List<int> b, bool little) {
  final sb = StringBuffer();
  for (var i = 0; i + 1 < b.length; i += 2) {
    var unit = _u16(b, i, little);
    if (unit >= 0xD800 && unit <= 0xDBFF && i + 3 < b.length) {
      final low = _u16(b, i + 2, little);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
        i += 2;
      }
    }
    sb.writeCharCode(unit > 0x10FFFF ? 0xFFFD : unit);
  }
  return sb.toString();
}

bool _looksLikeUtf16Le(List<int> b) {
  if (b.length < 4 || b.length.isOdd) return false;
  var zeroHighBytes = 0;
  for (var i = 1; i + 1 < b.length; i += 2) {
    if (b[i] == 0) zeroHighBytes++;
  }
  return zeroHighBytes * 2 >= (b.length ~/ 2);
}

/// 探测字幕字节的编码并尽量解码成文本。
///
/// 顺序：BOM（UTF-8 / UTF-16LE / UTF-16BE）→ 严格 UTF-8 → 无 BOM 的
/// UTF-16LE 启发式 → 保留原始字节。绝不对非 UTF-8 内容做假转码。
SubtitleDecoded decodeSubtitleBytes(List<int> bytes) {
  if (bytes.isEmpty) {
    return SubtitleDecoded(
      text: '',
      rawBytes: bytes,
      encoding: SubtitleEncoding.utf8,
      hasBom: false,
    );
  }
  // UTF-8 BOM
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return SubtitleDecoded(
      text: utf8.decode(bytes.sublist(3), allowMalformed: true),
      rawBytes: bytes,
      encoding: SubtitleEncoding.utf8Bom,
      hasBom: true,
    );
  }
  // UTF-16LE / BE BOM
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return SubtitleDecoded(
      text: _decodeUtf16(bytes.sublist(2), true),
      rawBytes: bytes,
      encoding: SubtitleEncoding.utf16Le,
      hasBom: true,
    );
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return SubtitleDecoded(
      text: _decodeUtf16(bytes.sublist(2), false),
      rawBytes: bytes,
      encoding: SubtitleEncoding.utf16Be,
      hasBom: true,
    );
  }
  // 无 BOM 的 UTF-16LE 必须**先于**严格 UTF-8 判定：纯 ASCII 的 UTF-16
  // 字节序列（'A',0,'B',0…）在 UTF-8 里是合法的（NUL 也是合法码点），
  // 若先做 UTF-8 就会被解成带 NUL 的乱码。
  if (_looksLikeUtf16Le(bytes)) {
    return SubtitleDecoded(
      text: _decodeUtf16(bytes, true),
      rawBytes: bytes,
      encoding: SubtitleEncoding.utf16Le,
      hasBom: false,
    );
  }
  // 严格 UTF-8：失败即说明不是 UTF-8（GBK/BIG5 的汉字字节几乎必然违规）。
  try {
    final text = utf8.decode(bytes);
    return SubtitleDecoded(
      text: text,
      rawBytes: bytes,
      encoding: SubtitleEncoding.utf8,
      hasBom: false,
    );
  } catch (_) {
    // 落到下面的非 UTF-8 判定。
  }
  return SubtitleDecoded(
    text: null,
    rawBytes: bytes,
    encoding: SubtitleEncoding.nonUtf8,
    hasBom: false,
  );
}

/// 从种子 release 名 / 片名里解析季集号，用于免费源的
/// `/subtitles/series/tt:S:E.json` 路径。
///
/// 只认 `S01E02` / `s1e2` / `1x02` 这类明确写法；电影名里孤立的年份
/// 数字不算。解析不到返回 (null, null)，调用方走电影路径。
({int? season, int? episode}) parseSubtitleSeasonEpisode(
  String? releaseName,
  String? title,
) {
  final text = '${releaseName ?? ''} ${title ?? ''}';
  final se = RegExp(
    r'(?:s(\d{1,2})\s*[._ -]*e(\d{1,3}))|(?:(\d{1,2})x(\d{2,3}))',
    caseSensitive: false,
  ).firstMatch(text);
  if (se == null) return (season: null, episode: null);
  final season = int.tryParse(se.group(1) ?? se.group(3) ?? '');
  final episode = int.tryParse(se.group(2) ?? se.group(4) ?? '');
  if (season == null || episode == null || season <= 0 || episode <= 0) {
    return (season: null, episode: null);
  }
  return (season: season, episode: episode);
}
