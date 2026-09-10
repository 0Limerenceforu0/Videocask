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
}
