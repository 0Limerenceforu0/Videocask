import 'package:flutter/foundation.dart';

/// 磁力资源标题：主标题 + 副标题（中/英互补展示）
@immutable
class TorrentTitleLines {
  final String primary;
  final String? secondary;

  const TorrentTitleLines({required this.primary, this.secondary});
}

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');
final RegExp _latinWord = RegExp(r'[A-Za-z]{2,}');

bool _hasCjk(String s) => _cjk.hasMatch(s);

bool _mostlyLatin(String s) {
  final letters = RegExp(r'[A-Za-z]').allMatches(s).length;
  return letters >= 3 && !_hasCjk(s);
}

/// 磁力资源标题经 [splitTorrentDisplayTitle] 后的主行是否主要为拉丁字母（无汉字）。
///
/// 用于详情页：此类资源旁展示 CMS 中文片名标签，便于辨认。
bool torrentTitlePrimaryIsMostlyLatin(String raw) {
  final lines = splitTorrentDisplayTitle(raw);
  final p = lines.primary.trim();
  if (p.isEmpty) return false;
  return _mostlyLatin(p);
}

/// 从常见命名里拆出中英文两行（如 "中文名 / English"、"英文名.1080p"）
TorrentTitleLines splitTorrentDisplayTitle(String raw) {
  final s = raw.trim();
  if (s.isEmpty) {
    return const TorrentTitleLines(primary: '');
  }

  for (final sep in [' / ', '／', ' | ', ' — ', ' – ', ' - ']) {
    final parts = s.split(sep);
    if (parts.length == 2) {
      final a = parts[0].trim();
      final b = parts[1].trim();
      if (a.isNotEmpty && b.isNotEmpty) {
        if (_hasCjk(a) && _mostlyLatin(b)) {
          return TorrentTitleLines(primary: a, secondary: b);
        }
        if (_hasCjk(b) && _mostlyLatin(a)) {
          return TorrentTitleLines(primary: b, secondary: a);
        }
        if (_hasCjk(a) != _hasCjk(b)) {
          final zh = _hasCjk(a) ? a : b;
          final en = _hasCjk(a) ? b : a;
          return TorrentTitleLines(primary: zh, secondary: en);
        }
      }
    }
  }

  final paren = RegExp(r'^(.+?)[（(]([^)）]+)[)）]\s*$').firstMatch(s);
  if (paren != null) {
    final a = paren.group(1)!.trim();
    final b = paren.group(2)!.trim();
    if (a.isNotEmpty && b.isNotEmpty) {
      if (_hasCjk(a) && _mostlyLatin(b)) {
        return TorrentTitleLines(primary: a, secondary: b);
      }
      if (_mostlyLatin(a) && _hasCjk(b)) {
        return TorrentTitleLines(primary: b, secondary: a);
      }
    }
  }

  final dots = s.split('.');
  if (dots.length >= 2) {
    final head = dots.first.trim();
    if (_mostlyLatin(head) && _latinWord.hasMatch(head)) {
      final rest = dots.sublist(1).join('.');
      final zhPick = RegExp(r'[\u4e00-\u9fff]{2,}').firstMatch(rest);
      if (zhPick != null) {
        return TorrentTitleLines(primary: zhPick.group(0)!, secondary: head);
      }
    }
  }

  if (_mostlyLatin(s)) {
    final zh = RegExp(r'[\u4e00-\u9fff]{2,}').firstMatch(s);
    if (zh != null) {
      return TorrentTitleLines(primary: zh.group(0)!, secondary: s);
    }
    return TorrentTitleLines(primary: s);
  }

  if (_hasCjk(s)) {
    final enMatches = _latinWord.allMatches(s).map((m) => m.group(0)!).toList();
    if (enMatches.isNotEmpty) {
      final sub = enMatches.join(' ');
      if (sub.length >= 3) {
        return TorrentTitleLines(primary: s, secondary: sub);
      }
    }
  }

  return TorrentTitleLines(primary: s);
}
