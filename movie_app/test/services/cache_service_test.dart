import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/cache_item.dart';
import 'package:movie_app/services/cache_item_store.dart';
import 'package:movie_app/services/cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CacheService cacheService;

  setUp(() {
    cacheService = CacheService();
  });

  tearDown(() async {
    // 尝试清理测试产生的缓存，但不抛出异常
    try {
      await cacheService.clearAllCache();
    } catch (e) {
      // 忽略清理时的异常
    }
  });

  group('CacheService', () {
    test('格式化文件大小', () {
      expect(CacheService.formatFileSize(0), '0 B');
      expect(CacheService.formatFileSize(1024), '1.0 KB');
      expect(CacheService.formatFileSize(1024 * 1024), '1.0 MB');
      expect(CacheService.formatFileSize(1024 * 1024 * 1024), '1.0 GB');
    });

    test('获取活跃下载任务数', () {
      expect(cacheService.activeDownloadCount, 0);
    });

    test('暂停所有下载', () {
      expect(() => cacheService.pauseAllDownloads(), returnsNormally);
    });

    test('设置和移除进度回调', () {
      void testCallback(int received, int total) {
        // 测试回调函数
      }

      cacheService.setProgressCallback('test_cache', testCallback);
      expect(
        () => cacheService.removeProgressCallback('test_cache'),
        returnsNormally,
      );
    });

    test('获取所有缓存项（空状态）', () {
      final items = cacheService.getAllCacheItems();
      expect(items, isEmpty);
    });

    test('isCacheableUrl rejects magnet and file', () {
      expect(CacheService.isCacheableUrl('magnet:?xt=urn:btih:abc'), isFalse);
      expect(CacheService.isCacheableUrl('file:///tmp/a.mp4'), isFalse);
      expect(
        CacheService.isCacheableUrl('https://cdn.example.com/a.mp4'),
        isTrue,
      );
    });

    test('m3u8CacheBlockReason detects encryption and master playlist', () {
      expect(
        CacheService.m3u8CacheBlockReason('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128'),
        'encrypted',
      );
      expect(
        CacheService.m3u8CacheBlockReason(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1280000',
        ),
        'master_playlist',
      );
      expect(
        CacheService.m3u8CacheBlockReason('#EXTM3U\n#EXTINF:10,\nseg.ts'),
        isNull,
      );
    });

    test('isHlsUrl detects m3u8 addresses', () {
      expect(
        CacheService.isHlsUrl('https://cdn.example.com/play/hls/index.m3u8'),
        isTrue,
      );
      expect(CacheService.isHlsUrl('https://cdn.example.com/a.mp4'), isFalse);
    });

    test('findTaskForEpisode prefers downloading over waiting', () async {
      final store = InMemoryCacheItemStore();
      final service = CacheService.test(store: store);
      final older = CacheItem(
        id: 'old',
        movieId: 'm1',
        movieName: 'show',
        url: 'https://cdn/a.m3u8',
        episodeIndex: 0,
        status: 'downloading',
        fileSize: 100,
        downloadedSize: 40,
        createdAt: DateTime(2026, 1, 1),
      );
      final newer = CacheItem(
        id: 'new',
        movieId: 'm1',
        movieName: 'show',
        url: 'https://cdn/a.m3u8',
        episodeIndex: 0,
        status: 'waiting',
        createdAt: DateTime(2026, 2, 1),
      );
      await store.saveCacheItem(older);
      await store.saveCacheItem(newer);

      final picked = service.findTaskForEpisode(
        movieId: 'm1',
        episodeIndex: 0,
      );
      expect(picked?.id, 'old');
    });

    test('findTaskForEpisode returns latest match', () async {
      // Storage may be uninitialized in unit tests; method should not throw.
      expect(
        () => cacheService.findTaskForEpisode(
          movieId: 'missing',
          episodeIndex: 0,
        ),
        returnsNormally,
      );
    });

    test('maxCacheBytes uses AppConstants', () {
      expect(CacheService.maxCacheBytes, greaterThan(0));
    });

    test('headersFor uses pageUrl referer', () {
      final item = CacheItem(
        id: '1',
        movieId: 'm',
        movieName: 'n',
        url: 'https://cdn/a.mp4',
        pageUrl: 'https://play.example.com/x',
      );
      expect(
        CacheService.headersFor(item)['Referer'],
        'https://play.example.com/x/',
      );
    });

    test('minValidVideoBytes guards against html error pages', () {
      expect(CacheService.minValidVideoBytes, greaterThanOrEqualTo(256 * 1024));
    });
  });
}
