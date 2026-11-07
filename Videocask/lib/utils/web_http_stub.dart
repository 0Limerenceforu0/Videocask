/// 非 Web 端 HTTP 工具函数 stub
///
/// 非 Web 端不使用此文件，直接通过 Dio 发请求
library;

Future<String?> httpGetText(String url) async {
  throw UnsupportedError('httpGetText 仅在 Web 端可用');
}

Future<String?> webRequestForApi(String targetUrl) async {
  throw UnsupportedError('webRequestForApi 仅在 Web 端可用');
}

/// 非 Web 端不需要代理，原样返回。
String webProxiedMediaUrl(String rawUrl) => rawUrl;

/// 非 Web 端不需要代理，原样返回。
String webProxiedImageUrl(String rawUrl) => rawUrl;

/// 非 Web 端不需要代理，原样返回（真实请求头由 PlayerService 直接带上）。
String webProxiedMediaUrlWithHeaders(
  String rawUrl,
  Map<String, String> headers,
) =>
    rawUrl;

/// 非 Web 端走本地 HLS 去广告代理，这里原样返回。
String webHlsUrl(String rawUrl) => rawUrl;
