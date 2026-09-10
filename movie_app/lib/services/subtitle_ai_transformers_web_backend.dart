// ignore_for_file: prefer_const_constructors

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'subtitle_ai_backend.dart';

/// Web 端 transformers.js 后端
///
/// **当前为 stub**：返回明确错误，等 JS bridge 完成后启用。
///
/// 后续接入：
/// 1. 在 `web/index.html` 注入 `<script type="module">` 加载
///    `@huggingface/transformers`（CDN: https://cdn.jsdelivr.net/npm/@huggingface/transformers）
/// 2. 暴露 `window.__whisperBridge` 对象，实现
///    `extractAudio(source) → {samples, sampleRate, durationMs}` 和
///    `transcribe(samples, sampleRate) → {segments, text, language}`
/// 3. 注册 Flutter `MethodChannel('web/whisper_bridge')` handler，dart 侧通过
///    `WebJsBridge.invoke` 调用上面两个方法
class TransformersWebSubtitleBackend implements SubtitleAiBackend {
  @override
  SubtitleAiBackendKind get kind => SubtitleAiBackendKind.transformersWeb;

  @override
  String get displayName => '本地离线（浏览器 Whisper）';

  @override
  bool isReady({SubtitleAiRuntimeConfig? runtime}) {
    return kIsWeb;
  }

  @override
  Future<SubtitleAiResult> generate({
    required String source,
    required SubtitleAiRuntimeConfig runtime,
    String? hintTitle,
    void Function(SubtitleAiProgress)? onProgress,
  }) async {
    if (!kIsWeb) {
      throw SubtitleAiException('transformers.js 后端仅 Web 端可用');
    }

    // 临时 stub：让 analyze 通过，等 web JS bridge 完成后再启用
    throw SubtitleAiException(
      'Web 端离线 Whisper 待启用。需要完成 web/index.html JS bridge 注入与 '
      'MethodChannel handler 注册（详见 subtitle_ai_transformers_web_backend.dart 顶部注释）。',
    );
  }
}