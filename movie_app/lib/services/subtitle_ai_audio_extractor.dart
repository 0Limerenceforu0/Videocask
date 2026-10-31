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

    if (kIsWeb) {
      throw UnsupportedError('Web 端请使用 AudioContext 路径，不要走 PcmAudioExtractor');
    }

    // http(s) 直接把 URL 交给 ffmpeg：ffmpeg 原生支持 http/https 与 HLS(m3u8)。
    // 旧实现会先下载到临时文件再喂给 ffmpeg——但本应用片源多为 m3u8，
    // 下载得到的只是几 KB 的播放列表文本，ffmpeg 根本解不出音频。
    // 这是「AI 字幕跑不通」的关键原因之一，同时也省掉 50MB 临时下载。
    final inputPath = source.startsWith('file://')
        ? source.replaceFirst('file://', '')
        : source;

    final isRemote =
        inputPath.startsWith('http://') || inputPath.startsWith('https://');
    if (!isRemote && !File(inputPath).existsSync()) {
      throw SubtitleAiException('音频源不存在：$inputPath');
    }

    onProgress?.call(const SubtitleAiProgress('抽取音频 PCM16 16kHz mono', 0.25));

    final maxSec = maxDuration?.inSeconds;
    final args = <String>[
      '-y',
      '-i',
      inputPath,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-f',
      's16le',
      '-acodec',
      'pcm_s16le',
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
  }

  static Future<Uint8List> _runFfmpeg(List<String> args) async {
    // Web 端没有本地 ffmpeg，也没有进程/文件系统；先短路掉，
    // 否则下面读 Platform 会抛 Unsupported operation: Platform._operatingSystem。
    if (kIsWeb) {
      throw UnsupportedError('浏览器端不支持本地 ffmpeg 抽音，请改用「在线 API」字幕。');
    }
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

  /// 定位 ffmpeg 可执行文件。
  ///
  /// 查找顺序：
  /// 1. 程序所在目录（随包分发的内置 ffmpeg，优先级最高）
  /// 2. 系统 PATH
  ///
  /// 都找不到时抛出**可操作**的错误（告诉用户该把 ffmpeg 放哪），
  /// 而不是让 `Process.start` 抛一个看不懂的 ProcessException。
  static Future<String> _resolveFfmpeg() async {
    final exeName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';

    // 1) 程序目录（与 exe 同级，便于绿色版随包携带）
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final bundled = File('${appDir.path}${Platform.pathSeparator}$exeName');
      if (bundled.existsSync()) return bundled.path;
    } catch (_) {}

    // 2) 系统 PATH
    try {
      final lookup = Platform.isWindows ? 'where' : 'which';
      final r = await Process.run(lookup, [exeName]);
      if (r.exitCode == 0) {
        final out = (r.stdout as String).trim();
        final first = out.split('\n').first.trim();
        if (first.isNotEmpty) return first;
      }
    } catch (_) {}

    String appDirHint = '';
    try {
      appDirHint = File(Platform.resolvedExecutable).parent.path;
    } catch (_) {}
    throw SubtitleAiException(
      '未找到 ffmpeg，无法抽取音频。\n'
      '请二选一：\n'
      '1) 安装 ffmpeg 并加入系统 PATH；\n'
      '2) 把 $exeName 直接放到程序目录：$appDirHint',
    );
  }

  /// 桌面端：spawn ffmpeg 子进程
  ///
  /// 释放纪律：ffmpeg 会一直跑到读完整个输入（整集可能是 GB 级），期间持有
  /// 管道 fd，且 stdout 在内存里累积 PCM（长视频可达数百 MB）。因此：
  /// 1. **必须有 kill 路径** —— 用户关掉弹窗/退出页面时要能终止子进程；
  /// 2. **必须有超时** —— 兜住「卡住不动」的子进程，避免无限期占用资源；
  /// 3. 退出时确保管道被 drain（否则子进程写满管道会永久阻塞）。
  static Future<Uint8List> _runFfmpegDesktop(List<String> args) async {
    final ffmpeg = await _resolveFfmpeg();
    final proc = await Process.start(ffmpeg, args);
    final out = <int>[];
    final errBuf = <String>[];
    final outSub = proc.stdout.listen((data) {
      out.addAll(data);
    });
    final errSub = proc.stderr.listen((e) {
      errBuf.add(String.fromCharCodes(e));
    });

    try {
      final exitCode = await proc.exitCode.timeout(
        _ffmpegTimeout,
        onTimeout: () {
          // 超时：杀掉子进程并抛错，避免它继续跑完整集。
          proc.kill(ProcessSignal.sigkill);
          throw SubtitleAiException(
            'ffmpeg 抽取音频超时（超过 ${_ffmpegTimeout.inMinutes} 分钟），已终止。',
          );
        },
      );
      if (exitCode != 0) {
        throw SubtitleAiException(
          'ffmpeg 退出码 $exitCode：${errBuf.join().split("\n").take(20).join("\n")}',
        );
      }
      return Uint8List.fromList(out);
    } finally {
      await outSub.cancel();
      await errSub.cancel();
    }
  }

  /// ffmpeg 抽取音频的最长耗时（超时即终止子进程）。
  static const Duration _ffmpegTimeout = Duration(minutes: 10);
}

/// 兼容抽象 static 不能直接被外部 override 的限制
class FfmpegMobileRunnerShim {
  static Future<Uint8List> Function(List<String>)? run;
}
