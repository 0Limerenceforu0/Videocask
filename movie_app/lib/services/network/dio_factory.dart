import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import '../../config/constants.dart';

/// 网络请求缓存拦截器
class CacheInterceptor extends Interceptor {
  final String cacheDirPath;
  final Duration maxAge;

  CacheInterceptor({
    required this.cacheDirPath,
    this.maxAge = const Duration(hours: 1),
  });

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 只缓存GET请求
    if (options.method == 'GET') {
      final cacheKey = _getCacheKey(options);
      final cacheFile = File('$cacheDirPath/$cacheKey');

      if (await cacheFile.exists()) {
        final modifiedTime = await cacheFile.lastModified();
        if (DateTime.now().difference(modifiedTime) < maxAge) {
          final cachedData = await cacheFile.readAsString();
          final response = Response<String>(
            data: cachedData,
            statusCode: 200,
            requestOptions: options,
          );
          return handler.resolve(response);
        }
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    // 只缓存GET请求的成功响应
    if (response.requestOptions.method == 'GET' && response.statusCode == 200) {
      final cacheKey = _getCacheKey(response.requestOptions);
      final cacheFile = File('$cacheDirPath/$cacheKey');

      // 确保缓存目录存在
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsString(response.data.toString());
    }
    handler.next(response);
  }

  String _getCacheKey(RequestOptions options) {
    // 使用URL的MD5作为缓存键
    final uri = options.uri.toString();
    return '${uri.hashCode.abs()}.cache';
  }
}

/// 统一创建 [Dio]，避免各 Service 重复配置超时与重定向。
class DioFactory {
  DioFactory._();

  /// 获取缓存目录；Web 端无文件系统，返回 null 表示禁用磁盘缓存
  static Future<String?> _getCacheDir() async {
    if (kIsWeb) return null;
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}/dio_cache';
  }

  /// 响应为纯文本（CMS / m3u8 / HTML 解析等）
  static Future<Dio> plainText({
    Duration? connectTimeout,
    Duration? receiveTimeout,
    int maxRedirects = 5,
  }) async {
    final cacheDir = await _getCacheDir();
    final dio = Dio(
      BaseOptions(
        connectTimeout: connectTimeout ??
            const Duration(milliseconds: AppConstants.apiTimeout),
        receiveTimeout: receiveTimeout ??
            const Duration(milliseconds: AppConstants.apiTimeout),
        followRedirects: true,
        maxRedirects: maxRedirects,
        responseType: ResponseType.plain,
      ),
    );

    // 添加缓存拦截器（Web 端无文件系统，跳过磁盘缓存）
    if (cacheDir != null) {
      dio.interceptors.add(CacheInterceptor(cacheDirPath: cacheDir));
    }

    return dio;
  }

  /// 响应为 JSON（通用 REST 接口）
  static Future<Dio> json({
    Duration? connectTimeout,
    Duration? receiveTimeout,
  }) async {
    final cacheDir = await _getCacheDir();
    final dio = Dio(
      BaseOptions(
        connectTimeout: connectTimeout ??
            const Duration(milliseconds: AppConstants.apiTimeout),
        receiveTimeout: receiveTimeout ??
            const Duration(milliseconds: AppConstants.apiTimeout),
        followRedirects: true,
        maxRedirects: 5,
        responseType: ResponseType.json,
      ),
    );

    // 添加缓存拦截器（Web 端无文件系统，跳过磁盘缓存）
    if (cacheDir != null) {
      dio.interceptors.add(CacheInterceptor(cacheDirPath: cacheDir));
    }

    return dio;
  }
}
