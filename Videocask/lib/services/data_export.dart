import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'download_export.dart';

/// 把文本数据写到系统「下载」目录。
///
/// Android 复用诊断日志那条原生通道（`guanzi/logExport`）的 MediaStore 写入实现：
/// 免存储权限、任意文件管理器都能取到；桌面端没有该通道，由 [DownloadExport]
/// 直接写下载目录。Web 端抛 [UnsupportedError]，由调用方降级到剪贴板。
abstract final class DataExport {
  static String _timeStamp() {
    final d = DateTime.now();
    String p(int n) => n < 10 ? '0$n' : '$n';
    return '${d.year}${p(d.month)}${p(d.day)}_${p(d.hour)}${p(d.minute)}${p(d.second)}';
  }

  static String backupFileName() => 'guanzi_backup_${_timeStamp()}.json';

  /// 返回用户可见的目标路径描述。Web 端没有文件系统，抛
  /// [UnsupportedError]，由调用方降级到剪贴板。
  static Future<String> exportText({
    required String name,
    required String content,
    String mimeType = 'application/json',
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Web 端请使用剪贴板导出');
    }
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}${Platform.pathSeparator}$name')
      ..writeAsStringSync(content);
    try {
      return await DownloadExport.write(
        sourcePath: file.path,
        name: name,
        mimeType: mimeType,
      );
    } finally {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }
}
