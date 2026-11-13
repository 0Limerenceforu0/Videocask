import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';
import 'storage_service.dart';

/// 下载文件的落盘位置（三端策略不同）。
///
/// 当前主要用于「应用更新安装包」的分发：
/// - **Android**：更新包先下载到应用私有缓存，完成后再经 `videocask/storage`
///   通道用 MediaStore 复制进公共目录 `Download/罐子`（文件管理器可见，可直接点开安装）；
///   公共目录里的文件**卸载应用后依然保留**。`publish` 方法本身也支持把其它文件
///   （如视频）发布到 `Movies/罐子`，但影视下载目前保持原有行为，不经此路径。
/// - **Windows / macOS / Linux**：用户可在设置里指定目录，未指定时用系统「下载」目录。
/// - **Web**：浏览器沙箱不允许网页指定保存路径，保存位置完全由浏览器决定；本应用
///   Web 端也不做磁力下载与应用内更新，因此不提供该设置。
abstract final class DownloadStorage {
  static const MethodChannel _channel = MethodChannel('videocask/storage');

  /// 设置项 key：桌面端自定义下载目录（绝对路径）。空串表示未设置。
  static const String overrideKey = 'download_dir_override';

  /// 公共目录下的子目录名：相册里显示为「罐子」，文件管理器里是 `Download/罐子`。
  static const String publicSubDir = '罐子';

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// 桌面端是否支持自定义目录。Web 与移动端不走这条路径。
  static bool get supportsCustomDirectory => _isDesktop;

  /// 用户设置的下载目录；未设置返回 null（Android 永远返回 null）。
  static String? savedDirectory() {
    if (!_isDesktop) return null;
    final value = StorageService().getSetting(overrideKey);
    return (value == null || value.trim().isEmpty) ? null : value.trim();
  }

  /// 保存桌面端下载目录；传 null 或空串表示恢复默认（系统「下载」目录）。
  static Future<void> setSavedDirectory(String? path) async {
    final value = path?.trim() ?? '';
    await StorageService().saveSetting(overrideKey, value);
  }

  /// 解析下载引擎实际写入的根目录。
  ///
  /// - 桌面端优先用用户指定目录，其次系统下载目录；
  /// - Android 用应用外部目录（免权限、卸载随应用删除，因此需要在下载完成后再发布）。
  static Future<Directory> resolveWorkingRoot() async {
    Directory? dir;
    final custom = savedDirectory();
    if (custom != null) {
      dir = Directory(custom);
    } else if (_isAndroid) {
      dir = await getExternalStorageDirectory();
    } else {
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {
        // iOS 等没有「下载目录」概念，继续退到文档目录。
      }
    }
    dir ??= await getApplicationDocumentsDirectory();
    final target = _isAndroid
        ? Directory('${dir.path}${Platform.pathSeparator}MagnetDownloads')
        : dir;
    if (!target.existsSync()) target.createSync(recursive: true);
    return target;
  }

  /// 把下载完成的文件发布到用户能直接找到的位置，返回可展示的目标路径。
  ///
  /// Android 会复制进公共媒体库（源文件由调用方清理）；桌面端文件本来就在用户
  /// 指定的可见目录里，直接返回原路径。
  static Future<String> publish({
    required String sourcePath,
    required String name,
    required bool isVideo,
    String? subDir,
  }) async {
    if (!_isAndroid) return sourcePath;
    try {
      final dest = await _channel.invokeMethod<String>('publishFile', {
        'path': sourcePath,
        'name': name,
        'kind': isVideo ? 'video' : 'download',
        'subDir': subDir ?? publicSubDir,
        'mimeType': guessMimeType(name),
      });
      return dest ?? name;
    } catch (e) {
      DebugLog.log('DownloadStorage', '发布到公共目录失败: $e');
      rethrow;
    }
  }

  /// 按扩展名猜 MIME：MediaStore 靠它决定归类，猜错会导致相册里不显示。
  static String guessMimeType(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'avi':
        return 'video/x-msvideo';
      case 'mov':
        return 'video/quicktime';
      case 'wmv':
        return 'video/x-ms-wmv';
      case 'flv':
        return 'video/x-flv';
      case 'ts':
      case 'm2ts':
        return 'video/mp2t';
      case 'webm':
        return 'video/webm';
      case 'rmvb':
      case 'rm':
        return 'video/vnd.rn-realvideo';
      case 'apk':
        return 'application/vnd.android.package-archive';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }
}
