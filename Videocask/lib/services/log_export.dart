import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';
import 'download_export.dart';

/// 诊断日志导出 / 清空。
///
/// 痛点：videocask_logs（含 crash_*.txt / java_crash_*.txt）位于应用私有外部目录
/// `Android/data/com.example.movie_app/files/videocask_logs`，Android 11+ 的
/// 分区存储下普通文件管理器进不去、用户既取不出也删不掉。
///
/// 解决：
/// - 导出：把整个目录打成 zip，交给原生层经 MediaStore 写入系统「下载」目录
///   （免权限、任意文件管理器可访问），返回用户可见目标路径；
/// - 清空：删除目录下除「当前正在写入的日志」以外的所有文件（应用对自身私有目录
///   有删除权，用户无权限的问题在这里绕开）。
abstract final class LogExport {
  static String _timeStamp() {
    final d = DateTime.now();
    String p(int n) => n < 10 ? '0$n' : '$n';
    return '${d.year}${p(d.month)}${p(d.day)}_${p(d.hour)}${p(d.minute)}${p(d.second)}';
  }

  /// 把 videocask_logs 目录打包并导出到系统「下载」目录。
  /// 返回用户可见的目标路径描述；失败时抛异常（调用方负责提示）。
  static Future<String> exportToDownloads() async {
    final dir = DebugLog.directory;
    if (dir == null) throw Exception('日志未初始化');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.existsSync())
        .toList();
    if (files.isEmpty) throw Exception('没有可导出的日志文件');

    // 1) 打包到临时目录（应用私有，可写）
    final tmp = await getTemporaryDirectory();
    final zipName = 'videocask_logs_${_timeStamp()}.zip';
    final zipPath = '${tmp.path}${Platform.pathSeparator}$zipName';
    final archive = Archive();
    for (final f in files) {
      final bytes = f.readAsBytesSync();
      final name = f.path.split(Platform.pathSeparator).last;
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes.isEmpty) throw Exception('打包失败');
    final zipFile = File(zipPath)..writeAsBytesSync(zipBytes);

    // 2) 落到用户可见的下载目录：Android 走 MediaStore 通道，桌面端直接写文件。
    try {
      return await DownloadExport.write(
        sourcePath: zipPath,
        name: zipName,
        mimeType: 'application/zip',
      );
    } finally {
      try {
        if (zipFile.existsSync()) zipFile.deleteSync();
      } catch (_) {}
    }
  }

  /// 清空 videocask_logs：删除除「当前正在写入的日志」以外的所有文件。
  /// 返回成功删除的文件数（应用对自身私有目录有删除权限，无需用户授权）。
  static Future<int> clearLogs() async {
    final dir = DebugLog.directory;
    if (dir == null) return 0;
    final current = DebugLog.currentFilePath;
    var count = 0;
    for (final entity in dir.listSync()) {
      if (entity is File) {
        if (entity.path == current) continue; // 不删正在写的当日日志
        try {
          entity.deleteSync();
          count++;
        } catch (_) {}
      }
    }
    return count;
  }
}
