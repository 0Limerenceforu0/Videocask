import '../models/movie.dart';

/// 为在线字幕搜索生成关键词（磁力种子名过长、含分辨率/小组标记时先清洗，并尝试别名）。
class SubtitleSearchQueries {
  SubtitleSearchQueries._();

  /// 按优先级排序的去重关键词列表。
  static List<String> forMovie(Movie m) {
    final out = <String>[];
    void add(String? s) {
      final t = s?.trim() ?? '';
      if (t.length < 2) return;
      if (!out.contains(t)) out.add(t);
    }

    final name = m.name.trim();
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(name);

    if (hasCjk) {
      add(name);
    } else {
      add(_cleanTorrentStyleTitle(name));
      final paren = RegExp(r'\((\d{4})\)').firstMatch(name);
      if (paren != null) {
        final core = name.substring(0, paren.start).trim();
        if (core.length >= 2) {
          add(core);
          add('$core ${paren.group(1)}');
        }
      }
    }

    add(m.alias.trim());
    add(name);

    return out;
  }

  /// 去掉常见压制组/分辨率标记，便于 OpenSubtitles 按片名命中。
  static String _cleanTorrentStyleTitle(String raw) {
    var s = raw;
    s = s.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    s = s.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
    s = s.replaceAll(
      RegExp(
        r'\b(480p|720p|1080p|2160p|4320p|4k|5k|8k|hdr|sdr|uhd|blu-?ray|bdrip|brrip|web-?dl|webrip|dvdrip|hdtv|cam|ts|tc|x264|x265|hevc|av1|vp9|h\.?264|h\.?265|10bit|8bit|aac|ddp|atmos|dts|ac3|eac3|repack|proper|remux|internal|limited|extended|unrated|dc|directors|theatrical|yify|yts|galaxy|etrg|evo|fgt|megusta|rapta|sujaidr|rarbg|sparks|dimension|framestor|playhd|hds|nf|amzn|hulu|d\+|dsnp|hmax|pcok|stan)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    s = s.replaceAll(RegExp(r'[-_.]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }
}
