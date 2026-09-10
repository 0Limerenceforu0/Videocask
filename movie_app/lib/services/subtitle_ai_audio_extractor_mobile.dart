// ignore_for_file: prefer_const_constructors

import 'dart:async';
import 'dart:typed_data';

import 'subtitle_ai_backend.dart';

/// 移动端 ffmpeg 抽音（Android/iOS）
///
/// 当前为 stub 实现：返回明确错误，引导用户/开发者集成 ffmpeg-kit 或其它方案。
///
/// **接入方案**（任选其一）：
///
/// 1. **使用 ffmpeg_kit_flutter_new**（推荐）：把下面 [ffmpegMobileRunImpl] 替换为：
///    ```dart
///    import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
///    import 'package:ffmpeg_kit_flutter_new/return_code.dart';
///
///    Future<Uint8List> ffmpegMobileRunImpl(List<String> args) async {
///      final command = args.join(' ');
///      final completer = Completer<Uint8List>();
///      await FFmpegKit.executeAsync(command, (session) async {
///        final code = await session.getReturnCode();
///        if (!ReturnCode.isSuccess(code)) {
///          completer.completeError(SubtitleAiException('ffmpeg 失败 ($code)'));
///          return;
///        }
///        final data = await session.getOutputData();
///        completer.complete(data != null
///            ? Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes)
///            : Uint8List(0));
///      });
///      return completer.future;
///    }
///    ```
///    然后把 ffmpeg_kit_flutter_new 加回 pubspec.yaml。
///
/// 2. **让用户在 Termux 里装 ffmpeg**：走 [subtitle_ai_audio_extractor.dart] 的
///    `Process.start('ffmpeg', args)` 路径（需要 root 或 Termux 启动）。
///
/// 3. **集成原生 SDK**：用 arthenica/ffmpeg-kit-android 的 jniLibs 形式，
///    自己写 MethodChannel 桥接。
Future<Uint8List> ffmpegMobileRunImpl(List<String> args) async {
  throw SubtitleAiException(
    '移动端 ffmpeg 抽音尚未启用。请按 file 顶部注释的 3 种方案之一接入。\n'
    '命令: ${args.join(" ")}',
  );
}

/// 注册移动端 runner
void registerMobileFfmpegRunner() {
  FfmpegMobileRunnerShim.run = ffmpegMobileRunImpl;
}

/// 兼容抽象 static 不能直接被外部 override 的限制
class FfmpegMobileRunnerShim {
  static Future<Uint8List> Function(List<String>)? run;
}