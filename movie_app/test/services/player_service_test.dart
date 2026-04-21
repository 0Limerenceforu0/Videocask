import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/player_service.dart';

void main() {
  late PlayerService playerService;

  setUp(() {
    playerService = PlayerService();
  });

  tearDown(() async {
    // 尝试释放播放器，但不抛出异常
    try {
      await playerService.dispose();
    } catch (e) {
      // 忽略释放时的异常
    }
  });

  group('PlayerService', () {
    test('检查是否支持播放', () {
      expect(PlayerService.isSupported, isTrue);
    });

    test('设置自动播放下一集', () async {
      await playerService.setAutoPlayNext(false);
      expect(playerService.autoPlayNext, isFalse);

      await playerService.setAutoPlayNext(true);
      expect(playerService.autoPlayNext, isTrue);
    });

    test('回调函数设置', () {
      playerService.onPlayingChanged = (_) {};
      playerService.onPositionChanged = (_) {};
      playerService.onDurationChanged = (_) {};
      playerService.onBufferingChanged = (_) {};
      playerService.onBufferChanged = (_) {};
      playerService.onCompleted = () {};
      playerService.onError = (_) {};

      // 验证回调函数已设置
      expect(playerService.onPlayingChanged, isNotNull);
      expect(playerService.onPositionChanged, isNotNull);
      expect(playerService.onDurationChanged, isNotNull);
      expect(playerService.onBufferingChanged, isNotNull);
      expect(playerService.onBufferChanged, isNotNull);
      expect(playerService.onCompleted, isNotNull);
      expect(playerService.onError, isNotNull);
    });

    test('亮度和全屏方法不抛出异常', () {
      expect(() => playerService.setBrightness(0.5), returnsNormally);
      expect(() => playerService.enterFullScreen(), returnsNormally);
      expect(() => playerService.exitFullScreen(), returnsNormally);
    });

    test('获取初始状态', () {
      expect(playerService.player, isNull);
      expect(playerService.videoController, isNull);
      expect(playerService.autoPlayNext, isTrue);
      expect(playerService.playbackSpeed, equals(1.0));
    });
  });
}
