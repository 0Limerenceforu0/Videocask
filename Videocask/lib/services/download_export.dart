import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 把已经生成好的文件放进「用户能直接取到」的目录。
///
/// Android 走 `videocask/logExport` 原生通道经 MediaStore 写入系统下载目录（免存储
/// 权限）；Windows / Linux / macOS / iOS 没有这条通道，改为直接写系统下载目录，
/// 拿不到下载目录时退到应用文档目录。Web 不支持写文件，由调用方降级剪贴板。
///
/// 这条分支以前漏了：`DataExport` 与 `LogExport` 都无条件调原生通道，导致桌面端
/// 点「导出数据 / 导出诊断日志」必然抛 `MissingPluginException`。
abstract final class DownloadExport {
  static const MethodChannel _channel = MethodChannel('videocask/logExport');

  /// 把 [sourcePath] 指向的临时文件导出为 [name]，返回用户可见的目标路径描述。
  /// 调用方负责在结束后清理源文件。
  static Future<String> write({
    required String sourcePath,
    required String name,
    String mimeType = 'application/octet-stream',
  }) async {
    final route = resolveDownloadExportRoute(isWeb: kIsWeb, isAndroid: _isAndroid);
    switch (route) {
      case DownloadExportRoute.unsupported:
        throw UnsupportedError('Web 端请使用剪贴板导出');
      case DownloadExportRoute.nativeMediaStore:
        final dest = await _channel.invokeMethod<String>('export', {
          'path': sourcePath,
          'name': name,
          'mime': mimeType,
        });
        return dest ?? name;
      case DownloadExportRoute.directFile:
        final dir = await _userVisibleDirectory();
        return copyIntoDirectory(
          sourcePath: sourcePath,
          name: name,
          dir: dir,
        );
    }
  }

  /// 把源文件复制进 [dir]，返回目标绝对路径。
  ///
  /// 抽出来是为了能直接单测「桌面端真的把文件写出来了」，不用依赖
  /// path_provider 在各平台的实现细节（Windows 走 FFI，channel mock 未必生效）。
  @visibleForTesting
  static Future<String> copyIntoDirectory({
    required String sourcePath,
    required String name,
    required Directory dir,
  }) async {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final target = File('${dir.path}${Platform.pathSeparator}$name');
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  static Future<Directory> _userVisibleDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } catch (_) {
      // iOS 等平台没有「下载目录」概念，继续退到应用文档目录。
    }
    return getApplicationDocumentsDirectory();
  }
}

/// 导出通道选择：抽成纯函数，方便锁住三端行为（见 download_export_test.dart）。
enum DownloadExportRoute {
  /// Web：不写文件，调用方降级剪贴板。
  unsupported,

  /// Android：走 MediaStore 原生通道，任意文件管理器都能取到。
  nativeMediaStore,

  /// 其它原生平台：直接写系统下载目录 / 应用文档目录。
  directFile,
}

DownloadExportRoute resolveDownloadExportRoute({
  required bool isWeb,
  required bool isAndroid,
}) {
  if (isWeb) return DownloadExportRoute.unsupported;
  if (isAndroid) return DownloadExportRoute.nativeMediaStore;
  return DownloadExportRoute.directFile;
}
