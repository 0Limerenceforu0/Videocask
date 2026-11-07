import '../models/movie.dart';
import '../services/torrent_player_models.dart';

/// 磁力多集资源：从文件列表解析选集，并用 [fileUrlPrefix] 标记文件索引。
class MagnetEpisodeParser {
  MagnetEpisodeParser._();

  static const fileUrlPrefix = 'magnet-file://';

  static bool isMagnetFileUrl(String url) => url.startsWith(fileUrlPrefix);

  static int? fileIndexFromUrl(String url) {
    if (!isMagnetFileUrl(url)) return null;
    return int.tryParse(url.substring(fileUrlPrefix.length));
  }

  static String fileUrl(int fileIndex) => '$fileUrlPrefix$fileIndex';

  static const _videoExts = [
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.wmv',
    '.flv',
    '.webm',
    '.m4v',
    '.ts',
  ];

  static const _junkNameTokens = [
    'sample',
    'trailer',
    'preview',
    'proof',
    'screens',
    'subtitle',
    'subs',
  ];

  static List<TorrentFileItem> videoFiles(List<TorrentFileItem> files) {
    return files.where((f) => _isVideoFile(f.name)).toList();
  }

  /// 多视频文件时生成选集线路；单文件返回 null（按单片播放）。
  static PlayRoute? buildPlayRoute(
    List<TorrentFileItem> files, {
    required String routeName,
  }) {
    final videos = videoFiles(files);
    if (videos.length <= 1) return null;

    final parsed = videos.map(_ParsedTorrentEpisode.fromFile).toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));

    final episodes = parsed
        .asMap()
        .entries
        .map(
          (e) => Episode(
            index: e.key,
            name: e.value.label,
            url: fileUrl(e.value.file.index),
          ),
        )
        .toList();

    return PlayRoute(name: routeName, episodes: episodes);
  }

  /// 起播/续播时选择文件索引。
  static int? pickFileIndex(
    List<TorrentFileItem> files, {
    int episodeIndex = 0,
    String? torrentTitle,
    int? preferredFileIndex,
  }) {
    if (preferredFileIndex != null) {
      return preferredFileIndex;
    }

    final route = buildPlayRoute(files, routeName: '');
    if (route != null &&
        episodeIndex >= 0 &&
        episodeIndex < route.episodes.length) {
      return fileIndexFromUrl(route.episodes[episodeIndex].url);
    }

    if (torrentTitle != null && torrentTitle.trim().isNotEmpty) {
      final fromTitle = _fileIndexMatchingTitle(files, torrentTitle);
      if (fromTitle != null) return fromTitle;
    }

    return _pickLargestVideo(files);
  }

  static int? _fileIndexMatchingTitle(
    List<TorrentFileItem> files,
    String torrentTitle,
  ) {
    final title = torrentTitle.toLowerCase();
    final sn = RegExp(r'\bs(\d{1,2})e(\d{1,2})\b', caseSensitive: false)
        .firstMatch(title);
    if (sn != null) {
      final season = int.tryParse(sn.group(1) ?? '') ?? -1;
      final episode = int.tryParse(sn.group(2) ?? '') ?? -1;
      if (season > 0 && episode > 0) {
        final pattern = RegExp(
          r'\bs0*' +
              season.toString() +
              r'[\s._-]?e0*' +
              episode.toString() +
              r'\b',
          caseSensitive: false,
        );
        for (final f in videoFiles(files)) {
          if (pattern.hasMatch(f.name.toLowerCase())) return f.index;
        }
      }
    }

    final cn = RegExp(r'第\s*0*(\d{1,3})\s*集').firstMatch(torrentTitle);
    if (cn != null) {
      final ep = int.tryParse(cn.group(1) ?? '') ?? -1;
      if (ep > 0) {
        final pattern = RegExp(r'第\s*0*$ep\s*集');
        for (final f in videoFiles(files)) {
          if (pattern.hasMatch(f.name)) return f.index;
        }
      }
    }
    return null;
  }

  static int? _pickLargestVideo(List<TorrentFileItem> files) {
    TorrentFileItem? best;
    var bestScore = -1.0;
    for (final f in files) {
      final s = _videoScore(f);
      if (s < 0) continue;
      if (best == null || s > bestScore) {
        best = f;
        bestScore = s;
      }
    }
    return best?.index;
  }

  static double _videoScore(TorrentFileItem f) {
    final lower = f.name.toLowerCase();
    if (!_isVideoFile(lower)) return -1;
    var s = f.size.toDouble();
    for (final token in _junkNameTokens) {
      if (lower.contains(token)) s *= 0.001;
    }
    return s;
  }

  static bool _isVideoFile(String name) {
    final lower = name.toLowerCase();
    return _videoExts.any(lower.endsWith);
  }
}

class _ParsedTorrentEpisode {
  _ParsedTorrentEpisode({
    required this.file,
    required this.label,
    required this.sortKey,
  });

  final TorrentFileItem file;
  final String label;
  final int sortKey;

  factory _ParsedTorrentEpisode.fromFile(TorrentFileItem file) {
    final base = _basename(file.name);
    final sn =
        RegExp(r'\b[Ss](\d{1,2})[\s._-]?[Ee](\d{1,2})\b').firstMatch(base);
    if (sn != null) {
      final season = int.tryParse(sn.group(1) ?? '') ?? 0;
      final episode = int.tryParse(sn.group(2) ?? '') ?? 0;
      final label =
          'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
      return _ParsedTorrentEpisode(
        file: file,
        label: label,
        sortKey: season * 10000 + episode,
      );
    }

    final cn = RegExp(r'第\s*0*(\d{1,3})\s*集').firstMatch(base);
    if (cn != null) {
      final ep = int.tryParse(cn.group(1) ?? '') ?? 0;
      return _ParsedTorrentEpisode(
        file: file,
        label: '第$ep集',
        sortKey: ep,
      );
    }

    return _ParsedTorrentEpisode(
      file: file,
      label: _shorten(base),
      sortKey: file.index + 100000,
    );
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final i = normalized.lastIndexOf('/');
    return i >= 0 ? normalized.substring(i + 1) : normalized;
  }

  static String _shorten(String name) {
    const maxLen = 28;
    if (name.length <= maxLen) return name;
    return '${name.substring(0, maxLen - 1)}…';
  }
}
