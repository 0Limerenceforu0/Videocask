import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/torrent_info.dart';

/// 识别并排除「影视解说 / 拉片 / 剧情讲解」等非正片资源。
class CommentaryContentFilter {
  CommentaryContentFilter._();

  /// 只要出现「解说」二字就判定为非正片（2026-10-28 收紧）。
  ///
  /// 原来逐个枚举 `电影解说 / 影视解说 / 解说版 / 解说合集 …`，实测采集站
  /// 的命名太杂（`功夫解说全集`、`XX 第1集解说`、`[解说]`），枚举永远漏。
  /// 正常影视片名里几乎不会出现「解说」，宁可多杀。
  static final RegExp _pattern = RegExp(r'解说', caseSensitive: false);

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
