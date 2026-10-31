import 'dart:convert';

import '../models/magnet_source_config.dart';

/// 内置磁力源目录（与用户提供的「稳定源」对齐；Apibay 作为额外稳定 JSON 源保留）
class MagnetSourceCatalog {
  MagnetSourceCatalog._();

  /// 默认启用列表。
  ///
  /// 🔴 2026-10-27 真机（HUAWEI FNE-AN00 / 5G）+ 本机直连双重实测：
  /// YTS / 1337x / BT4G / Nyaa **全部 `connection timeout`**，
  /// 6 个内置源里只有 **Torrentio**（IMDb 索引）与 **apibay**（仅英文查询）
  /// 可达。这 4 个死源此前默认开启，用户每搜一次就要白等一整轮超时
  /// （搜索页实测 28.6s）。现改为默认关闭 —— 需要时可在
  /// 「设置 → 磁力搜索源」里手动打开。
  ///
  /// 注意：**不要**把 Torrentio 也关掉，它是国内唯一能出结果的磁力源。
  static List<MagnetSourceConfig> get builtInDefaults => const [
        MagnetSourceConfig(
          id: 'yts_mx',
          displayName: 'YTS.mx',
          driver: MagnetSourceDriver.ytsMxApi,
          urlTemplate:
              'https://yts.mx/api/v2/list_movies.json?query_term={query}&limit=20',
          // 实测不可达（5G 下 12s 连接超时）→ 默认关闭。
          enabled: false,
          isBuiltin: true,
        ),
        MagnetSourceConfig(
          id: 'torrentio',
          displayName: 'Torrentio',
          driver: MagnetSourceDriver.torrentioJson,
          // 2026-10-22 修复：Torrentio 只接受带媒体类型的路径（`movie/` 或
          // `series/`）。旧模板 `stream/{query}.json` 实测恒返 404 —— 它是国内
          // 唯一稳定可达的磁力源，模板错误直接导致「搜不到任何磁力」。
          // 片名查询不要走 Torrentio：`stream/search/{片名}.json` 实测返回
          // 空 streams（Torrentio 是 IMDb id 索引，见 _searchTorrentioAt）。
          urlTemplate: 'https://torrentio.strem.fun/stream/movie/{query}.json',
          enabled: true,
          isBuiltin: true,
        ),
        MagnetSourceConfig(
          id: '1337x',
          displayName: '1337x',
          driver: MagnetSourceDriver.html1337x,
          urlTemplate: 'https://1337x.to/search/{query}/1/',
          // 实测不可达 → 默认关闭。
          enabled: false,
          isBuiltin: true,
        ),
        MagnetSourceConfig(
          id: 'bt4g',
          displayName: 'BT4G',
          driver: MagnetSourceDriver.htmlBt4g,
          urlTemplate: 'https://bt4g.org/search/{query}',
          // 实测不可达 → 默认关闭。
          enabled: false,
          isBuiltin: true,
        ),
        MagnetSourceConfig(
          id: 'nyaa',
          displayName: 'Nyaa.si (RSS)',
          driver: MagnetSourceDriver.rssNyaa,
          urlTemplate: 'https://nyaa.si/?page=rss&q={query}',
          // 实测不可达 → 默认关闭。
          enabled: false,
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
