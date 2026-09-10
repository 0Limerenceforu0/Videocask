import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/cache_item.dart';
import 'package:movie_app/services/cache_item_store.dart';
import 'package:movie_app/services/cache_service.dart';
import 'package:movie_app/services/m3u8_playlist_resolver.dart';

import '../helpers/mock_download_http_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CacheService.connectivityAllowsDownload', () {
    test('blocks mobile data when onlyWifi', () {
      expect(
        CacheService.connectivityAllowsDownload(
          result: ConnectivityResult.mobile,
          onlyWifi: true,
        ),
        isFalse,
      );
      expect(
        CacheService.connectivityAllowsDownload(
          result: ConnectivityResult.wifi,
          onlyWifi: true,
        ),
        isTrue,
      );
    });

    test('allows any network when onlyWifi is false', () {
      expect(
        CacheService.connectivityAllowsDownload(
          result: ConnectivityResult.mobile,
          onlyWifi: false,
        ),
        isTrue,
      );
    });

    test('blocks when offline', () {
      expect(
        CacheService.connectivityAllowsDownload(
          result: ConnectivityResult.none,
          onlyWifi: false,
        ),
        isFalse,
      );
    });
  });

  group('CacheService.startDownload automation', () {
    late Directory tempDir;
    late InMemoryCacheItemStore store;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cache_dl_test_');
      store = InMemoryCacheItemStore();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    CacheService buildService({
      Dio? dio,
      Future<ConnectivityResult> Function()? connectivityChecker,
      Future<M3u8MediaPlaylist> Function(String url, {String? referer})?
          m3u8Override,
    }) {
      return CacheService.test(
        store: store,
        cacheDirectory: tempDir.path,
        downloadDio: dio,
        connectivityChecker:
            connectivityChecker ?? () async => ConnectivityResult.wifi,
        m3u8ResolveOverride: m3u8Override,
      );
    }

    Future<CacheItem> seedTask({
      required String id,
      required String url,
      String status = 'waiting',
      String pageUrl = '',
      int downloadedSize = 0,
    }) async {
      final item = CacheItem(
        id: id,
        movieId: 'm1',
        movieName: 'Movie',
        url: url,
        pageUrl: pageUrl,
        localPath: '${tempDir.path}/$id.mp4',
        status: status,
        downloadedSize: downloadedSize,
      );
      await store.saveCacheItem(item);
      return item;
    }

    test('returns false when concurrent slots are full', () async {
      final service = buildService();
      await seedTask(id: 'c1', url: 'https://cdn.example.com/a.mp4');
      for (var i = 0; i < CacheService.maxConcurrentDownloads; i++) {
        service.debugOccupyDownloadSlot('slot_$i');
      }
      final ok = await service.startDownload('c1');
      expect(ok, isFalse);
      expect(store.item('c1')!.status, 'waiting');
    });

    test('returns false on mobile data when onlyWifi enabled', () async {
      final service = buildService(
        connectivityChecker: () async => ConnectivityResult.mobile,
      );
      await service.setOnlyWifi(true);
      await seedTask(id: 'c1', url: 'https://cdn.example.com/a.mp4');
      final ok = await service.startDownload('c1');
      expect(ok, isFalse);
      expect(store.item('c1')!.status, 'waiting');
    });

    test('marks failed when url is empty', () async {
      final service = buildService();
      await seedTask(id: 'c1', url: '');
      final ok = await service.startDownload('c1');
      expect(ok, isFalse);
      expect(store.item('c1')!.status, 'failed');
    });

    test('marks failed when url is not cacheable', () async {
      final service = buildService();
      await seedTask(id: 'c1', url: 'magnet:?xt=urn:btih:abc');
      final ok = await service.startDownload('c1');
      expect(ok, isFalse);
      expect(store.item('c1')!.status, 'failed');
    });

    test('returns false when task id missing', () async {
      final service = buildService();
      expect(await service.startDownload('missing'), isFalse);
    });

    test('direct download completes when file is large enough', () async {
      final adapter = MockDownloadHttpAdapter(
        defaultBytes: bytesOfLength(CacheService.minValidVideoBytes + 1024),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final service = buildService(dio: dio);
      await seedTask(
        id: 'c1',
        url: 'https://cdn.example.com/movie.mp4',
        pageUrl: 'https://play.example.com/x',
      );

      final ok = await service.startDownload('c1');
      expect(ok, isTrue);
      expect(store.item('c1')!.status, 'completed');
      expect(File(store.item('c1')!.localPath).existsSync(), isTrue);
      expect(adapter.fetchCount, greaterThan(0));
    });

    test('direct download fails when response is too small', () async {
      final adapter = MockDownloadHttpAdapter(
        defaultBytes: bytesOfLength(1024),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final service = buildService(dio: dio);
      await seedTask(id: 'c1', url: 'https://cdn.example.com/tiny.mp4');

      final ok = await service.startDownload('c1');
      expect(ok, isFalse);
      expect(store.item('c1')!.status, 'failed');
    });

    test('direct download fails on http error', () async {
      final adapter = MockDownloadHttpAdapter(
        defaultBytes: bytesOfLength(CacheService.minValidVideoBytes + 1),
        failUrls: {'forbidden'},
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final service = buildService(dio: dio);
      await seedTask(id: 'c1', url: 'https://cdn.example.com/forbidden.mp4');

      final ok = await service.startDownload('c1');
      expect(ok, isFalse);
      expect(store.item('c1')!.status, 'failed');
    });

    test('pause during direct download sets paused', () async {
      final adapter = _StallDownloadAdapter(
        payload: bytesOfLength(CacheService.minValidVideoBytes + 1),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final service = buildService(dio: dio);
      await seedTask(id: 'c1', url: 'https://cdn.example.com/slow.mp4');

      final future = service.startDownload('c1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      service.pauseDownload('c1');
      final ok = await future;
      expect(ok, isFalse);
      expect(store.item('c1')!.status, 'paused');
    });

    test('m3u8 download fails when playlist has no segments', () async {
      final service = buildService(
        m3u8Override: (_, {referer}) async => const M3u8MediaPlaylist(
          playlistUrl: 'https://cdn.example.com/index.m3u8',
          content: '#EXTM3U',
          segmentUrls: [],
        ),
      );
      await seedTask(id: 'c1', url: 'https://cdn.example.com/index.m3u8');

      final ok = await service.startDownload('c1');
      expect(ok, isFalse);
      expect(store.item('c1')!.status, 'failed');
    });

    test('m3u8 download merges segments into completed file', () async {
      const segSize = CacheService.minValidVideoBytes ~/ 2 + 1024;
      final adapter = MockDownloadHttpAdapter(
        urlBytes: {
          'seg0.ts': bytesOfLength(segSize),
          'seg1.ts': bytesOfLength(segSize),
        },
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final service = buildService(
        dio: dio,
        m3u8Override: (_, {referer}) async => M3u8MediaPlaylist(
          playlistUrl: 'https://cdn.example.com/v.m3u8',
          content: '#EXTM3U',
          segmentUrls: const [
            'https://cdn.example.com/seg0.ts',
            'https://cdn.example.com/seg1.ts',
          ],
        ),
      );
      await seedTask(id: 'c1', url: 'https://cdn.example.com/index.m3u8');

      final ok = await service.startDownload('c1');
      expect(ok, isTrue);
      expect(store.item('c1')!.status, 'completed');
      expect(
        File(store.item('c1')!.localPath).lengthSync(),
        greaterThanOrEqualTo(CacheService.minValidVideoBytes),
      );
      expect(adapter.fetchedUrls.length, 2);
    });

    test('resume direct download sends Range header', () async {
      String? rangeHeader;
      final adapter = _RangeCapturingAdapter(
        onFetch: (options) => rangeHeader = options.headers['Range'] as String?,
        payload: bytesOfLength(CacheService.minValidVideoBytes + 4096),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final service = buildService(dio: dio);
      await seedTask(
        id: 'c1',
        url: 'https://cdn.example.com/resume.mp4',
        status: 'paused',
        downloadedSize: 65536,
      );

      await service.resumeDownload('c1');
      expect(rangeHeader, 'bytes=65536-');
      expect(store.item('c1')!.status, 'completed');
    });

    test('resume m3u8 skips existing temp segments', () async {
      const segSize = CacheService.minValidVideoBytes ~/ 2 + 1024;
      final adapter = MockDownloadHttpAdapter(
        urlBytes: {
          'seg1.ts': bytesOfLength(segSize),
        },
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final service = buildService(
        dio: dio,
        m3u8Override: (_, {referer}) async => M3u8MediaPlaylist(
          playlistUrl: 'https://cdn.example.com/v.m3u8',
          content: '#EXTM3U',
          segmentUrls: const [
            'https://cdn.example.com/seg0.ts',
            'https://cdn.example.com/seg1.ts',
          ],
        ),
      );
      final item = await seedTask(
        id: 'c1',
        url: 'https://cdn.example.com/index.m3u8',
        status: 'paused',
      );
      final tempDir = Directory('${item.localPath}_temp');
      await tempDir.create(recursive: true);
      await File('${tempDir.path}/segment_0.ts').writeAsBytes(
        bytesOfLength(segSize),
      );

      final ok = await service.resumeDownload('c1');
      expect(ok, isTrue);
      expect(store.item('c1')!.status, 'completed');
      expect(adapter.fetchedUrls.length, 1);
      expect(adapter.fetchedUrls.single, contains('seg1.ts'));
    });

    test('scheduleWaitingDownloads respects max concurrency', () async {
      final adapter = _StallDownloadAdapter(
        payload: bytesOfLength(CacheService.minValidVideoBytes + 1),
        stallMs: 500,
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final service = buildService(dio: dio);

      for (var i = 0; i < 4; i++) {
        await seedTask(
          id: 'c$i',
          url: 'https://cdn.example.com/$i.mp4',
        );
      }

      unawaited(service.scheduleWaitingDownloads());
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final items = store.getAllCacheItems();
      final downloading = items.where((i) => i.isDownloading).length;
      final waiting = items.where((i) => i.isWaiting).length;

      expect(downloading, CacheService.maxConcurrentDownloads);
      expect(waiting, 1);
    });
  });
}

/// 下载过程中延迟，便于触发 pause / 并发测试。
class _StallDownloadAdapter implements HttpClientAdapter {
  _StallDownloadAdapter({
    required this.payload,
    this.stallMs = 120,
  });

  final List<int> payload;
  final int stallMs;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await Future<void>.delayed(Duration(milliseconds: stallMs));
    return ResponseBody.fromBytes(
      Uint8List.fromList(payload),
      200,
      headers: {
        Headers.contentLengthHeader: [payload.length.toString()],
      },
    );
  }
}

class _RangeCapturingAdapter implements HttpClientAdapter {
  _RangeCapturingAdapter({
    required this.onFetch,
    required this.payload,
  });

  final void Function(RequestOptions options) onFetch;
  final List<int> payload;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onFetch(options);
    return ResponseBody.fromBytes(
      Uint8List.fromList(payload),
      200,
      headers: {
        Headers.contentLengthHeader: [payload.length.toString()],
      },
    );
  }
}
