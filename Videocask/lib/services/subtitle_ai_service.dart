// ignore_for_file: prefer_const_constructors

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'storage_service.dart';
import 'subtitle_ai_backend.dart';
import 'subtitle_ai_online_backend.dart';
import 'subtitle_ai_sherpa_backend.dart';
import 'subtitle_ai_srt_formatter.dart';
import 'subtitle_ai_transformers_web_backend.dart';

/// 历史 API 配置结构（保留 SubtitleAiConfig 名称以避免破坏 import）
///
/// 新代码请直接使用 [SubtitleAiRuntimeConfig]。
class SubtitleAiConfig {
  final String apiUrl;
  final String? apiKey;
  final String model;
  final String language;
  final bool translate;
  final Duration? maxAudioDuration;
  final String? initialPrompt;
  final bool sendAsUrl;

  const SubtitleAiConfig({
    required this.apiUrl,
    this.apiKey,
    this.model = 'whisper-1',
    this.language = 'zh',
    this.translate = false,
    this.maxAudioDuration,
    this.initialPrompt,
    this.sendAsUrl = false,
  });

  bool get isConfigured => apiUrl.trim().isNotEmpty;
}

/// 顶层门面：保留旧 [SubtitleAiConfig] 兼容性，同时承担新 backend 调度职责。
///
/// 注册的后端：
/// - [OnlineApiSubtitleBackend]（在线 API，向后兼容）
/// - [SherpaOnnxSubtitleBackend]（Android/iOS/桌面 Native）
/// - [TransformersWebSubtitleBackend]（Web 浏览器）
class SubtitleAiService {
  static final SubtitleAiService _instance = SubtitleAiService._internal();
  factory SubtitleAiService() => _instance;
  SubtitleAiService._internal() {
    registerBackend(OnlineApiSubtitleBackend());
    if (!kIsWeb) {
      registerBackend(SherpaOnnxSubtitleBackend());
    } else {
      registerBackend(TransformersWebSubtitleBackend());
    }
  }

  final Map<SubtitleAiBackendKind, SubtitleAiBackend> _backends = {};

  /// 注册后端（重复注册会覆盖）
  void registerBackend(SubtitleAiBackend backend) {
    _backends[backend.kind] = backend;
  }

  SubtitleAiBackend? backendFor(SubtitleAiBackendKind kind) => _backends[kind];

  Iterable<SubtitleAiBackend> get allBackends => _backends.values;

  /// 从设置读取 runtime config（包含选定 backend + 离线模型 ID + API 配置）
  SubtitleAiRuntimeConfig runtimeFromSettings() {
    final s = StorageService();
    return SubtitleAiRuntimeConfig(
      backend: s.subtitleAiBackend,
      apiUrl: s.subtitleAiApiUrl,
      apiKey: s.subtitleAiApiKey,
      apiModel: s.subtitleAiModel,
      apiLanguage: s.subtitleAiLanguage,
      apiSendAsUrl: s.subtitleAiSendAsUrl,
      selectedModelId: s.subtitleAiOfflineModel,
      maxAudioDuration: s.subtitleAiMaxMinutes > 0
          ? Duration(minutes: s.subtitleAiMaxMinutes)
          : null,
      initialPrompt: s.subtitleAiInitialPrompt,
    );
  }

  /// 旧 API 兼容：返回历史 [SubtitleAiConfig]
  SubtitleAiConfig configFromSettings() {
    final s = StorageService();
    return SubtitleAiConfig(
      apiUrl: s.subtitleAiApiUrl,
      apiKey: s.subtitleAiApiKey,
      model: s.subtitleAiModel,
      language: s.subtitleAiLanguage,
      maxAudioDuration: s.subtitleAiMaxMinutes > 0
          ? Duration(minutes: s.subtitleAiMaxMinutes)
          : null,
      sendAsUrl: s.subtitleAiSendAsUrl,
      initialPrompt: s.subtitleAiInitialPrompt,
    );
  }

  /// 旧 API 兼容入口：使用 [SubtitleAiConfig]（会自动判定走 onlineApi backend）
  Future<SubtitleAiResult> generate({
    required String source,
    required SubtitleAiConfig config,
    String? hintTitle,
    void Function(SubtitleAiProgress)? onProgress,
  }) async {
    final runtime = _legacyToRuntime(config);
    return _dispatch(
      source: source,
      runtime: runtime,
      hintTitle: hintTitle,
      onProgress: onProgress,
    );
  }

  /// 新 API：直接传 [SubtitleAiRuntimeConfig]，可指定任意后端
  Future<SubtitleAiResult> generateWithBackend({
    required String source,
    SubtitleAiRuntimeConfig? runtime,
    String? hintTitle,
    void Function(SubtitleAiProgress)? onProgress,
  }) async {
    runtime ??= runtimeFromSettings();
    return _dispatch(
      source: source,
      runtime: runtime,
      hintTitle: hintTitle,
      onProgress: onProgress,
    );
  }

  Future<SubtitleAiResult> _dispatch({
    required String source,
    required SubtitleAiRuntimeConfig runtime,
    String? hintTitle,
    void Function(SubtitleAiProgress)? onProgress,
  }) async {
    final backend = _backends[runtime.backend];
    if (backend == null) {
      throw SubtitleAiException('当前平台不支持 ${runtime.backend.label}');
    }
    return backend.generate(
      source: source,
      runtime: runtime,
      hintTitle: hintTitle,
      onProgress: onProgress,
    );
  }

  SubtitleAiRuntimeConfig _legacyToRuntime(SubtitleAiConfig legacy) {
    return SubtitleAiRuntimeConfig(
      backend: SubtitleAiBackendKind.onlineApi,
      apiUrl: legacy.apiUrl,
      apiKey: legacy.apiKey,
      apiModel: legacy.model,
      apiLanguage: legacy.language,
      apiSendAsUrl: legacy.sendAsUrl,
      selectedModelId: StorageService().subtitleAiOfflineModel,
      maxAudioDuration: legacy.maxAudioDuration,
      initialPrompt: legacy.initialPrompt,
    );
  }

  /// 把 segments 列表转 SRT（UI 直接调用）
  String segmentsToSrt(
    List<SubtitleAiSegment> segments, {
    String fallbackPlain = '',
  }) {
    return SrtFormatter.fromSegments(segments, fallbackPlain: fallbackPlain);
  }
}

/// 抽音辅助：把生成的 SRT 落盘到临时目录，给播放器 [SubtitleService.loadFromFile] 用
Future<String> writeSrtToTemp(String srtContent) async {
  if (kIsWeb) {
    return srtContent;
  }
  final dir = await getTemporaryDirectory();
  final f = File(
    '${dir.path}${Platform.pathSeparator}ai_${DateTime.now().millisecondsSinceEpoch}.srt',
  );
  await f.writeAsString(srtContent, flush: true);
  return f.path;
}
