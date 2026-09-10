import 'dart:async' show Timer, unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'detail_player.dart';
import 'detail_video_layout.dart';

/// 详情全屏时的移动端方向控制（从 [DetailPage] 抽离）。
class DetailFullscreenOrientationController {
  bool androidLandscapeLocked = false;
  Timer? _debounce;

  void dispose() {
    _debounce?.cancel();
    _debounce = null;
  }

  Future<void> applyMobileNonFullscreen({
    required bool isMobilePlatform,
    required List<DeviceOrientation> portraitOrientations,
  }) async {
    if (!isMobilePlatform || kIsWeb) return;
    await SystemChrome.setPreferredOrientations(portraitOrientations);
  }

  Future<void> applyMobileFullscreen({
    required bool isMobilePlatform,
    required bool isAndroidPlatform,
    required DetailPlayer player,
    required bool Function() isMounted,
  }) async {
    if (!isMobilePlatform || !player.isFullScreen || kIsWeb) return;

    final portraitVideo = DetailVideoLayout.isConfidentPortraitVideo(
      videoWidth: player.videoWidth,
      videoHeight: player.videoHeight,
      rotate: player.videoRotate,
    );

    if (portraitVideo) {
      androidLandscapeLocked = false;
      await SystemChrome.setPreferredOrientations(
        DetailVideoLayout.portraitOrientations,
      );
      return;
    }

    if (isAndroidPlatform) {
      androidLandscapeLocked = true;
      await SystemChrome.setPreferredOrientations(
        DetailVideoLayout.landscapeOrientations,
      );
      return;
    }

    // iOS：先切横屏，再开放四向（含反向横屏）
    androidLandscapeLocked = false;
    await SystemChrome.setPreferredOrientations(
      DetailVideoLayout.landscapeOrientations,
    );
    if (!isMounted()) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!isMounted() || !player.isFullScreen) return;
    await SystemChrome.setPreferredOrientations(
      DetailVideoLayout.preferredOrientations(
        isFullScreen: true,
        videoWidth: player.videoWidth,
        videoHeight: player.videoHeight,
        rotate: player.videoRotate,
      ),
    );
  }

  void scheduleMobileSync({
    required bool isMobilePlatform,
    required bool isAndroidPlatform,
    required DetailPlayer player,
    required bool Function() isMounted,
  }) {
    if (!isMobilePlatform || !player.isFullScreen || kIsWeb) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!isMounted() || !player.isFullScreen) return;
      unawaited(
        applyMobileFullscreen(
          isMobilePlatform: isMobilePlatform,
          isAndroidPlatform: isAndroidPlatform,
          player: player,
          isMounted: isMounted,
        ),
      );
    });
  }

  void resetAndroidLock() {
    androidLandscapeLocked = false;
  }

  void cancelScheduledSync() {
    _debounce?.cancel();
    _debounce = null;
  }
}
