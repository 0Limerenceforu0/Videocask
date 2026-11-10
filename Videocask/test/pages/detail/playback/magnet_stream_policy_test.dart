import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/magnet_stream_policy.dart';

/// 4078 真机回归：磁力会话漏判 → 软重载重开流 → 误报完成 → 纠偏 seek 到片长。
void main() {
  group('isMagnetStreamSession', () {
    test('伪地址 magnet-file:// 直接命中', () {
      expect(
        isMagnetStreamSession(
          currentPlayUrl: 'magnet-file://0',
          activeStreamUrl: 'http://127.0.0.1:45123/0',
          hasMagnetSession: true,
        ),
        isTrue,
      );
    });

    test('currentPlayUrl 被覆写成 streamUrl 后仍能靠本地回环流识别', () {
      expect(
        isMagnetStreamSession(
          currentPlayUrl: 'http://127.0.0.1:45123/0',
          activeStreamUrl: 'http://127.0.0.1:45123/0',
          hasMagnetSession: true,
        ),
        isTrue,
      );
    });

    test('localhost 形式也算本地回环流', () {
      expect(
        isMagnetStreamSession(
          currentPlayUrl: null,
          activeStreamUrl: 'http://localhost:8080/stream',
          hasMagnetSession: true,
        ),
        isTrue,
      );
    });

    test('同一页面切到在线源后不误判', () {
      // lastMagnetUri 只在 releasePlayerInstance 清，切在线源时仍非空；
      // 但 activeStreamUrl 变成远端地址，必须判 false。
      expect(
        isMagnetStreamSession(
          currentPlayUrl: 'https://cdn.example.com/a.m3u8',
          activeStreamUrl: 'https://cdn.example.com/a.m3u8',
          hasMagnetSession: true,
        ),
        isFalse,
      );
    });

    test('没有磁力会话标记且地址为空时 false', () {
      expect(
        isMagnetStreamSession(
          currentPlayUrl: null,
          activeStreamUrl: null,
          hasMagnetSession: false,
        ),
        isFalse,
      );
    });
  });

  group('isValidRecoverySeekTarget', () {
    test('正常中途位置允许纠偏', () {
      expect(
        isValidRecoverySeekTarget(
          target: const Duration(seconds: 2944),
          duration: const Duration(seconds: 7507),
        ),
        isTrue,
      );
    });

    test('目标等于片长必须拒绝（4078 致命 bug）', () {
      expect(
        isValidRecoverySeekTarget(
          target: const Duration(seconds: 7507),
          duration: const Duration(seconds: 7507),
        ),
        isFalse,
      );
    });

    test('片尾 10s 内一律拒绝', () {
      expect(
        isValidRecoverySeekTarget(
          target: const Duration(seconds: 7500),
          duration: const Duration(seconds: 7507),
        ),
        isFalse,
      );
    });

    test('过小的目标仍按原规则拒绝', () {
      expect(
        isValidRecoverySeekTarget(
          target: const Duration(seconds: 7),
          duration: const Duration(seconds: 7507),
        ),
        isFalse,
      );
    });

    test('时长未知时不误杀有效目标', () {
      expect(
        isValidRecoverySeekTarget(
          target: const Duration(seconds: 300),
          duration: Duration.zero,
        ),
        isTrue,
      );
    });
  });

  group('shouldSkipResumeSeek', () {
    test('磁力流 3s 的小续播也必须跳过（打断顺序预取）', () {
      expect(
        shouldSkipResumeSeek(
          isMagnet: true,
          pending: const Duration(seconds: 3),
        ),
        isTrue,
      );
    });

    test('磁力流远端续播同样跳过', () {
      expect(
        shouldSkipResumeSeek(
          isMagnet: true,
          pending: const Duration(seconds: 3345),
        ),
        isTrue,
      );
    });

    test('在线流保留原有续播', () {
      expect(
        shouldSkipResumeSeek(
          isMagnet: false,
          pending: const Duration(seconds: 3),
        ),
        isFalse,
      );
    });
  });

  group('shouldIgnoreMagnetPrematureComplete', () {
    test('pos=7s / dur=7507s 的磁力误报完成必须忽略', () {
      expect(
        shouldIgnoreMagnetPrematureComplete(
          isMagnet: true,
          position: const Duration(seconds: 7),
          duration: const Duration(seconds: 7507),
        ),
        isTrue,
      );
    });

    test('真的播到片尾不忽略', () {
      expect(
        shouldIgnoreMagnetPrematureComplete(
          isMagnet: true,
          position: const Duration(seconds: 7490),
          duration: const Duration(seconds: 7507),
        ),
        isFalse,
      );
    });

    test('在线流不受影响', () {
      expect(
        shouldIgnoreMagnetPrematureComplete(
          isMagnet: false,
          position: const Duration(seconds: 7),
          duration: const Duration(seconds: 7507),
        ),
        isFalse,
      );
    });
  });
}
