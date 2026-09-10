import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/torrent_info.dart';

/// 识别并排除「影视解说 / 拉片 / 剧情讲解」等非正片资源。
class CommentaryContentFilter {
  CommentaryContentFilter._();

  static final RegExp _pattern = RegExp(
    r'影视解说|电影解说|剧集解说|动漫解说|综艺解说|纪录片解说|'
    r'解说版|解说合集|'
    r'[【\[\(（]解说[】\]\)）]|'
    r'解说[\s\-_·:|]|^解说',
    caseSensitive: false,
  );

  static final RegExp _extraPattern = RegExp(
    r'吐槽解说|拉片解说|拆电影|几分钟看完|分钟看完|x分钟看完|'
    r'剧情讲解|讲电影|唠电影|盘点解说|'
    r'recut|commentary\s*cut|movie\s*recap|film\s*recap',
    caseSensitive: false,
  );

  /// 片名、磁力标题等单行文本是否属于解说类资源。
  static bool matchesText(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    final t = text.trim();
    return _pattern.hasMatch(t) || _extraPattern.hasMatch(t);
  }

  static bool isMovie(Movie movie) {
    if (matchesText(movie.name)) return true;
    if (matchesText(movie.alias)) return true;
    if (matchesText(movie.updateStatus)) return true;
    for (final g in movie.genres) {
      if (matchesText(g)) return true;
    }
    return false;
  }

  static bool isTorrent(TorrentInfo torrent) => matchesText(torrent.name);
}
