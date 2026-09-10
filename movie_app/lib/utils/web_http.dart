/// Web端 HTTP 工具函数
///
/// 跨域策略（按优先级尝试，成功即记住，避免每个请求都走慢通道）：
/// 1. `--dart-define=CORS_PROXY_BASE=...` 指定的自建代理
/// 2. 同源 `/proxy?url=...`（由 `tool/web_dev_server.py` 提供）
/// 3. 本机默认端口 `http://127.0.0.1:8787/proxy?url=...`
/// 4. 公共 CORS 代理（兜底，常被限流）
///
/// 说明：浏览器直连 CMS 会被同源策略拦截，必须经代理转发。
///
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
library;

import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

/// 部署时可用 `--dart-define=CORS_PROXY_BASE=https://your-proxy/proxy?url=`
const String _proxyBaseOverride = String.fromEnvironment('CORS_PROXY_BASE');

/// 本地代理默认端口，可用 `--dart-define=CORS_PROXY_PORT=9000` 覆盖
const String _localProxyPort = String.fromEnvironment(
  'CORS_PROXY_PORT',
  defaultValue: '8787',
);

/// 上次成功的代理序号（进程内粘性记忆，减少无谓的超时等待）
int _preferredProxyIndex = 0;

/// 把目标 URL 拼到代理 base 上（兼容 base 是否已带 `url=` 参数）
String _buildProxyUrl(String base, String targetUrl) {
  final encoded = Uri.encodeComponent(targetUrl);
  if (base.endsWith('=') || base.endsWith('url')) return base + encoded;
  return base + (base.contains('?') ? '&url=' : '?url=') + encoded;
}

List<String Function(String targetUrl)> _corsProxyUrlBuilders() {
  final builders = <String Function(String)>[];
  if (_proxyBaseOverride.isNotEmpty) {
    builders.add((u) => _buildProxyUrl(_proxyBaseOverride, u));
  }
  builders.add((u) => '/proxy?url=${Uri.encodeComponent(u)}');
  builders.add(
    (u) => 'http://127.0.0.1:$_localProxyPort/proxy?url='
        '${Uri.encodeComponent(u)}',
  );
  builders.add(
    (u) => 'https://api.allorigins.win/raw?url='
        '${Uri.encodeQueryComponent(u)}',
  );
  return builders;
}

bool _responseLooksLikeApiJson(String? text) {
  if (text == null || text.isEmpty) return false;
  final t = text.trimLeft();
  if (t.startsWith('<') || t.startsWith('<!')) return false;
  return true;
}

/// 发起 GET 并返回文本（任意 URL）
Future<String?> httpGetText(String url) async {
  try {
    final request = html.HttpRequest();
    request.open('GET', url, async: true);
    request.responseType = 'text';
    request.send();

    await request.onLoad.first;

    if (request.status == 200) {
      final text = request.responseText;
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return null;
  } catch (e) {
    debugPrint('httpGetText 失败: $e');
    return null;
  }
}

/// Web 端请求 CMS JSON（自动挑选可用的 CORS 代理）
Future<String?> webRequestForApi(String targetUrl) async {
  if (targetUrl.isEmpty) return null;

  final builders = _corsProxyUrlBuilders();
  // 先试上次成功的那个，再按序尝试其余
  final order = <int>[
    if (_preferredProxyIndex < builders.length) _preferredProxyIndex,
    ...List.generate(builders.length, (i) => i)
        .where((i) => i != _preferredProxyIndex),
  ];

  for (final index in order) {
    try {
      final wrapped = builders[index](targetUrl);
      final text = await httpGetText(wrapped);
      if (_responseLooksLikeApiJson(text)) {
        _preferredProxyIndex = index;
        return text;
      }
      if (text != null && text.isNotEmpty) {
        debugPrint(
          'CORS 代理[$index] 返回非 JSON（前 60 字）：'
          '${text.length > 60 ? text.substring(0, 60) : text}',
        );
      }
    } catch (e) {
      debugPrint('CORS 代理请求异常: $e');
    }
  }
  return null;
}

/// 把 HLS 地址包装成同源的可播放地址。
///
/// 直接转发 m3u8 还不够：hls.js 会用 XHR 拉分片，分片地址同样跨域，
/// 且 m3u8 里的相对路径要相对原始地址解析。所以交给代理端的 `/hls`
/// 做播放列表重写（见 tool/web_dev_server.py）。
String webHlsUrl(String rawUrl) {
  if (rawUrl.isEmpty) return rawUrl;
  final lower = rawUrl.toLowerCase();
  if (lower.startsWith('blob:') || lower.contains('/hls?url=')) return rawUrl;
  // 用绝对地址，避免 hls.js / <video> 对相对路径解析不一致
  String origin;
  try {
    origin = Uri.base.origin;
  } catch (_) {
    origin = '';
  }
  return '$origin/hls?url=${Uri.encodeComponent(rawUrl)}';
}

/// 图片地址的 Web 端代理包装。
///
/// CanvasKit 渲染下跨域图片需要目标站返回 CORS 头，而 CMS 图床通常不返回，
/// 因此图片也必须经同源 `/proxy` 转发（与媒体地址同策略）。
String webProxiedImageUrl(String rawUrl) => webProxiedMediaUrl(rawUrl);

/// 把媒体地址包装成可跨域播放的地址（Web 端视频源同样受同源策略限制）。
///
/// 已是同源 / blob / data 的直返，其余交给 CORS 代理转发。
String webProxiedMediaUrl(String rawUrl) {
  if (rawUrl.isEmpty) return rawUrl;
  final lower = rawUrl.toLowerCase();
  if (lower.startsWith('blob:') ||
      lower.startsWith('data:') ||
      lower.startsWith('/') ||
      lower.contains('127.0.0.1') ||
      lower.contains('localhost')) {
    return rawUrl;
  }
  final builders = _corsProxyUrlBuilders();
  final index =
      _preferredProxyIndex < builders.length ? _preferredProxyIndex : 0;
  return builders[index](rawUrl);
}
