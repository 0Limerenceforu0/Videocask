import 'dart:convert';

import '../models/magnet_source_config.dart';

/// 内置磁力源目录（与用户提供的「稳定源」对齐；Apibay 作为额外稳定 JSON 源保留）
class MagnetSourceCatalog {
  MagnetSourceCatalog._();

  /// 默认启用列表：YTS、Torrentio、1337x、BT4G、Nyaa + Apibay
  static List<MagnetSourceConfig> get builtInDefaults => const [
        MagnetSourceConfig(
          id: 'yts_mx',
          displayName: 'YTS.mx',
          driver: MagnetSourceDriver.ytsMxApi,
          urlTemplate:
              'https://yts.mx/api/v2/list_movies.json?query_term={query}&limit=20',
          enabled: true,
          isBuiltin: true,
        ),
        MagnetSourceConfig(
          id: 'torrentio',
          displayName: 'Torrentio',
          driver: MagnetSourceDriver.torrentioJson,
          urlTemplate: 'https://torrentio.strem.fun/stream/{query}.json',
          enabled: true,
          isBuiltin: true,
        ),
        MagnetSourceConfig(
          id: '1337x',
          displayName: '1337x',
          driver: MagnetSourceDriver.html1337x,
          urlTemplate: 'https://1337x.to/search/{query}/1/',
          enabled: true,
          isBuiltin: true,
        ),
        MagnetSourceConfig(
          id: 'bt4g',
          displayName: 'BT4G',
          driver: MagnetSourceDriver.htmlBt4g,
          urlTemplate: 'https://bt4g.org/search/{query}',
          enabled: true,
          isBuiltin: true,
        ),
        MagnetSourceConfig(
          id: 'nyaa',
          displayName: 'Nyaa.si (RSS)',
          driver: MagnetSourceDriver.rssNyaa,
          urlTemplate: 'https://nyaa.si/?page=rss&q={query}',
          enabled: true,
          isBuiltin: true,
        ),
        MagnetSourceConfig(
          id: 'apibay',
          displayName: 'PirateBay (apibay)',
          driver: MagnetSourceDriver.apibay,
          urlTemplate: 'https://apibay.org/q.php?q={query}&cat=0&page={page}',
          enabled: true,
          isBuiltin: true,
        ),
      ];

  static String encodeList(List<MagnetSourceConfig> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<MagnetSourceConfig> decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => MagnetSourceConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
