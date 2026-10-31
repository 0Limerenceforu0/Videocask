import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../config/constants.dart';
import '../models/cache_item.dart';
import '../utils/app_data_paths.dart';
import 'cache_item_store.dart';
import 'hls_segment_crypto.dart';
import 'media_fetch_headers.dart';
import 'm3u8_playlist_resolver.dart';
import 'network/dio_factory.dart';

/// 缓存服务
class CacheService {
  CacheService._({
    CacheItemStore? store,
    M3u8PlaylistResolver? m3u8Resolver,
    Dio? downloadDio,
    Future<List<ConnectivityResult>> Function()? connectivityChecker,
    String? cacheDirectory,
    Future<M3u8MediaPlaylist> Function(String url, {String? referer})?
        m3u8ResolveOverride,
  })  : _store = store ?? StorageCacheItemStore(),
        _m3u8Resolver = m3u8Resolver ?? M3u8PlaylistResolver(),
        _downloadDio = downloadDio,
        _connectivityChecker =
            connectivityChecker ?? Connectivity().checkConnectivity,
        _cacheDirOverride = cacheDirectory,
        _m3u8ResolveOverride = m3u8ResolveOverride;

  static final CacheService _instance = CacheService._();
  factory CacheService() => _instance;

  /// 单测专用：独立实例 + 可注入存储 / 网络 / 目录。
  @visibleForTesting
  factory CacheService.test({
    CacheItemStore? store,
    M3u8PlaylistResolver? m3u8Resolver,
    Dio? downloadDio,
    Future<List<ConnectivityResult>> Function()? connectivityChecker,
    String? cacheDirectory,
    Future<M3u8MediaPlaylist> Function(String url, {String? referer})?
        m3u8ResolveOverride,
  }) {
    return CacheService._(
      store: store,
      m3u8Resolver: m3u8Resolver,
      downloadDio: downloadDio,
      connectivityChecker: connectivityChecker,
      cacheDirectory: cacheDirectory,
      m3u8ResolveOverride: m3u8ResolveOverride,
    );
  }

  final CacheItemStore _store;
  Dio? _downloadDio;
  final M3u8PlaylistResolver _m3u8Resolver;
  final Future<List<ConnectivityResult>> Function() _connectivityChecker;
  final String? _cacheDirOverride;
  final Future<M3u8MediaPlaylist> Function(String url, {String? referer})?
      _m3u8ResolveOverride;

  /// 过小的「视频」多半是 HTML 错误页，视为下载失败。
  static const int minValidVideoBytes = 256 * 1024;

  /// 缓存下载 HTTP 头（优先使用 [CacheItem.pageUrl] 作 Referer）。
  static Map<String, String> headersFor(CacheItem item, {String? url}) {
    final target = url ?? item.url;
    final page = item.pageUrl.trim();
    if (page.isNotEmpty) {
      return MediaFetchHeaders.forUrl(target, referer: page);
    }
    return MediaFetchHeaders.forUrl(target);
  }

  static bool isHlsUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('/hls/');
  }

  /// 初始化Dio实例（m3u8 解析等短请求仍可用独立 Dio）
  Future<Dio> _getDownloadDio() async {
    _downloadDio ??= await DioFactory.plainText(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
    );
    return _downloadDio!;
  }

  Map<String, String> _fetchHeadersForItem(CacheItem item, {String? url}) {
    return CacheService.headersFor(item, url: url);
  }

  Future<bool> _validateDownloadedFile(CacheItem item, File file) async {
    try {
      if (!await file.exists()) return false;
      final size = await file.length();
      if (size >= minValidVideoBytes) return true;
      await file.delete();
      debugPrint('下载失败: 文件过小 (${size}B)，可能为错误页或非视频内容');
      await _store.saveCacheItem(item.copyWith(status: 'failed'));
      return false;
    } catch (e) {
      debugPrint('校验缓存文件失败: $e');
      await _store.saveCacheItem(item.copyWith(status: 'failed'));
      return false;
    }
  }

  /// 缓存目录
  String? _cacheDir;

  /// 活跃下载任务
  final Map<String, CancelToken> _activeDownloads = {};

  /// 下载进度回调
  final Map<String, void Function(int, int)> _progressCallbacks = {};

  VoidCallback? _cacheItemsChangedListener;

  /// 缓存项写入后通知（供 [CacheProvider] 刷新 UI）。
  set cacheItemsChangedListener(VoidCallback? listener) {
    _cacheItemsChangedListener = listener;
  }

  void _emitCacheItemsChanged() {
    _cacheItemsChangedListener?.call();
  }

  Future<void> _persistItem(CacheItem item, {bool notifyUi = false}) async {
    await _store.saveCacheItem(item);
    if (notifyUi) _emitCacheItemsChanged();
  }

  static int _taskSelectionPriority(CacheItem item) {
    if (item.isDownloading) return 0;
    if (item.isWaiting) return 1;
    if (item.isPaused) return 2;
    if (item.isFailed) return 3;
    if (item.isCompleted) return 4;
    return 5;
  }

  /// 连接状态订阅
  ///
  /// connectivity_plus 7.x 起回调给的是**全部**可用网络类型
  /// （`List<ConnectivityResult>`，多网卡/热点并存时不再互相覆盖），
  /// 这里在入口处折算成一个"代表类型"再交给 [_connectivityAllowsDownload]。
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  Future<void>? _downloadStartLock;

  bool _onlyWifi = false;

  /// 是否仅 WiFi 下载
  bool get onlyWifi => _onlyWifi;

  /// 最大并发下载数
  static const int maxConcurrentDownloads = 3;

  /// 最大缓存容量（字节）
  static int get maxCacheBytes => AppConstants.maxCacheSize * 1024 * 1024;

  /// 初始化
  Future<void> init() async {
    if (kIsWeb) {
      // Web端不支持文件缓存，跳过目录创建
      _onlyWifi = _store.getBoolSetting(
        AppConstants.keyOnlyWifiCache,
        defaultValue: false,
      );
      return;
    }

    // 桌面端位于软件所在目录（绿色便携），移动端走应用支持目录。
    final cacheDir = await AppDataPaths.cacheRoot();
    _cacheDir = cacheDir.path;
    await Directory(_cacheDir!).create(recursive: true);
    await _migrateFromLegacyTempCache();

    _onlyWifi = _store.getBoolSetting(
      AppConstants.keyOnlyWifiCache,
      defaultValue: false,
    );

    // 监听网络状态
    await _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final result = representativeConnectivity(results);
      if (_onlyWifi && result != ConnectivityResult.wifi) {
        pauseAllDownloads();
        return;
      }
      if (_connectivityAllowsDownload(result)) {
        unawaited(scheduleWaitingDownloads());
      }
    });
    unawaited(scheduleWaitingDownloads());
  }

  /// 把 connectivity_plus 7.x 的「全部网络类型」折算成一个代表类型。
  ///
  /// 判定原则：**只要有一条 WiFi 就算 WiFi**（双网卡/移动热点并存时，
  /// 用户既连着 WiFi 又有移动数据是常态，按 wifi 判定才符合"仅 WiFi 下载"
  /// 的直觉）；空列表与只含 none 都视为断网；否则按 wifi 以外的固定优先级
  /// 取一个，避免调用方被迫关心多网卡语义。
  @visibleForTesting
  static ConnectivityResult representativeConnectivity(
    List<ConnectivityResult> results,
  ) {
    if (results.contains(ConnectivityResult.wifi)) {
      return ConnectivityResult.wifi;
    }
    if (results.contains(ConnectivityResult.ethernet)) {
      return ConnectivityResult.ethernet;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return ConnectivityResult.mobile;
    }
    if (results.contains(ConnectivityResult.vpn)) {
      return ConnectivityResult.vpn;
    }
    return ConnectivityResult.none;
  }

  bool _connectivityAllowsDownload(ConnectivityResult result) {
    return connectivityAllowsDownload(result: result, onlyWifi: _onlyWifi);
  }

  /// 网络是否允许下载（单测可直测）。
  @visibleForTesting
  static bool connectivityAllowsDownload({
    required ConnectivityResult result,
    required bool onlyWifi,
  }) {
    if (result == ConnectivityResult.none) return false;
    if (!onlyWifi) return true;
    return result == ConnectivityResult.wifi;
  }

  Future<M3u8MediaPlaylist> _resolveM3u8Playlist(
    String url, {
    String? referer,
  }) {
    final override = _m3u8ResolveOverride;
    if (override != null) {
      return override(url, referer: referer);
    }
    return _m3u8Resolver.resolve(url, referer: referer);
  }

  /// 占满并发槽（单测模拟已有下载任务）。
  @visibleForTesting
  void debugOccupyDownloadSlot(String cacheId) {
    _activeDownloads[cacheId] = CancelToken();
  }

  /// 获取缓存目录
  Future<String> getCacheDirectory() async {
    if (_cacheDirOverride != null) {
      await Directory(_cacheDirOverride!).create(recursive: true);
      return _cacheDirOverride!;
    }
    if (_cacheDir != null) return _cacheDir!;
    if (kIsWeb) return '';
    final cacheDir = await AppDataPaths.cacheRoot();
    _cacheDir = cacheDir.path;
    await Directory(_cacheDir!).create(recursive: true);
    await _migrateFromLegacyTempCache();
    return _cacheDir!;
  }

  Future<void> _migrateFromLegacyTempCache() async {
    if (kIsWeb || _cacheDir == null) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final legacy = Directory('${tempDir.path}/movie_app/cache');
      if (!await legacy.exists()) return;
      await for (final entity in legacy.list(recursive: true)) {
        if (entity is! File) continue;
        final rel = entity.path.substring(legacy.path.length + 1);
        final target = File('${_cacheDir!}/$rel');
        if (await target.exists()) continue;
        await target.parent.create(recursive: true);
        await entity.copy(target.path);
      }
    } catch (e) {
      debugPrint('迁移旧缓存目录失败: $e');
    }
  }

  /// 是否允许加入下载队列（Web / 磁力 / 本地 file 不可缓存）。
  static bool isCacheableUrl(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.isEmpty) return false;
    if (lower.startsWith('magnet:') ||
        lower.startsWith('file:') ||
        lower.startsWith('magnet-file:')) {
      return false;
    }
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  /// m3u8 内容是否可离线拼接（非 master、无加密）。
  static String? m3u8CacheBlockReason(String content) {
    final upper = content.toUpperCase();
    if (upper.contains('#EXT-X-KEY')) {
      return 'encrypted';
    }
    if (upper.contains('#EXT-X-STREAM-INF')) {
      return 'master_playlist';
    }
    return null;
  }

  /// 获取缓存总大小（字节）
  Future<int> getTotalCacheSize() async {
    // Web 端无本地文件系统，直接返回 0（避免 dart:io 在 Web 抛 _Namespace）
    if (kIsWeb) return 0;
    final dir = Directory(await getCacheDirectory());
    int totalSize = 0;
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
    } catch (e) {
      debugPrint('计算缓存大小失败: $e');
    }
    return totalSize;
  }

  /// 添加缓存任务
  Future<CacheItem> addCacheTask({
    required String movieId,
    required String movieName,
    required String movieCover,
    required int episodeIndex,
    required String episodeName,
    required String url,
    String pageUrl = '',
    String quality = '自动',
    String sourceId = '',
  }) async {
    final id =
        'cache_${movieId}_${episodeIndex}_${DateTime.now().millisecondsSinceEpoch}';
    final cacheDir = await getCacheDirectory();
    final fileName = '${movieId}_$episodeIndex.mp4';
    final localPath = '$cacheDir/$fileName';

    final item = CacheItem(
      id: id,
      movieId: movieId,
      sourceId: sourceId,
      movieName: movieName,
      movieCover: movieCover,
      episodeIndex: episodeIndex,
      episodeName: episodeName,
      url: url,
      pageUrl: pageUrl,
      quality: quality,
      localPath: localPath,
      status: 'waiting',
    );

    await _store.saveCacheItem(item);
    return item;
  }

  /// 下载前确保未超过 [maxCacheBytes]；必要时 LRU 清理已完成项。
  Future<void> ensureSpaceForDownload({
    int estimatedBytes = 512 * 1024 * 1024,
  }) async {
    if (kIsWeb) return;
    var total = await getTotalCacheSize();
    if (total + estimatedBytes <= maxCacheBytes) return;

    final completed =
        _store.getAllCacheItems().where((i) => i.isCompleted).toList()
          ..sort(
            (a, b) {
              final ta = a.completedAt ?? a.createdAt;
              final tb = b.completedAt ?? b.createdAt;
              return ta.compareTo(tb);
            },
          );

    for (final old in completed) {
      if (total + estimatedBytes <= maxCacheBytes) break;
      await deleteCache(old.id);
      total = await getTotalCacheSize();
    }
  }

  /// 开始下载
  Future<bool> startDownload(String cacheId) async {
    final prepared = await _withDownloadStartLock(
      () => _prepareDownloadStart(cacheId),
    );
    if (prepared == null) return false;
    if (prepared.alreadyActive) return true;

    try {
      await ensureSpaceForDownload();
      if (isHlsUrl(prepared.item.url)) {
        return _downloadM3u8(
          cacheId,
          prepared.item,
          cancelToken: prepared.cancelToken,
        );
      }
      return _downloadDirect(
        cacheId,
        prepared.item,
        cancelToken: prepared.cancelToken,
      );
    } catch (e) {
      _releaseDownloadSlot(cacheId);
      rethrow;
    }
  }

  Future<_PreparedDownloadStart?> _prepareDownloadStart(String cacheId) async {
    if (_activeDownloads.containsKey(cacheId)) {
      return _PreparedDownloadStart.alreadyActive();
    }

    if (_onlyWifi) {
      final connectivity =
          representativeConnectivity(await _connectivityChecker());
      if (!_connectivityAllowsDownload(connectivity)) {
        debugPrint('非WiFi环境，暂停下载');
        return null;
      }
    }

    final items = _store.getAllCacheItems();
    final item = items.where((i) => i.id == cacheId).firstOrNull;
    if (item == null) return null;

    if (item.url.isEmpty) {
      debugPrint('下载失败: URL为空');
      await _store.saveCacheItem(item.copyWith(status: 'failed'));
      return null;
    }

    if (!isCacheableUrl(item.url)) {
      debugPrint('下载失败: URL不可缓存');
      await _store.saveCacheItem(item.copyWith(status: 'failed'));
      return null;
    }

    if (_activeDownloads.length >= maxConcurrentDownloads) {
      debugPrint('已达到最大并发下载数: $maxConcurrentDownloads');
      return null;
    }

    final cancelToken = CancelToken();
    _activeDownloads[cacheId] = cancelToken;
    return _PreparedDownloadStart(item: item, cancelToken: cancelToken);
  }

  /// 直链文件下载
  Future<bool> _downloadDirect(
    String cacheId,
    CacheItem item, {
    required CancelToken cancelToken,
    int resumeFrom = 0,
  }) async {
    final dir =
        Directory(item.localPath.substring(0, item.localPath.lastIndexOf('/')));
    await dir.create(recursive: true);

    await _store.saveCacheItem(item.copyWith(status: 'downloading'));

    // 记录下载开始时间，用于计算速度
    final startTime = DateTime.now();

    try {
      final dio = await _getDownloadDio();
      final headers = _fetchHeadersForItem(item);
      if (resumeFrom > 0) {
        headers['Range'] = 'bytes=$resumeFrom-';
      }

      await dio.download(
        item.url,
        item.localPath,
        cancelToken: cancelToken,
        options: Options(headers: headers),
        onReceiveProgress: (received, total) {
          final actualReceived = resumeFrom + received;
          final actualTotal =
              resumeFrom > 0 && total > 0 ? resumeFrom + total : total;
          if (actualTotal > 0) {
            final elapsedSeconds =
                DateTime.now().difference(startTime).inSeconds + 1;
            unawaited(
              _persistItem(
                item.copyWith(
                  downloadedSize: actualReceived,
                  fileSize: actualTotal,
                  speed: received ~/ elapsedSeconds,
                ),
                notifyUi: true,
              ),
            );
            final callback = _progressCallbacks[cacheId];
            if (callback != null) {
              callback(actualReceived, actualTotal);
            }
          }
        },
      );

      // 下载完成
      final file = File(item.localPath);
      final fileSize = await file.length();
      if (!await _validateDownloadedFile(item, file)) {
        _releaseDownloadSlot(cacheId);
        unawaited(scheduleWaitingDownloads());
        return false;
      }
      await _store.saveCacheItem(
        item.copyWith(
          status: 'completed',
          fileSize: fileSize,
          downloadedSize: fileSize,
          completedAt: DateTime.now(),
        ),
      );

      _releaseDownloadSlot(cacheId);
      unawaited(scheduleWaitingDownloads());
      return true;
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        // 用户取消
        await _store.saveCacheItem(item.copyWith(status: 'paused'));
      } else {
        // 下载失败
        await _store.saveCacheItem(item.copyWith(status: 'failed'));
        debugPrint('下载失败: $e');
      }
      _releaseDownloadSlot(cacheId);
      unawaited(scheduleWaitingDownloads());
      return false;
    }
  }

  /// m3u8分片下载
  Future<bool> _downloadM3u8(
    String cacheId,
    CacheItem item, {
    required CancelToken cancelToken,
    bool startFrom = false,
  }) async {
    final dir =
        Directory(item.localPath.substring(0, item.localPath.lastIndexOf('/')));
    await dir.create(recursive: true);

    await _store.saveCacheItem(item.copyWith(status: 'downloading'));

    try {
      final playlist = await _resolveM3u8Playlist(
        item.url,
        referer: item.pageUrl.trim().isNotEmpty ? item.pageUrl : item.url,
      );
      final tsUrls = playlist.segmentUrls;
      if (tsUrls.isEmpty) {
        await _store.saveCacheItem(item.copyWith(status: 'failed'));
        _releaseDownloadSlot(cacheId);
        unawaited(scheduleWaitingDownloads());
        return false;
      }
      // AES-128 隐式 IV 由原始分片序号推导；广告剔除后需按原始序号解密。
      int sourceIndexFor(int i) {
        return i >= 0 && i < playlist.segmentSourceIndices.length
            ? playlist.segmentSourceIndices[i]
            : i;
      }

      final fetchHeaders = _fetchHeadersForItem(
        item,
        url: playlist.playlistUrl,
      );
      Uint8List? aesKeyBytes;
      if (playlist.aes128Key != null) {
        aesKeyBytes = await HlsSegmentCrypto.loadKeyBytes(
          playlist.aes128Key!,
          headers: _fetchHeadersForItem(
            item,
            url: playlist.aes128Key!.uri,
          ),
        );
      }

      final dio = await _getDownloadDio();
      final tempDir = '${item.localPath}_temp';
      await Directory(tempDir).create(recursive: true);

      final downloadStartedAt = DateTime.now();
      var downloadedBytes = 0;

      int startSegment = 0;
      if (startFrom) {
        for (var i = 0; i < tsUrls.length; i++) {
          final tsPath = '$tempDir/segment_$i.ts';
          if (await File(tsPath).exists()) {
            downloadedBytes += await File(tsPath).length();
          } else {
            startSegment = i;
            break;
          }
          if (i == tsUrls.length - 1) {
            startSegment = tsUrls.length;
          }
        }
      }

      for (var i = startSegment; i < tsUrls.length; i++) {
        if (cancelToken.isCancelled) break;

        final tsPath = '$tempDir/segment_$i.ts';
        final response = await dio.get<List<int>>(
          tsUrls[i],
          cancelToken: cancelToken,
          options: Options(
            headers: fetchHeaders,
            responseType: ResponseType.bytes,
          ),
        );
        var bytes = Uint8List.fromList(response.data ?? const []);
        if (aesKeyBytes != null) {
          bytes = HlsSegmentCrypto.decryptSegment(
            encrypted: bytes,
            keyBytes: aesKeyBytes,
            segmentIndex: sourceIndexFor(i),
            ivHex: playlist.aes128Key?.ivHex,
          );
        }
        await File(tsPath).writeAsBytes(bytes, flush: true);
        downloadedBytes += bytes.length;

        final segmentsDone = i + 1;
        final estimatedTotal = downloadedBytes * tsUrls.length ~/ segmentsDone;
        final elapsedMs =
            DateTime.now().difference(downloadStartedAt).inMilliseconds;
        final speed = elapsedMs > 0 ? (downloadedBytes * 1000 ~/ elapsedMs) : 0;
        await _persistItem(
          item.copyWith(
            downloadedSize: downloadedBytes,
            fileSize: estimatedTotal,
            speed: speed,
          ),
          notifyUi: true,
        );
        final callback = _progressCallbacks[cacheId];
        if (callback != null) {
          callback(downloadedBytes, estimatedTotal);
        }
      }

      // 检查是否被取消
      if (cancelToken.isCancelled) {
        await _store.saveCacheItem(item.copyWith(status: 'paused'));
        _releaseDownloadSlot(cacheId);
        unawaited(scheduleWaitingDownloads());
        return false;
      }

      // 6. 合并ts为mp4（直接拼接文件）
      final outFile = File(item.localPath);
      final sink = outFile.openWrite();
      for (int i = 0; i < tsUrls.length; i++) {
        final tsFile = File('$tempDir/segment_$i.ts');
        if (await tsFile.exists()) {
          final bytes = await tsFile.readAsBytes();
          sink.add(bytes);
        }
      }
      await sink.close();

      // 7. 清理临时文件
      await Directory(tempDir).delete(recursive: true);

      // 8. 更新状态
      final fileSize = await outFile.length();
      if (!await _validateDownloadedFile(item, outFile)) {
        _releaseDownloadSlot(cacheId);
        unawaited(scheduleWaitingDownloads());
        return false;
      }
      await _store.saveCacheItem(
        item.copyWith(
          status: 'completed',
          fileSize: fileSize,
          downloadedSize: fileSize,
          completedAt: DateTime.now(),
        ),
      );

      _releaseDownloadSlot(cacheId);
      unawaited(scheduleWaitingDownloads());
      return true;
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        await _store.saveCacheItem(item.copyWith(status: 'paused'));
      } else {
        await _store.saveCacheItem(item.copyWith(status: 'failed'));
        debugPrint('m3u8下载失败: $e');
      }
      _releaseDownloadSlot(cacheId);
      unawaited(scheduleWaitingDownloads());
      return false;
    }
  }

  /// 暂停下载
  void pauseDownload(String cacheId) {
    final cancelToken = _activeDownloads[cacheId];
    if (cancelToken != null) {
      cancelToken.cancel('用户暂停');
      _releaseDownloadSlot(cacheId);
      unawaited(scheduleWaitingDownloads());
    }
  }

  /// 暂停所有下载
  void pauseAllDownloads() {
    for (final id in _activeDownloads.keys.toList()) {
      pauseDownload(id);
    }
  }

  /// 恢复下载（支持断点续传）
  Future<bool> resumeDownload(String cacheId) async {
    final prepared = await _withDownloadStartLock(
      () => _prepareResumeDownload(cacheId),
    );
    if (prepared == null) return false;
    if (prepared.alreadyActive) return true;

    try {
      if (prepared.item.url.contains('.m3u8')) {
        return _downloadM3u8(
          cacheId,
          prepared.item,
          cancelToken: prepared.cancelToken,
          startFrom: true,
        );
      }
      return _downloadDirect(
        cacheId,
        prepared.item,
        cancelToken: prepared.cancelToken,
        resumeFrom: prepared.item.downloadedSize,
      );
    } catch (e) {
      _releaseDownloadSlot(cacheId);
      rethrow;
    }
  }

  Future<_PreparedDownloadStart?> _prepareResumeDownload(String cacheId) async {
    if (_activeDownloads.containsKey(cacheId)) {
      return _PreparedDownloadStart.alreadyActive();
    }

    if (_onlyWifi) {
      final connectivity =
          representativeConnectivity(await _connectivityChecker());
      if (!_connectivityAllowsDownload(connectivity)) {
        debugPrint('非WiFi环境，暂停下载');
        return null;
      }
    }

    final items = _store.getAllCacheItems();
    final item = items.where((i) => i.id == cacheId).firstOrNull;
    if (item == null) return null;

    if (item.url.isEmpty) {
      debugPrint('下载失败: URL为空');
      await _store.saveCacheItem(item.copyWith(status: 'failed'));
      return null;
    }

    if (_activeDownloads.length >= maxConcurrentDownloads) {
      debugPrint('已达到最大并发下载数: $maxConcurrentDownloads');
      return null;
    }

    final cancelToken = CancelToken();
    _activeDownloads[cacheId] = cancelToken;
    return _PreparedDownloadStart(item: item, cancelToken: cancelToken);
  }

  Future<T> _withDownloadStartLock<T>(Future<T> Function() action) async {
    final previous = _downloadStartLock;
    final gate = Completer<void>();
    _downloadStartLock = gate.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }
    try {
      return await action();
    } finally {
      if (!gate.isCompleted) {
        gate.complete();
      }
      if (identical(_downloadStartLock, gate.future)) {
        _downloadStartLock = null;
      }
    }
  }

  /// 删除缓存
  Future<bool> deleteCache(String cacheId) async {
    // 暂停下载
    pauseDownload(cacheId);

    // 删除文件
    final items = _store.getAllCacheItems();
    final item = items.where((i) => i.id == cacheId).firstOrNull;
    if (item != null && item.localPath.isNotEmpty) {
      try {
        final file = File(item.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('删除缓存文件失败: $e');
      }
    }

    // 删除记录
    await _store.deleteCacheItem(cacheId);
    unawaited(scheduleWaitingDownloads());
    return true;
  }

  /// 清理所有缓存
  Future<int> clearAllCache() async {
    pauseAllDownloads();

    int deletedCount = 0;
    final items = _store.getAllCacheItems();

    for (final item in items) {
      try {
        if (item.localPath.isNotEmpty) {
          final file = File(item.localPath);
          if (await file.exists()) {
            await file.delete();
          }
        }
        deletedCount++;
      } catch (e) {
        debugPrint('删除缓存文件失败: $e');
      }
    }

    await _store.clearCacheItems();
    return deletedCount;
  }

  /// 设置进度回调
  void setProgressCallback(String cacheId, void Function(int, int) callback) {
    _progressCallbacks[cacheId] = callback;
  }

  /// 移除进度回调
  void removeProgressCallback(String cacheId) {
    _progressCallbacks.remove(cacheId);
  }

  /// 设置仅WiFi下载
  Future<void> setOnlyWifi(bool value) async {
    _onlyWifi = value;
    await _store.saveBoolSetting(AppConstants.keyOnlyWifiCache, value);
    if (!value) {
      unawaited(scheduleWaitingDownloads());
    }
  }

  /// 查找已完成的本集本地缓存播放 URI（`file://`），无则 null。
  Future<String?> completedLocalPlayUri({
    required String movieId,
    required int episodeIndex,
    String sourceId = '',
  }) async {
    if (kIsWeb) return null;
    final item = findCompletedEpisode(
      movieId: movieId,
      episodeIndex: episodeIndex,
      sourceId: sourceId,
    );
    if (item == null || item.localPath.isEmpty) return null;
    try {
      final file = File(item.localPath);
      if (!await file.exists()) return null;
      if (await file.length() <= 0) return null;
      return Uri.file(item.localPath).toString();
    } catch (e) {
      debugPrint('读取本地缓存失败: $e');
      return null;
    }
  }

  /// 已完成且文件存在的缓存项。
  CacheItem? findCompletedEpisode({
    required String movieId,
    required int episodeIndex,
    String sourceId = '',
  }) {
    final items = _store
        .getAllCacheItems()
        .where(
          (i) =>
              i.movieId == movieId &&
              i.episodeIndex == episodeIndex &&
              i.isCompleted &&
              i.localPath.isNotEmpty,
        )
        .toList();
    if (items.isEmpty) return null;

    if (sourceId.isNotEmpty) {
      final matched = items.where((i) => i.sourceId == sourceId).toList();
      if (matched.isNotEmpty) {
        return _firstExistingFileItem(matched);
      }
    }
    return _firstExistingFileItem(items);
  }

  CacheItem? _firstExistingFileItem(List<CacheItem> items) {
    for (final item in items) {
      if (File(item.localPath).existsSync()) return item;
    }
    return null;
  }

  /// 获取所有缓存项
  List<CacheItem> getAllCacheItems() {
    return _store.getAllCacheItems();
  }

  /// 查找指定影片集数的最近一条缓存任务（任意状态）。
  CacheItem? findTaskForEpisode({
    required String movieId,
    required int episodeIndex,
    String sourceId = '',
  }) {
    final matches = _store
        .getAllCacheItems()
        .where(
          (i) =>
              i.movieId == movieId &&
              i.episodeIndex == episodeIndex &&
              (sourceId.isEmpty ||
                  i.sourceId.isEmpty ||
                  i.sourceId == sourceId),
        )
        .toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      final pa = _taskSelectionPriority(a);
      final pb = _taskSelectionPriority(b);
      if (pa != pb) return pa.compareTo(pb);
      return b.createdAt.compareTo(a.createdAt);
    });
    return matches.first;
  }

  /// 有空闲并发槽时自动启动 waiting 队列中的任务。
  Future<void> scheduleWaitingDownloads() async {
    if (kIsWeb) return;

    final waiting = _store
        .getAllCacheItems()
        .where((i) => i.status == 'waiting')
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final item in waiting) {
      if (_activeDownloads.length >= maxConcurrentDownloads) break;
      unawaited(startDownload(item.id));
    }
  }

  void _releaseDownloadSlot(String cacheId) {
    _activeDownloads.remove(cacheId);
    _progressCallbacks.remove(cacheId);
  }

  /// 获取正在下载的任务数
  int get activeDownloadCount => _activeDownloads.length;

  /// 格式化文件大小
  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int unitIndex = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }
}

class _PreparedDownloadStart {
  const _PreparedDownloadStart({
    required this.item,
    required this.cancelToken,
    this.alreadyActive = false,
  });

  factory _PreparedDownloadStart.alreadyActive() {
    return _PreparedDownloadStart(
      item: _sentinelItem,
      cancelToken: CancelToken(),
      alreadyActive: true,
    );
  }

  static final CacheItem _sentinelItem = CacheItem(
    id: '',
    movieId: '',
    movieName: '',
    url: '',
  );

  final CacheItem item;
  final CancelToken cancelToken;
  final bool alreadyActive;
}
