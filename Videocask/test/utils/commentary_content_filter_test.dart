import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/torrent_info.dart';
import 'package:movie_app/utils/commentary_content_filter.dart';

void main() {
  group('CommentaryContentFilter', () {
    test('detects common commentary titles', () {
      expect(CommentaryContentFilter.matchesText('流浪地球 影视解说'), isTrue);
      expect(CommentaryContentFilter.matchesText('【解说】星际穿越'), isTrue);
      expect(CommentaryContentFilter.matchesText('10分钟看完盗梦空间'), isTrue);
    });

    test('keeps regular movie titles', () {
      expect(CommentaryContentFilter.matchesText('流浪地球2'), isFalse);
      expect(CommentaryContentFilter.matchesText('Inception 2010'), isFalse);
    });

    test('filters movie and torrent models', () {
      expect(
        CommentaryContentFilter.isMovie(
          Movie(id: '1', name: '某某电影解说版'),
        ),
        isTrue,
      );
      expect(
        CommentaryContentFilter.isTorrent(
          TorrentInfo(
            name: 'Interstellar.2014.1080p',
            size: 0,
            seeders: 1,
            leechers: 0,
            magnetUri: 'magnet:?xt=urn:btih:'
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            source: 'test',
          ),
        ),
        isFalse,
      );
    });
  });

  // 2026-10-28 用户要求：搜索结果里不要出现「[电影解说]」。
  group('CommentaryContentFilter（解说判据收紧）', () {
    test('方括号标记', () {
      expect(CommentaryContentFilter.matchesText('功夫[电影解说]'), isTrue);
      expect(CommentaryContentFilter.matchesText('美人鱼【电影解说】'), isTrue);
    });

    test('不带方括号的变体也要拦（逐个枚举漏的就是这类）', () {
      expect(CommentaryContentFilter.matchesText('功夫解说全集'), isTrue);
      expect(CommentaryContentFilter.matchesText('XX 第1集解说'), isTrue);
      expect(CommentaryContentFilter.matchesText('解说：大话西游'), isTrue);
      expect(CommentaryContentFilter.matchesText('影视解说-少林足球'), isTrue);
    });

    test('正常片名不受影响', () {
      expect(CommentaryContentFilter.matchesText('功夫'), isFalse);
      expect(CommentaryContentFilter.matchesText('九品芝麻官'), isFalse);
      expect(CommentaryContentFilter.matchesText('长江七号'), isFalse);
      expect(CommentaryContentFilter.matchesText(''), isFalse);
      expect(CommentaryContentFilter.matchesText(null), isFalse);
    });

    test('标记藏在别名 / 备注里同样拦（源站常放备注）', () {
      expect(
        CommentaryContentFilter.isMovie(
          Movie(id: '1', name: '功夫', alias: '功夫[电影解说]'),
        ),
        isTrue,
      );
      expect(
        CommentaryContentFilter.isMovie(
          Movie(id: '2', name: '功夫', updateStatus: '更新至02集[电影解说]'),
        ),
        isTrue,
      );
      expect(CommentaryContentFilter.isMovie(Movie(id: '3', name: '功夫')), isFalse);
    });

    test('磁力标题', () {
      expect(
        CommentaryContentFilter.isTorrent(
          TorrentInfo(
            name: '功夫.2004[电影解说].1080p',
            size: 0,
            seeders: 1,
            leechers: 0,
            magnetUri: 'magnet:?xt=urn:btih:'
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            source: 'test',
          ),
        ),
        isTrue,
      );
    });
  });
}
