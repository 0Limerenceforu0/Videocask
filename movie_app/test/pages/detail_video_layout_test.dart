import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/detail_video_layout.dart';

void main() {
  group('DetailVideoLayout.nativeAspectRatio', () {
    test('uses stream dimensions when available', () {
      expect(
        DetailVideoLayout.nativeAspectRatio(
          videoWidth: 640,
          videoHeight: 480,
        ),
        4 / 3,
      );
    });

    test('falls back to mode then 16:9', () {
      expect(
        DetailVideoLayout.nativeAspectRatio(aspectRatioMode: 4 / 3),
        4 / 3,
      );
      expect(DetailVideoLayout.nativeAspectRatio(), closeTo(16 / 9, 0.001));
    });
  });

  group('DetailVideoLayout.shouldLetterbox', () {
    test('fullscreen uses native contain, not manual letterbox', () {
      expect(
        DetailVideoLayout.shouldLetterbox(
          isFullScreen: true,
          aspectRatioMode: 16 / 9,
        ),
        isFalse,
      );
      expect(
        DetailVideoLayout.shouldLetterbox(
          isFullScreen: true,
          aspectRatioMode: 16 / 9,
          cropFill: true,
        ),
        isFalse,
      );
    });

    test('original aspect mode letterboxes when embedded', () {
      expect(
        DetailVideoLayout.shouldLetterbox(
          isFullScreen: false,
          aspectRatioMode: 0,
        ),
        isTrue,
      );
    });

    test('letterbox for portrait video in embedded player', () {
      expect(
        DetailVideoLayout.shouldLetterbox(
          isFullScreen: false,
          aspectRatioMode: 16 / 9,
          videoWidth: 1080,
          videoHeight: 1920,
        ),
        isTrue,
      );
      expect(
        DetailVideoLayout.shouldLetterbox(
          isFullScreen: false,
          aspectRatioMode: 16 / 9,
          videoWidth: 1920,
          videoHeight: 1080,
        ),
        isFalse,
      );
    });
  });

  group('DetailVideoLayout.detailPlayerSlotHeight', () {
    test('portrait video uses taller slot than landscape 16:9', () {
      const width = 400.0;
      const max = 800.0;
      final landscape = DetailVideoLayout.detailPlayerSlotHeight(
        columnWidth: width,
        maxHeight: max,
        videoWidth: 1920,
        videoHeight: 1080,
      );
      final portrait = DetailVideoLayout.detailPlayerSlotHeight(
        columnWidth: width,
        maxHeight: max,
        videoWidth: 1080,
        videoHeight: 1920,
      );
      expect(portrait, greaterThan(landscape));
      expect(landscape, closeTo(width * 9 / 16, 0.5));
      expect(portrait, closeTo(width * 16 / 9, 0.5));
    });

    test('clamps to maxHeight', () {
      expect(
        DetailVideoLayout.detailPlayerSlotHeight(
          columnWidth: 360,
          maxHeight: 300,
          videoWidth: 1080,
          videoHeight: 1920,
        ),
        300,
      );
    });
  });

  group('DetailVideoLayout.androidPortraitDetailPlayerHeight', () {
    test('returns half screen for portrait video', () {
      expect(
        DetailVideoLayout.androidPortraitDetailPlayerHeight(
          screenHeight: 800,
          videoWidth: 1080,
          videoHeight: 1920,
        ),
        400,
      );
    });

    test('returns null for landscape video', () {
      expect(
        DetailVideoLayout.androidPortraitDetailPlayerHeight(
          screenHeight: 800,
          videoWidth: 1920,
          videoHeight: 1080,
        ),
        isNull,
      );
    });
  });

  group('DetailVideoLayout.formatPlaybackDuration', () {
    test('formats under one hour', () {
      expect(
        DetailVideoLayout.formatPlaybackDuration(
          const Duration(minutes: 5, seconds: 7),
        ),
        '5:07',
      );
    });

    test('formats with hours', () {
      expect(
        DetailVideoLayout.formatPlaybackDuration(
          const Duration(hours: 1, minutes: 5, seconds: 7),
        ),
        '1:05:07',
      );
    });
  });

  group('DetailVideoLayout.formatSeekBubbleSeconds', () {
    test('shows signed seconds', () {
      expect(DetailVideoLayout.formatSeekBubbleSeconds(12), '+12s');
      expect(DetailVideoLayout.formatSeekBubbleSeconds(-8), '-8s');
      expect(DetailVideoLayout.formatSeekBubbleSeconds(0), '0s');
    });
  });

  group('DetailVideoLayout.seekDragVelocityFactor', () {
    test('slow drag keeps base precision', () {
      expect(DetailVideoLayout.seekDragVelocityFactor(0), 1.0);
      expect(DetailVideoLayout.seekDragVelocityFactor(80), 1.0);
      expect(
        DetailVideoLayout.seekDragVelocityFactor(
          DetailVideoLayout.seekSlowDragVelocity,
        ),
        1.0,
      );
    });

    test('fast swipe boosts toward the ceiling', () {
      expect(
        DetailVideoLayout.seekDragVelocityFactor(
          DetailVideoLayout.seekFastDragVelocity,
        ),
        DetailVideoLayout.seekFastDragBoost,
      );
      // 超过快扫阈值后保持增益到顶，不继续涨
      expect(
        DetailVideoLayout.seekDragVelocityFactor(99999),
        DetailVideoLayout.seekFastDragBoost,
      );
    });

    test('monotonically increasing between thresholds', () {
      double? prev;
      for (var v = 100.0; v <= 1500; v += 100) {
        final f = DetailVideoLayout.seekDragVelocityFactor(v);
        expect(f, inInclusiveRange(1.0, DetailVideoLayout.seekFastDragBoost));
        if (prev != null) expect(f, greaterThanOrEqualTo(prev));
        prev = f;
      }
    });

    test('NaN and negative treated as slow drag', () {
      expect(DetailVideoLayout.seekDragVelocityFactor(double.nan), 1.0);
      expect(DetailVideoLayout.seekDragVelocityFactor(-5), 1.0);
    });
  });

  group('DetailVideoLayout.smoothSeekDragVelocity', () {
    test('blends new sample with configured weight', () {
      final v = DetailVideoLayout.smoothSeekDragVelocity(
        previous: 1000,
        instant: 0,
      );
      // 0.65 * 1000 + 0.35 * 0
      expect(v, closeTo(650, 0.001));
    });

    test('caps absurd single-frame velocity', () {
      final v = DetailVideoLayout.smoothSeekDragVelocity(
        previous: 0,
        instant: 999999,
      );
      expect(
        v,
        closeTo(DetailVideoLayout.seekInstantVelocityCap * 0.35, 0.001),
      );
    });

    test('NaN sample treated as zero', () {
      final v = DetailVideoLayout.smoothSeekDragVelocity(
        previous: 400,
        instant: double.nan,
      );
      expect(v, closeTo(260, 0.001));
    });
  });

  group('DetailVideoLayout.nextSeekDragSeconds', () {
    // 慢拖满屏约 90s：半屏（180px/360px）≈ 45s
    test('slow drag maps screen width to full-width seconds', () {
      final total = DetailVideoLayout.nextSeekDragSeconds(
        dx: 180,
        smoothedVelocity: 0,
        screenWidth: 360,
        currentTotalSeconds: 0,
        positionSeconds: 600,
        durationSeconds: 3600,
      );
      expect(total, closeTo(45, 0.001));
    });

    // 2026-10-19 方向修正：同样距离，快扫要比慢拖跳得更多（手速增益）
    test('fast swipe on same distance boosts, not damps', () {
      final slow = DetailVideoLayout.nextSeekDragSeconds(
        dx: 180,
        smoothedVelocity: 0,
        screenWidth: 360,
        currentTotalSeconds: 0,
        positionSeconds: 600,
        durationSeconds: 3600,
      );
      final fast = DetailVideoLayout.nextSeekDragSeconds(
        dx: 180,
        smoothedVelocity: 5000,
        screenWidth: 360,
        currentTotalSeconds: 0,
        positionSeconds: 600,
        durationSeconds: 3600,
      );
      // 45s * 6 倍增益 = 270s，未触 300s 封顶
      expect(fast, closeTo(slow * DetailVideoLayout.seekFastDragBoost, 0.001));
      expect(fast, greaterThan(slow));
    });

    // 快扫满屏：540s 增益量被单次封顶夹到 ±300s
    test('fast swipe full screen is capped at max total', () {
      final total = DetailVideoLayout.nextSeekDragSeconds(
        dx: 360,
        smoothedVelocity: 5000,
        screenWidth: 360,
        currentTotalSeconds: 0,
        positionSeconds: 600,
        durationSeconds: 3600,
      );
      expect(total, DetailVideoLayout.seekMaxTotalSeconds);
    });

    test('accumulates across updates and caps at max total', () {
      var total = 0.0;
      for (var i = 0; i < 20; i++) {
        total = DetailVideoLayout.nextSeekDragSeconds(
          dx: 30,
          smoothedVelocity: 0,
          screenWidth: 360,
          currentTotalSeconds: total,
          positionSeconds: 600,
          durationSeconds: 3600,
        );
      }
      // 20 * 30px = 600px ≈ 1.67 个满屏 → 慢拖本应 150s，未触顶
      expect(total, closeTo(90 * 600 / 360, 0.001));
      for (var i = 0; i < 50; i++) {
        total = DetailVideoLayout.nextSeekDragSeconds(
          dx: 60,
          smoothedVelocity: 0,
          screenWidth: 360,
          currentTotalSeconds: total,
          positionSeconds: 600,
          durationSeconds: 3600,
        );
      }
      expect(total, DetailVideoLayout.seekMaxTotalSeconds);
    });

    test('clamps to not pass start or end of the movie', () {
      // 距片尾只剩 30s：往前拖一个满屏也只到 30s
      final toEnd = DetailVideoLayout.nextSeekDragSeconds(
        dx: 360,
        smoothedVelocity: 0,
        screenWidth: 360,
        currentTotalSeconds: 0,
        positionSeconds: 3570,
        durationSeconds: 3600,
      );
      expect(toEnd, closeTo(30, 0.001));

      // 距片头只剩 10s：往后拖满屏也只到 -10s
      final toStart = DetailVideoLayout.nextSeekDragSeconds(
        dx: -360,
        smoothedVelocity: 0,
        screenWidth: 360,
        currentTotalSeconds: 0,
        positionSeconds: 10,
        durationSeconds: 3600,
      );
      expect(toStart, closeTo(-10, 0.001));
    });

    test('degenerate inputs keep previous total', () {
      expect(
        DetailVideoLayout.nextSeekDragSeconds(
          dx: 100,
          smoothedVelocity: 0,
          screenWidth: 0,
          currentTotalSeconds: 12,
          positionSeconds: 600,
          durationSeconds: 3600,
        ),
        12,
      );
      expect(
        DetailVideoLayout.nextSeekDragSeconds(
          dx: 100,
          smoothedVelocity: 0,
          screenWidth: 360,
          currentTotalSeconds: 12,
          positionSeconds: 600,
          durationSeconds: 0,
        ),
        12,
      );
      expect(
        DetailVideoLayout.nextSeekDragSeconds(
          dx: double.nan,
          smoothedVelocity: 0,
          screenWidth: 360,
          currentTotalSeconds: 12,
          positionSeconds: 600,
          durationSeconds: 3600,
        ),
        12,
      );
    });

    test('negative drag seeks backward', () {
      final total = DetailVideoLayout.nextSeekDragSeconds(
        dx: -180,
        smoothedVelocity: 0,
        screenWidth: 360,
        currentTotalSeconds: 0,
        positionSeconds: 600,
        durationSeconds: 3600,
      );
      expect(total, closeTo(-45, 0.001));
    });
  });

  group('DetailVideoLayout.normalizeVideoSize', () {
    test('swaps dimensions for 90 degree rotation', () {
      final n = DetailVideoLayout.normalizeVideoSize(
        videoWidth: 1920,
        videoHeight: 1080,
        rotate: 90,
      );
      expect(n.width, 1080);
      expect(n.height, 1920);
      expect(
        DetailVideoLayout.isPortraitVideo(
          videoWidth: 1920,
          videoHeight: 1080,
          rotate: 90,
        ),
        isTrue,
      );
      expect(
        DetailVideoLayout.isPortraitVideo(
          videoWidth: 1920,
          videoHeight: 1080,
          rotate: 0,
        ),
        isFalse,
      );
    });
  });

  group('DetailVideoLayout.layoutAspectRatio', () {
    test('swaps inverted dimensions in landscape fullscreen viewport', () {
      expect(
        DetailVideoLayout.layoutAspectRatio(
          viewportWidth: 800,
          viewportHeight: 400,
          videoWidth: 1080,
          videoHeight: 1920,
          isFullScreen: true,
        ),
        closeTo(16 / 9, 0.01),
      );
    });

    test('keeps portrait ratio in portrait viewport', () {
      expect(
        DetailVideoLayout.layoutAspectRatio(
          viewportWidth: 400,
          viewportHeight: 800,
          videoWidth: 1080,
          videoHeight: 1920,
          isFullScreen: true,
        ),
        closeTo(9 / 16, 0.01),
      );
    });
  });

  group('DetailVideoLayout.isConfidentPortraitVideo', () {
    test('landscape 16:9 is not confident portrait', () {
      expect(
        DetailVideoLayout.isConfidentPortraitVideo(
          videoWidth: 1920,
          videoHeight: 1080,
        ),
        isFalse,
      );
    });

    test('portrait 9:16 is confident portrait', () {
      expect(
        DetailVideoLayout.isConfidentPortraitVideo(
          videoWidth: 1080,
          videoHeight: 1920,
        ),
        isTrue,
      );
    });

    test('90 degree rotate swaps to landscape', () {
      expect(
        DetailVideoLayout.isConfidentPortraitVideo(
          videoWidth: 1080,
          videoHeight: 1920,
          rotate: 90,
        ),
        isFalse,
      );
    });
  });

  group('DetailVideoLayout.preferredOrientations', () {
    test('non-fullscreen is portrait only', () {
      expect(
        DetailVideoLayout.preferredOrientations(isFullScreen: false),
        DetailVideoLayout.portraitOrientations,
      );
    });

    test('fullscreen portrait video stays portrait only', () {
      expect(
        DetailVideoLayout.preferredOrientations(
          isFullScreen: true,
          videoWidth: 1080,
          videoHeight: 1920,
        ),
        DetailVideoLayout.portraitOrientations,
      );
    });

    test('fullscreen landscape video allows all orientations', () {
      expect(
        DetailVideoLayout.preferredOrientations(
          isFullScreen: true,
          videoWidth: 1920,
          videoHeight: 1080,
        ),
        DetailVideoLayout.allOrientations,
      );
      expect(
        DetailVideoLayout.preferredOrientations(
          isFullScreen: true,
          videoWidth: 1920,
          videoHeight: 1080,
        ),
        contains(DeviceOrientation.landscapeLeft),
      );
    });
  });
}
