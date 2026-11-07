// ignore_for_file: prefer_const_constructors

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'subtitle_ai_backend.dart';
import 'subtitle_ai_audio_extractor.dart';
import 'subtitle_ai_model_manager.dart';
import 'subtitle_ai_srt_formatter.dart';

/// Native 端 sherpa_onnx 后端
///
/// 流程：
///   1. ffmpeg 抽 PCM16 16kHz mono Float32（最多 N 分钟）
///   2. sherpa_onnx OfflineRecognizer.decode() 一次性识别
///   3. segments[] → SRT
class SherpaOnnxSubtitleBackend implements SubtitleAiBackend {
  @override
  SubtitleAiBackendKind get kind => SubtitleAiBackendKind.sherpaNative;

  @override
  String get displayName => '本地离线（sherpa_onnx）';

  @override
  bool isReady({SubtitleAiRuntimeConfig? runtime}) {
    if (runtime == null) return false;
    return runtime.isOfflineReady;
  }

  @override
  Future<SubtitleAiResult> generate({
    required String source,
    required SubtitleAiRuntimeConfig runtime,
    String? hintTitle,
    void Function(SubtitleAiProgress)? onProgress,
  }) async {
    if (kIsWeb) {
      throw SubtitleAiException('sherpa_onnx 后端不支持 Web');
    }
    final model = kSubtitleAiModelRegistry.findById(runtime.selectedModelId);
    if (model == null) {
      throw SubtitleAiException('未选择模型');
    }
    if (!await model.isLocallyAvailable) {
      throw SubtitleAiException(
        '模型未下载：${model.displayName}。请到「设置 → AI 字幕生成」下载。',
      );
    }

    final stopwatch = Stopwatch()..start();

    // 1) 抽音
    final audio = await PcmAudioExtractor.extract(
      source: source,
      maxDuration: runtime.maxAudioDuration,
      onProgress: onProgress,
    );
    onProgress?.call(const SubtitleAiProgress('初始化识别器', 0.6));

    // 2) 初始化 recognizer
    final recognizer = await _createRecognizer(model);
    try {
      onProgress?.call(const SubtitleAiProgress('识别中…', 0.7));

      final stream = recognizer.createStream();
      stream.acceptWaveform(
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text;
      stream.free();

      onProgress?.call(const SubtitleAiProgress('生成 SRT', 0.95));

      // sherpa_onnx 默认只输出整段 text，需要分句 → 用 [，。！？…\n] 切分并按比例分配时间
      final segments = _splitTextToSegments(text, audio.duration);

      final srt = SrtFormatter.fromSegments(segments, fallbackPlain: text);
      stopwatch.stop();

      return SubtitleAiResult(
        srtContent: srt,
        plainText: text,
        detectedLanguage: _detectLangFromModel(model),
        usedDuration: audio.duration,
        elapsed: stopwatch.elapsed,
        backend: SubtitleAiBackendKind.sherpaNative,
      );
    } finally {
      recognizer.free();
    }
  }

  /// 把整段 plain text 按标点切分成 segments 并按时长比例分配时间
  List<SubtitleAiSegment> _splitTextToSegments(String text, Duration total) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return const [];

    // 中英常见句末标点 + 换行
    final regex = RegExp(r'[^。！？!?\.\n]+[。！？!?\.\n]?');
    final matches = regex.allMatches(cleaned).toList(growable: false);
    if (matches.isEmpty) {
      return [
        SubtitleAiSegment(
          startSec: 0,
          endSec: total.inMilliseconds / 1000.0,
          text: cleaned,
        ),
      ];
    }

    final totalMs = total.inMilliseconds.clamp(1, 1 << 30);
    final segs = <SubtitleAiSegment>[];
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final segText = m.group(0)!.trim();
      if (segText.isEmpty) continue;
      // 按字符数比例分配
      final startMs = (totalMs * m.start ~/ cleaned.length).clamp(0, totalMs);
      final endMs = (totalMs * m.end ~/ cleaned.length).clamp(0, totalMs);
      segs.add(
        SubtitleAiSegment(
          startSec: startMs / 1000.0,
          endSec: endMs / 1000.0,
          text: segText,
        ),
      );
    }
    return segs;
  }

  String? _detectLangFromModel(SubtitleAiModel model) {
    if (model.supportedLanguages.length == 1) {
      return model.supportedLanguages.first;
    }
    return null;
  }

  Future<sherpa_onnx.OfflineRecognizer> _createRecognizer(
    SubtitleAiModel model,
  ) async {
    final dir = await model.modelDir();
    final tokens = '${dir.path}${Platform.pathSeparator}tokens.txt';

    sherpa_onnx.OfflineModelConfig modelConfig;

    switch (model.engineKind) {
      case 'whisper':
        // 找 encoder / decoder 文件
        String encoder = '';
        String decoder = '';
        for (final name in model.requiredFiles) {
          if (name.endsWith('-encoder.onnx')) {
            encoder = '${dir.path}${Platform.pathSeparator}$name';
          } else if (name.endsWith('-decoder.onnx')) {
            decoder = '${dir.path}${Platform.pathSeparator}$name';
          }
        }
        if (encoder.isEmpty || decoder.isEmpty) {
          throw SubtitleAiException(
            'Whisper 模型文件不完整：缺少 encoder/decoder.onnx',
          );
        }
        modelConfig = sherpa_onnx.OfflineModelConfig(
          whisper: sherpa_onnx.OfflineWhisperModelConfig(
            encoder: encoder,
            decoder: decoder,
            language: 'zh',
            task: 'transcribe',
          ),
          tokens: tokens,
          modelType: 'whisper',
          debug: false,
          numThreads: 2,
        );
        break;

      case 'paraformer':
        final onnx = model.requiredFiles.firstWhere(
          (f) => f.endsWith('.onnx'),
          orElse: () => 'model.int8.onnx',
        );
        modelConfig = sherpa_onnx.OfflineModelConfig(
          paraformer: sherpa_onnx.OfflineParaformerModelConfig(
            model: '${dir.path}${Platform.pathSeparator}$onnx',
          ),
          tokens: tokens,
          modelType: 'paraformer',
          debug: false,
          numThreads: 2,
        );
        break;

      case 'sense_voice':
        final onnx = model.requiredFiles.firstWhere(
          (f) => f.endsWith('.onnx'),
          orElse: () => 'model.int8.onnx',
        );
        modelConfig = sherpa_onnx.OfflineModelConfig(
          senseVoice: sherpa_onnx.OfflineSenseVoiceModelConfig(
            model: '${dir.path}${Platform.pathSeparator}$onnx',
            language: 'zh',
            useInverseTextNormalization: true,
          ),
          tokens: tokens,
          modelType: 'sense_voice',
          debug: false,
          numThreads: 2,
        );
        break;

      case 'zipformer_ctc':
        final onnx = model.requiredFiles.firstWhere(
          (f) => f.endsWith('.onnx'),
          orElse: () => 'model.int8.onnx',
        );
        modelConfig = sherpa_onnx.OfflineModelConfig(
          zipformerCtc: sherpa_onnx.OfflineZipformerCtcModelConfig(
            model: '${dir.path}${Platform.pathSeparator}$onnx',
          ),
          tokens: tokens,
          modelType: 'zipformer2_ctc',
          debug: false,
          numThreads: 2,
        );
        break;

      default:
        throw SubtitleAiException('未支持的模型类型：${model.engineKind}');
    }

    final config = sherpa_onnx.OfflineRecognizerConfig(
      model: modelConfig,
      decodingMethod: 'greedy_search',
    );
    return sherpa_onnx.OfflineRecognizer(config);
  }
}
