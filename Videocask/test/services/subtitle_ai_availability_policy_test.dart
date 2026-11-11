import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/subtitle_ai_availability_policy.dart';

void main() {
  test('Android / iOS 明确判为缺本地 ffmpeg runner，不能承诺离线生成', () {
    for (final p in <TargetPlatform>[TargetPlatform.android, TargetPlatform.iOS]) {
      expect(
        offlineSubtitleSupport(platform: p),
        SubtitleAiOfflineSupport.mobileFfmpegMissing,
      );
      expect(isOfflineSubtitleRunnable(platform: p), isFalse);
      expect(
        offlineSubtitleUnavailableReason(offlineSubtitleSupport(platform: p)),
        contains('ffmpeg'),
      );
    }
  });

  test('桌面端判据为可用，可以引导下载模型', () {
    for (final p in <TargetPlatform>[
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ]) {
      expect(
        offlineSubtitleSupport(platform: p),
        SubtitleAiOfflineSupport.ready,
      );
      expect(isOfflineSubtitleRunnable(platform: p), isTrue);
      expect(
        offlineSubtitleUnavailableReason(offlineSubtitleSupport(platform: p)),
        isEmpty,
      );
    }
  });

  test('Web 桥接缺失有独立说明', () {
    const s = SubtitleAiOfflineSupport.webBridgeMissing;
    expect(offlineSubtitleUnavailableReason(s), contains('transformers.js'));
  });
}
