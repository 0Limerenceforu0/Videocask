import 'package:flutter/services.dart';

/// 详情页播放器画面布局（可单测）。
class DetailVideoLayout {
  DetailVideoLayout._();

  static const double cropFillMarker = 999 / 999;

  static const double _defaultLandscapeAspect = 16 / 9;

  /// 片源分辨率已知时优先用真实宽高比；否则退回用户选项或 16:9。
  static double nativeAspectRatio({
    int? videoWidth,
    int? videoHeight,
    double aspectRatioMode = 16 / 9,
  }) {
    if (videoWidth != null &&
        videoHeight != null &&
        videoWidth > 0 &&
        videoHeight > 0) {
      return videoWidth / videoHeight;
    }
    if (aspectRatioMode > 0 && aspectRatioMode < 10) {
      return aspectRatioMode;
    }
    return _defaultLandscapeAspect;
  }

  static const List<DeviceOrientation> portraitOrientations = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ];

  static const List<DeviceOrientation> landscapeOrientations = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  static const List<DeviceOrientation> allOrientations = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    ...landscapeOrientations,
  ];

  /// 按 mpv 旋转元数据归一化片源宽高（90°/270° 时交换）。
  static ({int width, int height}) normalizeVideoSize({
    required int? videoWidth,
    required int? videoHeight,
    int rotate = 0,
  }) {
    if (videoWidth == null ||
        videoHeight == null ||
        videoWidth <= 0 ||
        videoHeight <= 0) {
      return (width: 0, height: 0);
    }
    var w = videoWidth;
    var h = videoHeight;
    final r = ((rotate % 360) + 360) % 360;
    if (r == 90 || r == 270) {
      final t = w;
      w = h;
      h = t;
    }
    return (width: w, height: h);
  }

  /// 竖屏片源（高大于宽）。
  static bool isPortraitVideo({
    int? videoWidth,
    int? videoHeight,
    int rotate = 0,
  }) {
    final n = normalizeVideoSize(
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      rotate: rotate,
    );
    if (n.width <= 0 || n.height <= 0) return false;
    return n.height > n.width;
  }

  /// 系统旋转决策用：明显竖屏（避免横屏片源元数据未就绪时误锁竖屏）。
  static bool isConfidentPortraitVideo({
    int? videoWidth,
    int? videoHeight,
    int rotate = 0,
  }) {
    final n = normalizeVideoSize(
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      rotate: rotate,
    );
    if (n.width <= 0 || n.height <= 0) return false;
    return n.height > n.width * 1.08;
  }

  /// 非全屏仅竖屏；全屏时竖屏片源仍仅竖屏，横屏片源允许四向旋转。
  static List<DeviceOrientation> preferredOrientations({
    required bool isFullScreen,
    int? videoWidth,
    int? videoHeight,
    int rotate = 0,
  }) {
    if (!isFullScreen) return portraitOrientations;
    if (isPortraitVideo(
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      rotate: rotate,
    )) {
      return portraitOrientations;
    }
    return allOrientations;
  }

  /// 详情页非全屏播放器区域高度：横屏默认 16:9；竖屏片源按真实比例加高（受 [maxHeight] 限制）。
  static double detailPlayerSlotHeight({
    required double columnWidth,
    required double maxHeight,
    int? videoWidth,
    int? videoHeight,
    double minHeight = 200,
  }) {
    if (columnWidth <= 0 || !columnWidth.isFinite) return minHeight;
    if (maxHeight <= 0 || !maxHeight.isFinite) return minHeight;
    final ar = nativeAspectRatio(
      videoWidth: videoWidth,
      videoHeight: videoHeight,
    );
    final ideal = columnWidth / ar;
    return ideal.clamp(minHeight, maxHeight);
  }

  /// 非全屏竖屏片源允许占用的最大高度比例（相对可用区域）。
  static double detailMaxHeightFactor({int? videoWidth, int? videoHeight}) {
    return isPortraitVideo(videoWidth: videoWidth, videoHeight: videoHeight)
        ? 0.78
        : 0.92;
  }

  /// 平台特定的 max-height factor：Web 端压扁到 ~58%，让下方简介/选集有充足空间；
  /// 安卓桌面端维持原值。
  static double detailMaxHeightFactorForPlatform({
    required bool isWeb,
    int? videoWidth,
    int? videoHeight,
  }) {
    if (isWeb) {
      // 竖屏片源在 Web 上仍需要更多纵向空间（社交短视频比例），但也收紧到 0.7
      return isPortraitVideo(videoWidth: videoWidth, videoHeight: videoHeight)
          ? 0.70
          : 0.58;
    }
    return detailMaxHeightFactor(
      videoWidth: videoWidth,
      videoHeight: videoHeight,
    );
  }

  /// Android 详情页竖屏片源：播放器区域占屏幕高度比例（非全屏）。
  static const double androidPortraitDetailScreenFactor = 0.5;

  /// Android 详情页竖屏片源固定槽高；非竖屏或未指定屏高时返回 null。
  static double? androidPortraitDetailPlayerHeight({
    required double screenHeight,
    int? videoWidth,
    int? videoHeight,
  }) {
    if (screenHeight <= 0 || !screenHeight.isFinite) return null;
    if (!isPortraitVideo(videoWidth: videoWidth, videoHeight: videoHeight)) {
      return null;
    }
    return screenHeight * androidPortraitDetailScreenFactor;
  }

  /// 播放器时间文案：`m:ss` 或 `h:mm:ss`。
  static String formatPlaybackDuration(Duration duration) {
    if (duration.isNegative) return '0:00';
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String formatSeekBubbleSeconds(int seconds) {
    if (seconds == 0) return '0s';
    return seconds > 0 ? '+${seconds}s' : '${seconds}s';
  }

  /// 全屏或「原始比例」、竖屏嵌入模式下按片源比例完整显示（留黑边）。
  static bool shouldLetterbox({
    required bool isFullScreen,
    required double aspectRatioMode,
    bool cropFill = false,
    int? videoWidth,
    int? videoHeight,
    int rotate = 0,
  }) {
    if (cropFill) return false;
    if (isFullScreen) return false;
    if (aspectRatioMode == 0) return true;
    if (isPortraitVideo(
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      rotate: rotate,
    )) {
      return true;
    }
    return false;
  }

  /// 布局用宽高比：全屏横屏视口下若片源上报 h>w，多为旋转元数据未体现在尺寸上，按横屏处理。
  static double layoutAspectRatio({
    required double viewportWidth,
    required double viewportHeight,
    int? videoWidth,
    int? videoHeight,
    double aspectRatioMode = 16 / 9,
    bool isFullScreen = false,
    int rotate = 0,
  }) {
    final n = normalizeVideoSize(
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      rotate: rotate,
    );
    if (n.width > 0 && n.height > 0) {
      var w = n.width;
      var h = n.height;
      final viewportLandscape = viewportWidth > viewportHeight;
      if (isFullScreen && viewportLandscape && h > w) {
        final t = w;
        w = h;
        h = t;
      }
      return w / h;
    }
    return nativeAspectRatio(
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      aspectRatioMode: aspectRatioMode,
    );
  }
}
