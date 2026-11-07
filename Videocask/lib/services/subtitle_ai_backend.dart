// ignore_for_file: prefer_const_constructors

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'subtitle_ai_model_manager.dart';

/// AI 字幕生成后端类型
enum SubtitleAiBackendKind {
  /// 在线 API（faster-whisper-server / OpenAI Whisper 兼容）
  onlineApi,

  /// Native 离线（Android/iOS/桌面走 sherpa_onnx）
  sherpaNative,

  /// Web 离线（浏览器内 transformers.js + Whisper）
  transformersWeb,
}

extension SubtitleAiBackendKindLabel on SubtitleAiBackendKind {
  String get label {
    switch (this) {
      case SubtitleAiBackendKind.onlineApi:
        return '在线 API';
      case SubtitleAiBackendKind.sherpaNative:
        return '本地离线（sherpa_onnx）';
      case SubtitleAiBackendKind.transformersWeb:
        return '本地离线（浏览器 Whisper）';
    }
  }

  /// 是否需要付费 / 自部署服务端
  bool get needsServer => this == SubtitleAiBackendKind.onlineApi;

  /// 是否需要先下载模型
  bool get needsModelDownload =>
      this == SubtitleAiBackendKind.sherpaNative ||
      this == SubtitleAiBackendKind.transformersWeb;
}

/// 后端统一接口
///
/// 任何后端只要实现 [generate]，就能被 UI 层无差别调用。
/// 这样设置页切换三种后端、播放器入口按钮都不需要感知底层差异。
abstract class SubtitleAiBackend {
  SubtitleAiBackendKind get kind;

  String get displayName;

  /// 后端当前是否已就绪
  /// - onlineApi: API URL 已配置
  /// - sherpaNative: 已选模型文件存在
  /// - transformersWeb: 浏览器 OPFS 中已有模型（首次自动下载）
  bool isReady({SubtitleAiRuntimeConfig? runtime});

  /// 真正执行生成
  Future<SubtitleAiResult> generate({
    required String source,
    required SubtitleAiRuntimeConfig runtime,
    String? hintTitle,
    void Function(SubtitleAiProgress)? onProgress,
  });
}

/// 运行时配置（从设置中读取，按需更新）
class SubtitleAiRuntimeConfig {
  /// 后端类型
  final SubtitleAiBackendKind backend;

  /// 在线 API 配置
  final String apiUrl;
  final String? apiKey;
  final String apiModel;
  final String apiLanguage;
  final bool apiSendAsUrl;

  /// 离线配置
  final String selectedModelId;

  /// 通用
  final Duration? maxAudioDuration;
  final String? initialPrompt;

  const SubtitleAiRuntimeConfig({
    required this.backend,
    required this.apiUrl,
    required this.apiKey,
    required this.apiModel,
    required this.apiLanguage,
    required this.apiSendAsUrl,
    required this.selectedModelId,
    this.maxAudioDuration,
    this.initialPrompt,
  });

  bool get isOnlineApiConfigured =>
      backend == SubtitleAiBackendKind.onlineApi && apiUrl.trim().isNotEmpty;

  bool get isOfflineReady {
    if (backend != SubtitleAiBackendKind.sherpaNative &&
        backend != SubtitleAiBackendKind.transformersWeb) {
      return false;
    }
    if (selectedModelId.isEmpty) return false;
    final m = kSubtitleAiModelRegistry.findById(selectedModelId);
    return m != null;
  }
}

/// 进度回调（统一 UI 显示）
class SubtitleAiProgress {
  final String stage;
  final double value; // 0..1
  const SubtitleAiProgress(this.stage, this.value);
}

/// 统一返回结果
class SubtitleAiResult {
  final String srtContent;
  final String plainText;
  final String? detectedLanguage;
  final Duration usedDuration;
  final Duration elapsed;
  final SubtitleAiBackendKind backend;

  const SubtitleAiResult({
    required this.srtContent,
    required this.plainText,
    required this.usedDuration,
    required this.elapsed,
    required this.backend,
    this.detectedLanguage,
  });
}

class SubtitleAiException implements Exception {
  final String message;
  const SubtitleAiException(this.message);
  @override
  String toString() => 'SubtitleAiException: $message';
}

/// 工厂 + 调度入口
/// 抽音结果：16kHz mono Float32（Whisper 期望的格式）
class PcmAudioStream {
  final Float32List samples;
  final int sampleRate;
  final Duration duration;

  const PcmAudioStream({
    required this.samples,
    required this.sampleRate,
    required this.duration,
  });

  /// 把 PCM16 mono Int16 字节流转换为 Whisper 期望的 Float32 [-1, 1]
  static Float32List pcm16BytesToFloat32(Int16List pcm) {
    final out = Float32List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      out[i] = pcm[i] / 32768.0;
    }
    return out;
  }

  /// 从 wav 文件读 16kHz mono PCM
  /// 简易 WAV 头解析（仅支持 PCM16，未压缩）
  static PcmAudioStream fromWavFile(File file) {
    final raf = file.openSync();
    try {
      final header = raf.readSync(44);
      if (header.length < 44) {
        throw SubtitleAiException('WAV 文件头过短：${file.path}');
      }
      // RIFF...WAVE
      final riff = String.fromCharCodes(header.sublist(0, 4));
      final wave = String.fromCharCodes(header.sublist(8, 12));
      if (riff != 'RIFF' || wave != 'WAVE') {
        throw SubtitleAiException('不是合法 WAV 文件：${file.path}');
      }
      final channels = header[22] | (header[23] << 8);
      final sampleRate = header[24] |
          (header[25] << 8) |
          (header[26] << 16) |
          (header[27] << 24);
      final bitsPerSample = header[34] | (header[35] << 8);
      final data = raf.readSync(raf.lengthSync() - 44);
      if (bitsPerSample != 16) {
        throw SubtitleAiException('仅支持 PCM16 WAV，文件是 ${bitsPerSample}bit');
      }
      final pcm = Int16List.view(
        data.buffer,
        data.offsetInBytes,
        data.lengthInBytes ~/ 2,
      );
      Float32List mono;
      if (channels == 1) {
        mono = pcm16BytesToFloat32(pcm);
      } else if (channels == 2) {
        // 取左声道
        mono = Float32List(pcm.length ~/ 2);
        for (var i = 0; i < mono.length; i++) {
          mono[i] = pcm[i * 2] / 32768.0;
        }
      } else {
        // 多声道：取第一个声道
        mono = Float32List(pcm.length ~/ channels);
        for (var i = 0; i < mono.length; i++) {
          mono[i] = pcm[i * channels] / 32768.0;
        }
      }
      final duration = Duration(
        milliseconds: (mono.length * 1000 ~/ sampleRate),
      );
      return PcmAudioStream(
        samples: mono,
        sampleRate: sampleRate,
        duration: duration,
      );
    } finally {
      raf.closeSync();
    }
  }
}

/// 仅调试时打印进度（避免 release 模式刷屏）
void subtitleAiLog(String message) {
  if (kDebugMode) {
    debugPrint('[SubtitleAi] $message');
  }
}
