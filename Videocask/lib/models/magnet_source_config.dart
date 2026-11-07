import 'package:flutter/foundation.dart';

/// 磁力搜索源驱动（决定如何解析响应）
enum MagnetSourceDriver {
  /// YTS.mx `list_movies.json`
  ytsMxApi,

  /// Torrentio / Stremio 风格 JSON（streams 列表，含 infoHash 或 magnet url）
  torrentioJson,

  /// 1337x 等：HTML 列表中含 magnet 与标题
  html1337x,

  /// BT4G：HTML 中的 magnet 链接
  htmlBt4g,

  /// Nyaa RSS（nyaa:infoHash 或 description 中的 magnet）
  rssNyaa,

  /// PirateBay apibay `q.php`
  apibay,

  /// SolidTorrents 类 HTML（兼容旧版）
  solidHtml,

  /// Jackett `api/v2.0/.../results` JSON（Results[].MagnetUri）
  jackettApi,

  /// Knaben 聚合 API（POST `https://api.knaben.org/v1`，独立生态冗余第二源，支持中文原名直查）
  knabenJson,
}

/// 单条磁力搜索源配置（内置或可自定义）
@immutable
class MagnetSourceConfig {
  final String id;
  final String displayName;
  final MagnetSourceDriver driver;

  /// 须包含 `{query}`；可选 `{page}`（数字页码，从 1 起）
  final String urlTemplate;
  final bool enabled;
  final bool isBuiltin;

  const MagnetSourceConfig({
    required this.id,
    required this.displayName,
    required this.driver,
    required this.urlTemplate,
    this.enabled = true,
    this.isBuiltin = false,
  });

  /// 将模板中的 `{query}`、`{page}` 替换为编码后的值
  String buildUrl(String query, {int page = 1}) {
    final q = Uri.encodeQueryComponent(query);
    return urlTemplate.replaceAll('{query}', q).replaceAll('{page}', '$page');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'driver': driver.name,
        'urlTemplate': urlTemplate,
        'enabled': enabled,
        'isBuiltin': isBuiltin,
      };

  factory MagnetSourceConfig.fromJson(Map<String, dynamic> json) {
    var d = MagnetSourceDriver.htmlBt4g;
    final dn = json['driver'] as String?;
    if (dn != null) {
      for (final v in MagnetSourceDriver.values) {
        if (v.name == dn) {
          d = v;
          break;
        }
      }
    }
    return MagnetSourceConfig(
      id: json['id'] as String? ?? 'unknown',
      displayName: json['displayName'] as String? ?? '未命名',
      driver: d,
      urlTemplate: json['urlTemplate'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      isBuiltin: json['isBuiltin'] as bool? ?? false,
    );
  }

  MagnetSourceConfig copyWith({
    String? id,
    String? displayName,
    MagnetSourceDriver? driver,
    String? urlTemplate,
    bool? enabled,
    bool? isBuiltin,
  }) {
    return MagnetSourceConfig(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      driver: driver ?? this.driver,
      urlTemplate: urlTemplate ?? this.urlTemplate,
      enabled: enabled ?? this.enabled,
      isBuiltin: isBuiltin ?? this.isBuiltin,
    );
  }
}
