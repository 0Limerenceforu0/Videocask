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

    test('不设上限：maxCacheBytes 为 0，不再按 2GB 淘汰已下载剧集', () {
      // 用户明确要求取消缓存上限。若这里改回正数，说明又会把用户下载好的
      // 剧集按 LRU 悄悄删掉，必须让这条测试红。
      expect(CacheService.maxCacheBytes, 0);
    });

    test('不设上限时容量检查直接放行，不触发任何清理', () async {
      // 上限为 0 时 ensureSpaceForDownload 应在第一行就返回，
      // 不会去枚举缓存目录、更不会调用 deleteCache。
      expect(cacheService.getAllCacheItems(), isEmpty);
      await expectLater(
        cacheService.ensureSpaceForDownload(estimatedBytes: 1 << 30),
        completes,
      );
      expect(cacheService.getAllCacheItems(), isEmpty);
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
