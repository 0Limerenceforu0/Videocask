import 'package:flutter_test/flutter_test.dart';
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
  });
}
