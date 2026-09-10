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
