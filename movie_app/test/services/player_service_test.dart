import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/playback_strategy.dart';
import 'package:movie_app/services/player_service.dart';

void main() {
  late PlayerService playerService;

  setUp(() {
    playerService = PlayerService();
  });

  tearDown(() async {
    // 只释放实例、不 dispose 单例（与生产代码详情页关闭路径一致：
    // dispose 会让单例永久死亡，拖累同文件后续用例）。
    try {
      await playerService.releasePlayerInstance();
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

    test('事件通道：可注册多播监听器，且互不覆盖', () {
      final a = <bool>[];
      final b = <bool>[];
      playerService.playingChanged.add(a.add);
      playerService.playingChanged.add(b.add);
      playerService.positionChanged.add((_) {});
      playerService.durationChanged.add((_) {});
      playerService.bufferingChanged.add((_) {});
      playerService.bufferChanged.add((_) {});
      playerService.completed.add((_) {});
      playerService.error.add((_) {});

      // 验证监听器已注册（多播：多个消费者并存）
      expect(playerService.playingChanged.listenerCount, 2);
      expect(playerService.positionChanged.hasListeners, isTrue);
      expect(playerService.durationChanged.hasListeners, isTrue);
      expect(playerService.bufferingChanged.hasListeners, isTrue);
      expect(playerService.bufferChanged.hasListeners, isTrue);
      expect(playerService.completed.hasListeners, isTrue);
      expect(playerService.error.hasListeners, isTrue);

      // 广播后两个消费者都收到（不会被覆盖）
      playerService.playingChanged.emit(true);
      expect(a, [true]);
      expect(b, [true]);
    });

    test('事件通道：注销后不再收到事件', () {
      final seen = <bool>[];
      void handler(bool v) => seen.add(v);
      playerService.playingChanged.add(handler);

      playerService.playingChanged.emit(true);
      playerService.playingChanged.remove(handler);
      playerService.playingChanged.emit(false);

      expect(seen, [true]);
    });

    test('事件通道：模拟播放器重建后订阅依然有效（不冻结）', () {
      final seen = <Duration>[];
      playerService.positionChanged.add(seen.add);

      // 重建前的一轮
      playerService.positionChanged.emit(const Duration(seconds: 1));
      // 重建后（通道不重建）继续有事件
      playerService.positionChanged.emit(const Duration(seconds: 2));

      expect(seen, [const Duration(seconds: 1), const Duration(seconds: 2)]);
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
      expect(
        playerService.strategyConfig.demuxerBufferBytes,
        PlaybackStrategyConfig.fromKey('balanced').demuxerBufferBytes,
      );
    });
  });

  // ========== 单例存亡契约（2026-10-20 回归）==========
  //
  // 背景：详情页旧实现 `_releasePlayerResources()` 对**单例**调了
  // `playerService.dispose()`，而 `_disposed` 无任何复位路径——关掉第一个
  // 详情页后播放器单例即死亡，再打开任何视频都静默不播。
  // 契约：页面级关闭只调 `releasePlayerInstance()`（实例级释放）；
  // `dispose()` 只归应用退出路径，且一经调用服务即不可用。
  group('单例存亡契约', () {
    test('releasePlayerInstance 只释放实例，服务保持可用', () async {
      await playerService.releasePlayerInstance();
      expect(playerService.isDisposed, isFalse,
          reason: '实例级释放不得把单例标记为已销毁');
      expect(playerService.player, isNull);
      expect(playerService.videoController, isNull);
    });

    test('stop + releasePlayerInstance 组合（详情页关闭路径）不炸', () async {
      await playerService.stop();
      await playerService.releasePlayerInstance();
      expect(playerService.isDisposed, isFalse);
    });

    test('dispose 之后服务永久不可用（文档化单例语义）', () async {
      await playerService.dispose();
      expect(playerService.isDisposed, isTrue);
      // 与详情页关闭时等价的一组操作，不得让服务复活
      await playerService.releasePlayerInstance();
      expect(playerService.isDisposed, isTrue);
    });
  });

  // 🔴 FD 泄漏修复锁死（2026-10-23 荣耀70真机实测后固化）。
  //
  // 背景：media_kit 默认 SurfaceProducer 路径，Adreno GL 驱动每次
  // eglSwapBuffers 建一个 sync_file fence，Flutter 引擎 ImageReader
  // 消费侧不关它 → 每送显一帧漏 1 个 fd（实测 +22~24/s ≈ 帧率），
  // 单次连续播放约 24 分钟耗尽 RLIMIT_NOFILE(32768) → SIGSEGV。
  // 修复：Android 走 SurfaceTexture 老路径（GLConsumer 按帧消费，
  // fence 随 BufferQueue 回收），真机 5 分钟 31 点采样斜率 +0.000/s。
  //
  // 本组是「防回退护栏」：修复只有一行配置，任何人手滑改回默认值
  // （或删参数使默认 true 生效）都会静默复活泄漏——必须红。
  // 负向验证记录：将 false 改 true 后本组两条用例均红（2026-10-23）。
  group('FD 泄漏修复锁死（SurfaceTexture 路径）', () {
    test('Android 配置必须禁用 SurfaceProducer', () {
      final config = androidVideoControllerConfig(
        vo: 'gpu',
        hwdec: 'mediacodec',
      );
      expect(
        config.enableAndroidSurfaceProducer,
        isFalse,
        reason: 'SurfaceProducer 消费侧不关 Adreno 每帧 fence，'
            '每帧漏 1 个 sync_file fd，24 分钟耗尽崩溃',
      );
    });

    test('vo / hwdec 必须透传（防档位被配置层静默覆盖）', () {
      final config = androidVideoControllerConfig(
        vo: 'gpu-next',
        hwdec: 'no',
      );
      expect(config.vo, 'gpu-next',
          reason: 'vo 不透传 = 用户选的视频输出档位失效');
      expect(config.hwdec, 'no',
          reason: 'hwdec 不透传 = 用户选的硬解档位失效');
    });
  });
}
