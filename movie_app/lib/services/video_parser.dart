import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'media_fetch_headers.dart';
import 'network/dio_factory.dart';

/// 视频URL解析服务
///
/// 将采集站的网页播放链接解析为真实 m3u8 视频地址
class VideoParser {
  static final VideoParser _instance = VideoParser._internal();
  factory VideoParser() => _instance;
  VideoParser._internal();

  Dio? _dio;

  /// 初始化Dio实例
  Future<Dio> _getDio() async {
    _dio ??= await DioFactory.plainText(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    );
    return _dio!;
  }

  /// 解析视频URL
  ///
  /// 输入：网页播放链接（如 https://v.gsuus.com/play/yb8pL5Wb）
  /// 输出：真实 m3u8 地址（如 https://v.gsuus.com/play/hls/yb8pL5Wb/index.m3u8）
  ///
  /// 解析流程：
  /// 1. 请求播放页 HTML
  /// 2. 从 HTML 中提取 index.m3u8 链接
  /// 3. 请求 m3u8 主列表
  /// 4. 解析真实播放地址
  Future<String?> parseVideoUrl(String playPageUrl) async {
    try {
      debugPrint('开始解析视频URL: $playPageUrl');

      // 第一步：请求播放页，提取 index.m3u8
      final m3u8IndexUrl = await _extractM3u8IndexUrl(playPageUrl);
      if (m3u8IndexUrl == null) {
        debugPrint('未找到 index.m3u8 链接');
        return null;
      }
      debugPrint('找到 m3u8 索引: $m3u8IndexUrl');

      // 第二步：请求 m3u8 主列表，获取真实播放地址
      final realUrl = await _resolveM3u8Url(
        m3u8IndexUrl,
        referer: playPageUrl,
      );
      if (realUrl == null) {
        debugPrint('解析真实播放地址失败');
        // 返回 index.m3u8 本身，有些播放器也能直接播放
        return m3u8IndexUrl;
      }

      debugPrint('解析成功: $realUrl');
      return realUrl;
    } catch (e) {
      debugPrint('解析视频URL失败: $e');
      return null;
    }
  }

  /// 从播放页 HTML 中提取 index.m3u8 链接
  Future<String?> _extractM3u8IndexUrl(String pageUrl) async {
    try {
      final dio = await _getDio();
      final response = await dio.get(
        pageUrl,
        options: Options(headers: MediaFetchHeaders.forUrl(pageUrl)),
      );
      final html = response.data.toString();

      // 方法1：正则匹配 m3u8 链接
      final m3u8Pattern = RegExp(r'https?://[^\s"\x27<>]+\.m3u8[^\s"\x27<>]*');
      final matches = m3u8Pattern.allMatches(html);
      for (final match in matches) {
        final url = match.group(0)!;
        if (url.contains('index.m3u8')) {
          return url;
        }
      }

      // 方法2：如果没找到完整URL，尝试拼接
      // 有些页面可能用相对路径 /play/xxx/index.m3u8
      final relativePattern = RegExp(r'(/play/\S+\.m3u8)');
      final relativeMatches = relativePattern.allMatches(html);
      for (final match in relativeMatches) {
        final path = match.group(1)!;
        final uri = Uri.parse(pageUrl);
        return '${uri.scheme}://${uri.host}$path';
      }

      return null;
    } catch (e) {
      debugPrint('请求播放页失败: $e');
      return null;
    }
  }

  /// 解析 m3u8 主列表，获取真实播放地址
  Future<String?> _resolveM3u8Url(
    String m3u8IndexUrl, {
    String? referer,
  }) async {
    try {
      final dio = await _getDio();
      final response = await dio.get(
        m3u8IndexUrl,
        options: Options(
          headers: MediaFetchHeaders.forUrl(
            m3u8IndexUrl,
            referer: referer ?? m3u8IndexUrl,
          ),
        ),
      );
      final content = response.data.toString();

      final lines = content.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

        // 如果是相对路径，拼接域名
        if (trimmed.startsWith('/')) {
          final uri = Uri.parse(m3u8IndexUrl);
          return '${uri.scheme}://${uri.host}$trimmed';
        }

        // 如果是完整URL
        if (trimmed.startsWith('http')) {
          return trimmed;
        }
      }

      return null;
    } catch (e) {
      debugPrint('解析m3u8失败: $e');
      return null;
    }
  }
}
