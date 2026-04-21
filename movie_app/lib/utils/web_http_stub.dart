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
