/// CDN / 采集站媒体请求常用头（Referer、UA）。
class MediaFetchHeaders {
  MediaFetchHeaders._();

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static Map<String, String> forUrl(String url, {String? referer}) {
    final ref = referer?.trim();
    if (ref != null && ref.isNotEmpty) {
      final refUri = Uri.tryParse(ref);
      if (refUri != null && refUri.hasScheme) {
        final origin = '${refUri.scheme}://${refUri.host}';
        return {
          'User-Agent': _userAgent,
          'Referer': ref.endsWith('/') ? ref : '$ref/',
          'Origin': origin,
        };
      }
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return const {'User-Agent': _userAgent};
    }
    final origin = '${uri.scheme}://${uri.host}';
    return {
      'User-Agent': _userAgent,
      'Referer': '$origin/',
      'Origin': origin,
    };
  }
}
