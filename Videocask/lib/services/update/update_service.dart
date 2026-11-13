import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform, RandomAccessFile;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../config/constants.dart';
import '../debug_log.dart';
import '../storage_service.dart';
import 'update_policy.dart';

/// 一次检查更新的结果类型。
enum UpdateCheckStatus {
  /// 已是最新版本。
  upToDate,

  /// 发现可用更新。
  available,

  /// 仓库还没有任何 Release（首次发版前）。
  noRelease,

  /// 网络 / 解析失败。
  failed,
}

/// 检查更新的返回值。UI 据此区分「最新」「有新版」「还没发版」「网络失败」。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    this.info,
    this.error,
  });

  final UpdateCheckStatus status;
  final UpdateInfo? info;
  final String? error;

  bool get hasUpdate => status == UpdateCheckStatus.available && info != null;
}

/// GitHub Release 更新服务。
///
/// 只依赖公开仓库的只读接口，**不需要任何 Token**。
/// 发版（写）在 `tool/publish_release.py` 里做，凭证不进入客户端。
class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  // ==================== 仓库与接口 ====================

  /// 仓库坐标。改仓库时只改这两行。
  static const String repoOwner = '0Limerenceforu0';
  static const String repoName = 'Videocask';

  static const String _apiBase = 'https://api.github.com';
  static const String apiLatestRelease =
      '$_apiBase/repos/$repoOwner/$repoName/releases/latest';

  /// Release 页面（网络失败时给用户一个可手动打开的地址）。
  static const String releasesPageUrl =
      'https://github.com/$repoOwner/$repoName/releases';

  // ==================== 缓存 ====================

  /// 缓存有效期：GitHub 未认证接口限流是 60 次/小时/IP，
  /// 启动检查必须走缓存，否则同一出口 IP 下的用户很容易被限流。
  static const Duration cacheTtl = Duration(hours: 1);
  static const String _cacheJsonKey = 'update_release_cache_json';
  static const String _cacheAtKey = 'update_release_cache_at';

  /// 用户点「稍后」时记住跳过的构建号，同一构建不再反复弹。
  static const String _skippedBuildKey = 'update_skipped_build';

  /// 已经向用户提示过更新的版本（三段号）。同一版本只提醒一次。
  static const String _promptedVersionKey = 'update_prompted_version';

  // ==================== 平台通道 ====================

  static const MethodChannel _channel = MethodChannel('videocask/update');

  /// 当前运行平台。
  UpdatePlatform get platform {
    if (kIsWeb) return UpdatePlatform.web;
    if (Platform.isAndroid) return UpdatePlatform.android;
    if (Platform.isWindows) return UpdatePlatform.windows;
    return UpdatePlatform.unsupported;
  }

  /// Android 设备首选 ABI（其它平台返回 null）。
  ///
  /// 走原生 `Build.SUPPORTED_ABIS`，比 `Platform.version` 猜架构可靠。
  Future<String?> androidAbi() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final abis = await _channel.invokeListMethod<String>('getAbi');
      return pickAndroidAbiTag(abis ?? const []);
    } catch (e) {
      DebugLog.log('Update', '读取设备 ABI 失败: $e');
      return null;
    }
  }

  // ==================== 检查更新 ====================

  Dio _buildDio({Duration timeout = const Duration(seconds: 10)}) => Dio(
        BaseOptions(
          connectTimeout: timeout,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (code) => code != null && code >= 200 && code < 400,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'videocask-updater',
          },
        ),
      );

  /// 拉取最新 Release。
  ///
  /// [forceRefresh] 为 true 时绕过本地缓存（手动点「检查更新」用）。
  /// 网络失败**不会抛异常**，统一返回 [UpdateCheckResult.failed]，
  /// 保证启动路径上的静默检查永远不会因为网络问题影响主流程。
  Future<UpdateCheckResult> checkForUpdate({bool forceRefresh = false}) async {
    final current = currentVersion();
    if (!forceRefresh) {
      final cached = _readCache();
      if (cached != null) {
        return _evaluate(cached, current);
      }
    }

    try {
      final dio = _buildDio();
      final response = await dio.get<dynamic>(apiLatestRelease);
      final data = response.data;
      if (data is! Map) {
        return const UpdateCheckResult(
          status: UpdateCheckStatus.failed,
          error: '接口返回格式异常',
        );
      }
      final info = _parseRelease(Map<String, dynamic>.from(data));
      if (info == null) {
        return const UpdateCheckResult(
          status: UpdateCheckStatus.failed,
          error: 'Release 信息解析失败',
        );
      }
      await _writeCache(info);
      DebugLog.log(
        'Update',
        '检查更新: 远程 ${info.version.label} tag=${info.tagName} '
            '资产=${info.assets.map((a) => a.name).join(",")}',
      );
      return _evaluate(info, current);
    } on DioException catch (e) {
      // 404 = 仓库还没有任何 Release，这不是错误，是「还没发过版」。
      if (e.response?.statusCode == 404) {
        DebugLog.log('Update', '检查更新: 仓库暂无 Release');
        return const UpdateCheckResult(status: UpdateCheckStatus.noRelease);
      }
      DebugLog.log(
        'Update',
        '检查更新失败: ${e.type} status=${e.response?.statusCode} ${e.message}',
      );
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        error: _describeDioError(e),
      );
    } catch (e) {
      DebugLog.log('Update', '检查更新异常: $e');
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        error: e.toString(),
      );
    }
  }

  UpdateCheckResult _evaluate(UpdateInfo info, AppVersion current) {
    if (!info.version.isNewerThan(current)) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
        info: info,
      );
    }
    return UpdateCheckResult(
      status: UpdateCheckStatus.available,
      info: info,
    );
  }

  /// 本地当前版本。
  ///
  /// 只读 `AppConstants.appVersion`（发版时与 pubspec 同步，发版脚本会校验两者一致），
  /// 不在代码里另存一份版本号，避免「三处版本号漂移」。
  /// 构建号通过 `--dart-define=APP_BUILD_NUMBER=N` 可选注入；
  /// 未注入时仅按三段版本号比较——项目的发版规则保证每次交付 patch 递增，
  /// 因此三段号已足够判断新旧。
  AppVersion currentVersion() {
    final parsed = AppVersion.tryParse(AppConstants.appVersion);
    if (parsed == null) {
      return const AppVersion(major: 0, minor: 0, patch: 0, build: 0);
    }
    final build = UpdateBuildInfo.build;
    if (build <= 0) return parsed;
    return AppVersion(
      major: parsed.major,
      minor: parsed.minor,
      patch: parsed.patch,
      build: build,
    );
  }

  UpdateInfo? _parseRelease(Map<String, dynamic> json) {
    final tag = (json['tag_name'] ?? json['name'] ?? '').toString();
    final version = AppVersion.tryParse(tag) ??
        AppVersion.tryParse((json['name'] ?? '').toString());
    if (version == null) return null;

    final rawAssets = json['assets'];
    final assets = <ReleaseAsset>[];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final name = (map['name'] ?? '').toString();
        final url = (map['browser_download_url'] ?? '').toString();
        if (name.isEmpty || url.isEmpty) continue;
        assets.add(
          ReleaseAsset(
            name: name,
            downloadUrl: url,
            size: (map['size'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }

    DateTime? published;
    final publishedRaw = (json['published_at'] ?? '').toString();
    if (publishedRaw.isNotEmpty) {
      published = DateTime.tryParse(publishedRaw);
    }

    return UpdateInfo(
      version: version,
      tagName: tag,
      assets: assets,
      notes: (json['body'] ?? '').toString(),
      htmlUrl: (json['html_url'] ?? releasesPageUrl).toString(),
      publishedAt: published,
    );
  }

  String _describeDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接 GitHub 超时，请检查网络后重试';
      case DioExceptionType.connectionError:
        return '无法连接 GitHub，请检查网络或代理';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 403) return 'GitHub 接口访问过于频繁，请稍后再试';
        return 'GitHub 返回异常状态码 $code';
      default:
        return '检查更新失败：${e.message ?? e.type.name}';
    }
  }

  // ==================== 缓存读写 ====================

  UpdateInfo? _readCache() {
    final storage = StorageService();
    final at = storage.getIntSetting(_cacheAtKey, defaultValue: 0);
    if (at <= 0) return null;
    final savedAt = DateTime.fromMillisecondsSinceEpoch(at);
    if (DateTime.now().difference(savedAt) > cacheTtl) return null;
    final raw = storage.getSetting(_cacheJsonKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return _parseRelease(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(UpdateInfo info) async {
    final storage = StorageService();
    final payload = <String, dynamic>{
      'tag_name': info.tagName,
      'name': info.tagName,
      'body': info.notes,
      'html_url': info.htmlUrl,
      'published_at': info.publishedAt?.toIso8601String(),
      'assets': info.assets
          .map(
            (a) => {
              'name': a.name,
              'browser_download_url': a.downloadUrl,
              'size': a.size,
            },
          )
          .toList(),
    };
    await storage.saveSetting(_cacheJsonKey, jsonEncode(payload));
    await storage.saveIntSetting(
      _cacheAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 记住用户「稍后」跳过的构建号。
  Future<void> skipBuild(int? build) async {
    if (build == null) return;
    await StorageService().saveIntSetting(_skippedBuildKey, build);
  }

  int? skippedBuild() {
    final value =
        StorageService().getIntSetting(_skippedBuildKey, defaultValue: -1);
    return value < 0 ? null : value;
  }

  /// 记录「该版本已经提醒过」。写入后启动检查不再对同一版本弹窗。
  ///
  /// 存的是三段号（见 [versionKey]），不存构建号：远程 tag 一般不带 `+build`，
  /// 存构建号会在未注入 `APP_BUILD_NUMBER` 的平台上退化成 0，判断不稳定。
  Future<void> markVersionPrompted(AppVersion version) async {
    await StorageService().saveSetting(
      _promptedVersionKey,
      versionKey(version),
    );
  }

  /// 上一次已提醒过的版本（三段号）；从未提醒过返回 null。
  String? promptedVersion() {
    final value = StorageService().getSetting(_promptedVersionKey);
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // ==================== 下载 ====================

  /// 资产直连地址换成若干候选（直连优先，失败自动切镜像）。
  ///
  /// 镜像只作用于 `github.com/.../releases/download/...` 这类大文件；
  /// 小体积的 API JSON 不走镜像（镜像站不代理 API）。
  static List<String> downloadCandidates(String url) {
    final candidates = <String>[url];
    const mirrors = ['https://ghproxy.net/', 'https://gh-proxy.com/'];
    for (final mirror in mirrors) {
      final candidate = '$mirror$url';
      if (!candidates.contains(candidate)) candidates.add(candidate);
    }
    return candidates;
  }

  /// 下载到 [savePath]，按候选地址依次尝试。
  ///
  /// 返回实际成功的地址；全部失败时抛出最后一个异常。
  Future<String> download({
    required String url,
    required String savePath,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final candidates = downloadCandidates(url);
    Object? lastError;
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      try {
        DebugLog.log(
          'Update',
          '下载尝试 ${i + 1}/${candidates.length}: $candidate',
        );
        // 每个候选都用独立的 Dio：镜像超时后不能让连接池影响下一个。
        final dio = _buildDio(timeout: const Duration(seconds: 20));
        final tempPath = '$savePath.part';
        await dio.download(
          candidate,
          tempPath,
          cancelToken: cancelToken,
          deleteOnError: true,
          onReceiveProgress: (received, total) {
            if (total > 0) onProgress(received, total);
          },
        );
        final file = File(tempPath);
        if (!await file.exists()) {
          throw StateError('下载完成但文件不存在');
        }
        if (await file.length() < 1024) {
          throw StateError('下载内容异常（体积过小）');
        }
        // 镜像站失败时经常返回 200 + HTML 错误页，光看状态码会把网页当安装包。
        // APK 与 zip 都是 ZIP 容器，魔数必须是 "PK\x03\x04"。
        if (!await _looksLikeZip(file)) {
          throw StateError('下载内容不是有效的 APK/ZIP（可能是镜像错误页）');
        }
        // 先写临时文件再改名，避免半截文件被当成完整包。
        final target = File(savePath);
        if (await target.exists()) await target.delete();
        await file.rename(savePath);
        DebugLog.log(
            'Update', '下载成功: $savePath (${await File(savePath).length()} 字节)');
        return candidate;
      } on DioException catch (e) {
        lastError = e;
        if (CancelToken.isCancel(e)) rethrow;
        DebugLog.log('Update', '下载失败($candidate): ${e.type} ${e.message}');
      } catch (e) {
        lastError = e;
        DebugLog.log('Update', '下载失败($candidate): $e');
      }
    }
    throw lastError ?? StateError('所有下载地址均失败');
  }

  /// 校验文件头是不是 ZIP（APK 也是 ZIP）。用于挡住镜像返回的 HTML 错误页。
  static Future<bool> _looksLikeZip(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final head = await raf.read(4);
      // 'P' 'K' 0x03 0x04（空包可能是 0x05 0x06，按需放行前者即可）
      return head.length == 4 &&
          head[0] == 0x50 &&
          head[1] == 0x4B &&
          head[2] == 0x03 &&
          head[3] == 0x04;
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }
}

/// 构建期注入的可选信息。
class UpdateBuildInfo {
  UpdateBuildInfo._();

  /// 构建号（pubspec 的 `+N`），由构建命令注入：
  /// `flutter build apk --dart-define=APP_BUILD_NUMBER=68`。
  /// 未注入时为 0，此时版本比较只看三段版本号。
  static const int build = int.fromEnvironment('APP_BUILD_NUMBER');
}
