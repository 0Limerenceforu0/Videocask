import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// 本地离线字幕识别在此平台是否真的跑得起来。
///
/// 离线识别 = 本地 ASR 模型 + **本地抽音**。抽音依赖 ffmpeg：
/// - 桌面端：可 spawn 系统/随包 ffmpeg，链路完整；
/// - Android / iOS：`FfmpegMobileRunnerShim.run` 从未注册
///   （`subtitle_ai_audio_extractor_mobile.dart` 还是 stub），点了必失败；
/// - Web：需要 transformers.js 的 JS bridge，同样是 stub。
///
/// 2026-11-11 实机：在 HONOR 70 上打开「AI 字幕生成」设置页，
/// 页面自己就写着「移动端离线识别需要本地 ffmpeg 抽音（ffmpeg-kit），
/// 尚未接入」。所以字幕面板不能再承诺「下载模型后自动生成」。
/// 纯函数，便于单测，也避免设置页与播放页两处判断不一致。
enum SubtitleAiOfflineSupport {
  /// 桌面端：选模型下载后即可离线识别。
  ready,

  /// 移动端缺 ffmpeg runner。
  mobileFfmpegMissing,

  /// Web 端缺 transformers.js bridge。
  webBridgeMissing,
}

SubtitleAiOfflineSupport offlineSubtitleSupport({TargetPlatform? platform}) {
  if (kIsWeb) return SubtitleAiOfflineSupport.webBridgeMissing;
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return SubtitleAiOfflineSupport.mobileFfmpegMissing;
    default:
      return SubtitleAiOfflineSupport.ready;
  }
}

bool isOfflineSubtitleRunnable({TargetPlatform? platform}) =>
    offlineSubtitleSupport(platform: platform) ==
    SubtitleAiOfflineSupport.ready;

String offlineSubtitleUnavailableReason(SubtitleAiOfflineSupport support) {
  switch (support) {
    case SubtitleAiOfflineSupport.mobileFfmpegMissing:
      return '移动端离线识别需要本地 ffmpeg 抽音（ffmpeg-kit），当前尚未接入；'
          '请在桌面端使用，或改用「在线 API」。';
    case SubtitleAiOfflineSupport.webBridgeMissing:
      return '浏览器端离线识别需要 transformers.js 桥接，当前尚未接入；'
          '请改用「在线 API」或使用桌面端。';
    case SubtitleAiOfflineSupport.ready:
      return '';
  }
}
