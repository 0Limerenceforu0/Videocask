import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/cache_item.dart';
import 'package:movie_app/services/cache_service.dart';
import 'package:movie_app/services/media_fetch_headers.dart';

void main() {
  group('MediaFetchHeaders', () {
    test('forUrl uses media host when no referer', () {
      final headers = MediaFetchHeaders.forUrl('https://cdn.example.com/a.ts');
      expect(headers['Referer'], 'https://cdn.example.com/');
      expect(headers['Origin'], 'https://cdn.example.com');
      expect(headers['User-Agent'], isNotEmpty);
    });

    test('forUrl uses play page referer when provided', () {
      final headers = MediaFetchHeaders.forUrl(
        'https://cdn.example.com/a.ts',
        referer: 'https://v.example.com/play/x',
      );
      expect(headers['Referer'], 'https://v.example.com/play/x/');
      expect(headers['Origin'], 'https://v.example.com');
    });
  });

  group('CacheService.headersFor', () {
    test('prefers cache item pageUrl over media url origin', () {
      final item = CacheItem(
        id: '1',
        movieId: 'm',
        movieName: 'n',
        url: 'https://cdn.example.com/movie.ts',
        pageUrl: 'https://site.example.com/play/1',
      );
      final headers = CacheService.headersFor(item);
      expect(headers['Referer'], 'https://site.example.com/play/1/');
    });

    test('override url keeps page referer', () {
      final item = CacheItem(
        id: '1',
        movieId: 'm',
        movieName: 'n',
        url: 'https://cdn.example.com/index.m3u8',
        pageUrl: 'https://site.example.com/play/1',
      );
      final headers = CacheService.headersFor(
        item,
        url: 'https://cdn.example.com/key',
      );
      expect(headers['Referer'], 'https://site.example.com/play/1/');
    });
  });
}
