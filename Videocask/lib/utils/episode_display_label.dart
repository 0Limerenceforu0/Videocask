import '../models/movie.dart';

/// 从 CMS 选集名称提取短主标题（期/集/序号），便于网格按钮识别。
class EpisodeDisplayLabel {
  const EpisodeDisplayLabel({
    required this.primary,
    required this.full,
    this.secondary,
  });

  /// 格子/列表主标题（尽量短）。
  final String primary;

  /// 完整原始名称（Tooltip、Semantics）。
  final String full;

  /// 可选副标题（长名称时缩略展示）。
  final String? secondary;

  static EpisodeDisplayLabel forEpisode({
    required String name,
    required int index,
    int secondaryMaxLength = 18,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      final n = '${index + 1}';
      return EpisodeDisplayLabel(primary: n, full: n);
    }

    final compact = _extractCompactLabel(trimmed);
    if (compact != null) {
      final showSecondary =
          trimmed != compact && trimmed.length > compact.length + 2;
      return EpisodeDisplayLabel(
        primary: compact,
        full: trimmed,
        secondary: showSecondary ? _shorten(trimmed, secondaryMaxLength) : null,
      );
    }

    if (trimmed.length <= 8) {
      return EpisodeDisplayLabel(primary: trimmed, full: trimmed);
    }

    final n = '${index + 1}';
    return EpisodeDisplayLabel(
      primary: n,
      full: trimmed,
      secondary: _shorten(trimmed, secondaryMaxLength),
    );
  }

  static String? _extractCompactLabel(String name) {
    final qi = RegExp(r'第\s*0*(\d{1,4})\s*期').firstMatch(name);
    if (qi != null) {
      return '第${qi.group(1)}期';
    }

    final ji = RegExp(r'第\s*0*(\d{1,4})\s*集').firstMatch(name);
    if (ji != null) {
      return '第${ji.group(1)}集';
    }

    final seasonEpisode = RegExp(
      r'[Ss](\d{1,2})[\s._-]?[Ee](\d{1,2})',
    ).firstMatch(name);
    if (seasonEpisode != null) {
      final s = seasonEpisode.group(1)!.padLeft(2, '0');
      final e = seasonEpisode.group(2)!.padLeft(2, '0');
      return 'S$s E$e';
    }

    final ep = RegExp(r'\b[Ee][Pp]?\s*0*(\d{1,4})\b').firstMatch(name);
    if (ep != null) {
      return 'E${ep.group(1)}';
    }

    final date = RegExp(
      r'(20\d{2})[-./年]?(0?[1-9]|1[0-2])[-./月]?(0?[1-9]|[12]\d|3[01])',
    ).firstMatch(name);
    if (date != null) {
      final month = date.group(2)!.padLeft(2, '0');
      final day = date.group(3)!.padLeft(2, '0');
      return '${date.group(1)}-$month-$day';
    }

    final leading = RegExp(r'^(\d{1,4})[\s._\-、.]').firstMatch(name);
    if (leading != null) {
      return leading.group(1)!;
    }

    return null;
  }

  static String _shorten(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}…';
  }

  /// 名称较长、网格难以完整展示时，改用一行一集的列表布局。
  static bool episodesPreferListLayout(List<Episode> episodes) {
    for (var i = 0; i < episodes.length; i++) {
      final label = forEpisode(name: episodes[i].name, index: i);
      if (label.secondary != null) return true;
      if (label.full.length > 10 && label.primary != label.full) {
        return true;
      }
    }
    return false;
  }
}
