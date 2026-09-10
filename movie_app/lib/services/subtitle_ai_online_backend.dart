// ignore_for_file: prefer_const_constructors

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'subtitle_ai_backend.dart';
import 'subtitle_ai_srt_formatter.dart';

/// 在线 API 后端（OpenAI / faster-whisper-server 兼容）
///
/// 历史版本 `subtitle_ai_service.dart` 实现的逻辑，等价迁移过来。
/// 仍支持「multipart file」「JSON URL」两种调用模式。
class OnlineApiSubtitleBackend implements SubtitleAiBackend {
  OnlineApiSubtitleBackend({Dio? dio}) : _dio = dio ?? _buildDio();

  final Dio _dio;

  static Dio _buildDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(minutes: 2),
      ),
    );
  }

  @override
  SubtitleAiBackendKind get kind => SubtitleAiBackendKind.onlineApi;

  @override
  String get displayName => '在线 API';

  @override
  bool isReady({SubtitleAiRuntimeConfig? runtime}) {
    return runtime?.isOnlineApiConfigured ?? false;
  }

  @override
  Future<SubtitleAiResult> generate({
    required String source,
    required SubtitleAiRuntimeConfig runtime,
    String? hintTitle,
    void Function(SubtitleAiProgress)? onProgress,
  }) async {
    if (!isReady(runtime: runtime)) {
      throw SubtitleAiException(
        '在线 API 未配置：请在「设置 → AI 字幕生成」中填写 API URL',
      );
    }

    final stopwatch = Stopwatch()..start();
    onProgress?.call(const SubtitleAiProgress('准备音频', 0.05));

    if (runtime.apiSendAsUrl) {
      return _sendUrl(source, runtime, stopwatch, onProgress);
    }

    File audioFile;
    if (source.startsWith('http://') || source.startsWith('https://')) {
      audioFile = await _downloadToTemp(source, runtime.maxAudioDuration, (p) {
        onProgress?.call(SubtitleAiProgress(
          '下载音频样本 ${(p * 100).toStringAsFixed(0)}%',
          0.05 + p * 0.40,
        ));
      });
    } else if (source.startsWith('file://')) {
      audioFile = File(source.replaceFirst('file://', ''));
    } else {
      audioFile = File(source);
    }

    if (!audioFile.existsSync()) {
      throw SubtitleAiException('音频源不存在：${audioFile.path}');
    }

    onProgress?.call(const SubtitleAiProgress('调用 AI 接口', 0.55));
    final resp = await _sendMultipart(
      audioFile: audioFile,
      runtime: runtime,
      hintTitle: hintTitle,
    );
    onProgress?.call(const SubtitleAiProgress('解析结果', 0.92));

    final segs = resp.segments
        .map((s) => SubtitleAiSegment(
              startSec: s.start,
              endSec: s.end,
              text: s.text,
            ))
        .toList();
    final srt = SrtFormatter.fromSegments(segs, fallbackPlain: resp.text);

    stopwatch.stop();
    try {
      if (source.startsWith('http')) {
        await audioFile.delete().catchError((_) => audioFile);
      }
    } catch (_) {}

    return SubtitleAiResult(
      srtContent: srt,
      plainText: resp.text,
      detectedLanguage: resp.language,
      usedDuration: runtime.maxAudioDuration ?? const Duration(minutes: 10),
      elapsed: stopwatch.elapsed,
      backend: SubtitleAiBackendKind.onlineApi,
    );
  }

  Future<File> _downloadToTemp(
    String url,
    Duration? maxDuration,
    void Function(double) onProgress,
  ) async {
    final tmp = await getTemporaryDirectory();
    final filename =
        'ai_sub_${DateTime.now().millisecondsSinceEpoch}.bin';
    final file = File('${tmp.path}${Platform.pathSeparator}$filename');

    const maxBytes = 50 * 1024 * 1024; // 50MB
    await _dio.download(
      url,
      file.path,
      onReceiveProgress: (rec, total) {
        if (total > 0) onProgress((rec / total).clamp(0.0, 1.0));
      },
      options: Options(responseType: ResponseType.bytes),
    );

    final size = await file.length();
    if (size > maxBytes) {
      final raf = file.openSync(mode: FileMode.read);
      try {
        final bytes = raf.readSync(maxBytes);
        await file.writeAsBytes(bytes, flush: true);
      } finally {
        await raf.close();
      }
    }
    return file;
  }

  Future<_WhisperResponse> _sendMultipart({
    required File audioFile,
    required SubtitleAiRuntimeConfig runtime,
    String? hintTitle,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(audioFile.path),
      'model': runtime.apiModel,
      'language': runtime.apiLanguage,
      'response_format': 'verbose_json',
      'timestamp_granularities[]': 'segment',
      if (runtime.initialPrompt != null && runtime.initialPrompt!.isNotEmpty)
        'prompt': runtime.initialPrompt!,
      if (hintTitle != null && hintTitle.isNotEmpty) 'prompt': hintTitle,
    });

    final headers = <String, String>{};
    if (runtime.apiKey != null && runtime.apiKey!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${runtime.apiKey}';
    }

    final resp = await _dio.post(
      runtime.apiUrl,
      data: form,
      options: Options(
        headers: headers,
        contentType: 'multipart/form-data',
      ),
    );

    if (resp.statusCode != 200) {
      throw SubtitleAiException(
        'AI 接口返回 ${resp.statusCode}: ${resp.data}',
      );
    }

    return _WhisperResponse.fromJson(resp.data);
  }

  Future<SubtitleAiResult> _sendUrl(
    String url,
    SubtitleAiRuntimeConfig runtime,
    Stopwatch stopwatch,
    void Function(SubtitleAiProgress)? onProgress,
  ) async {
    onProgress?.call(const SubtitleAiProgress('调用 AI 接口（URL 模式）', 0.5));
    final headers = <String, String>{};
    if (runtime.apiKey != null && runtime.apiKey!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${runtime.apiKey}';
    }
    final resp = await _dio.post(
      runtime.apiUrl,
      data: {
        'audio': url,
        'model': runtime.apiModel,
        'language': runtime.apiLanguage,
        'response_format': 'verbose_json',
        'timestamp_granularities': ['segment'],
        if (runtime.initialPrompt != null && runtime.initialPrompt!.isNotEmpty)
          'initial_prompt': runtime.initialPrompt,
      },
      options: Options(headers: headers),
    );
    if (resp.statusCode != 200) {
      throw SubtitleAiException(
        'AI 接口返回 ${resp.statusCode}: ${resp.data}',
      );
    }
    onProgress?.call(const SubtitleAiProgress('解析结果', 0.92));
    final parsed = _WhisperResponse.fromJson(resp.data);
    final segs = parsed.segments
        .map((s) => SubtitleAiSegment(
              startSec: s.start,
              endSec: s.end,
              text: s.text,
            ))
        .toList();
    final srt = SrtFormatter.fromSegments(segs, fallbackPlain: parsed.text);
    stopwatch.stop();
    return SubtitleAiResult(
      srtContent: srt,
      plainText: parsed.text,
      detectedLanguage: parsed.language,
      usedDuration: runtime.maxAudioDuration ?? const Duration(minutes: 10),
      elapsed: stopwatch.elapsed,
      backend: SubtitleAiBackendKind.onlineApi,
    );
  }
}

class _WhisperResponse {
  final String text;
  final String? language;
  final List<_WhisperSegment> segments;

  _WhisperResponse({
    required this.text,
    this.language,
    required this.segments,
  });

  static _WhisperResponse fromJson(dynamic data) {
    if (data is! Map) {
      return _WhisperResponse(text: data?.toString() ?? '', segments: []);
    }
    final text = (data['text'] ?? '').toString();
    final language = data['language']?.toString();
    final segs = <_WhisperSegment>[];
    final raw = data['segments'];
    if (raw is List) {
      for (final s in raw) {
        if (s is Map) {
          segs.add(_WhisperSegment(
            start: (s['start'] as num?)?.toDouble() ?? 0.0,
            end: (s['end'] as num?)?.toDouble() ?? 0.0,
            text: (s['text'] ?? '').toString(),
          ));
        }
      }
    }
    return _WhisperResponse(text: text, language: language, segments: segs);
  }
}

class _WhisperSegment {
  final double start;
  final double end;
  final String text;
  _WhisperSegment({required this.start, required this.end, required this.text});
}