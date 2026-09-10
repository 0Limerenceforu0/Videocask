// ignore_for_file: prefer_const_constructors

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'subtitle_ai_backend.dart';

/// 跨平台 PCM16 16kHz mono 抽音器
///
/// - Android / iOS：调 `ffmpeg_kit_flutter_new`（通过 [FfmpegMobileRunner] 委托）
/// - Windows / macOS / Linux：spawn 系统 `ffmpeg` 子进程
/// - Web：返回 UnsupportedError（Web 端走 AudioContext，由 transformer_web_backend 处理）
class PcmAudioExtractor {
  /// 抽一段视频/音频的前 N 秒，返回 PCM16 mono16k 的 Float32List
  ///
  /// [source] 支持：
  /// - 本地文件路径
  /// - http(s) URL（先下载前 ~50MB，避免搬整集）
  /// - `file://` 路径
  static Future<PcmAudioStream> extract({
    required String source,
    Duration? maxDuration,
    void Function(SubtitleAiProgress)? onProgress,
  }) async {
    onProgress?.call(const SubtitleAiProgress('定位音频源', 0.05));

    String inputPath;
    bool cleanup = false;

    if (source.startsWith('http://') || source.startsWith('https://')) {
      inputPath = await _downloadRemoteToTemp(source, onProgress);
      cleanup = true;
    } else if (source.startsWith('file://')) {
      inputPath = source.replaceFirst('file://', '');
    } else {
      inputPath = source;
    }

    if (!File(inputPath).existsSync()) {
      throw SubtitleAiException('音频源不存在：$inputPath');
    }

    try {
      if (kIsWeb) {
        throw UnsupportedError('Web 端请使用 AudioContext 路径，不要走 PcmAudioExtractor');
      }

      onProgress?.call(const SubtitleAiProgress('抽取音频 PCM16 16kHz mono', 0.25));

      final maxSec = maxDuration?.inSeconds;
      final args = <String>[
        '-y',
        '-i', inputPath,
        '-vn',
        '-ac', '1',
        '-ar', '16000',
        '-f', 's16le',
        '-acodec', 'pcm_s16le',
        if (maxSec != null && maxSec > 0) ...['-t', maxSec.toString()],
        'pipe:1',
      ];

      final result = await _runFfmpeg(args);
      onProgress?.call(const SubtitleAiProgress('解码完成', 0.55));

      final pcm = Int16List.view(
        result.buffer,
        result.offsetInBytes,
        result.lengthInBytes ~/ 2,
      );
      final samples = PcmAudioStream.pcm16BytesToFloat32(pcm);
      final duration = Duration(milliseconds: samples.length * 1000 ~/ 16000);
      return PcmAudioStream(
        samples: samples,
        sampleRate: 16000,
        duration: duration,
      );
    } finally {
      if (cleanup) {
        try {
          await File(inputPath).delete().catchError((_) => File(inputPath));
        } catch (_) {}
      }
    }
  }

  static Future<Uint8List> _runFfmpeg(List<String> args) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final runner = FfmpegMobileRunnerShim.run;
      if (runner == null) {
        throw SubtitleAiException(
          '移动端 ffmpeg runner 未注册，请在 main() 中调用 registerMobileFfmpegRunner()',
        );
      }
      return await runner(args);
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return await _runFfmpegDesktop(args);
    } else {
      throw UnsupportedError('当前平台不支持本地 ffmpeg 抽音：${Platform.operatingSystem}');
    }
  }

  /// 桌面端：spawn ffmpeg 子进程
  static Future<Uint8List> _runFfmpegDesktop(List<String> args) async {
    final proc = await Process.start('ffmpeg', args);
    final out = <int>[];
    final errBuf = <String>[];
    proc.stdout.listen((data) {
      out.addAll(data);
    });
    proc.stderr.listen((e) {
      errBuf.add(String.fromCharCodes(e));
    });
    final exitCode = await proc.exitCode;
    if (exitCode != 0) {
      throw SubtitleAiException(
        'ffmpeg 退出码 $exitCode：${errBuf.join().split("\n").take(20).join("\n")}',
      );
    }
    return Uint8List.fromList(out);
  }

  static Future<String> _downloadRemoteToTemp(
    String url,
    void Function(SubtitleAiProgress)? onProgress,
  ) async {
    final tmp = await _tempDir();
    final filename =
        'ai_src_${DateTime.now().millisecondsSinceEpoch}.bin';
    final file = File('${tmp.path}${Platform.pathSeparator}$filename');

    const maxBytes = 50 * 1024 * 1024; // 50MB 上限（抽 10 分钟够用）
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw SubtitleAiException('下载失败 ${resp.statusCode}：$url');
      }
      final sink = file.openWrite();
      var received = 0;
      var aborted = false;
      await for (final chunk in resp) {
        if (aborted) break;
        if (received + chunk.length > maxBytes) {
          sink.add(chunk.sublist(0, maxBytes - received));
          received = maxBytes;
          aborted = true;
          break;
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(SubtitleAiProgress(
          '下载音频样本 ${(received * 100 ~/ maxBytes)}%',
          0.05 + (received / maxBytes) * 0.20,
        ));
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close(force: true);
    }
    return file.path;
  }

  static Future<Directory> _tempDir() async {
    if (Platform.isWindows) {
      final base = Platform.environment['TEMP'] ?? 'C:\\Windows\\Temp';
      return Directory(base);
    } else if (Platform.isMacOS || Platform.isLinux) {
      return Directory('/tmp');
    } else {
      return Directory('.');
    }
  }
}

/// 兼容抽象 static 不能直接被外部 override 的限制
class FfmpegMobileRunnerShim {
  static Future<Uint8List> Function(List<String>)? run;
}