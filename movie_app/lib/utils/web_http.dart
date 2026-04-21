/// Web端 HTTP 工具函数
///
/// 使用公共 CORS 代理直连 CMS（与 web/index.html 中脚本策略一致），避免仅请求
/// `/api/proxy` 却因静态托管无反代而拿到整页 HTML（`Unexpected token '<'`）。
/// 若你部署了自建反代，最后再尝试同源 `/api/proxy?url=...`。
///
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
library;

import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

final List<String Function(String targetUrl)> _corsProxyUrlBuilders = [
  (u) => 'https://api.allorigins.win/raw?url=${Uri.encodeQueryComponent(u)}',
  (u) => 'https://corsproxy.io/?${Uri.encodeComponent(u)}',
];

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

    if (request.status == 200 && request.responseText != null) {
      final text = request.responseText!;
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  } catch (e) {
    debugPrint('httpGetText 失败: $e');
    return null;
  }
}

/// Web 端请求 CMS JSON
Future<String?> webRequestForApi(String targetUrl) async {
  if (targetUrl.isEmpty) return null;

  for (final build in _corsProxyUrlBuilders) {
    try {
      final wrapped = build(targetUrl);
      final text = await httpGetText(wrapped);
      if (_responseLooksLikeApiJson(text)) {
        return text;
      }
      if (text != null && text.isNotEmpty) {
        debugPrint(
          'CORS 代理返回非 JSON（前 60 字）：${text.length > 60 ? text.substring(0, 60) : text}',
        );
      }
    } catch (e) {
      debugPrint('CORS 代理请求异常: $e');
    }
  }

  try {
    final proxyUrl = '/api/proxy?url=${Uri.encodeComponent(targetUrl)}';
    debugPrint('回退同源代理: $proxyUrl');
    final text = await httpGetText(proxyUrl);
    if (_responseLooksLikeApiJson(text)) {
      return text;
    }
  } catch (e) {
    debugPrint('同源代理失败: $e');
  }

  return null;
}
