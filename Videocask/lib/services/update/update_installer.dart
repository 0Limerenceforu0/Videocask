import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../debug_log.dart';
import 'update_policy.dart';

/// 安装失败原因（UI 据此给不同的引导文案）。
enum InstallFailure {
  /// 平台不支持自动更新（Linux / macOS / Web）。
  unsupportedPlatform,

  /// Android 没有「安装未知应用」权限。
  installPermissionDenied,

  /// 找不到可执行文件 / 解压结果异常。
  payloadInvalid,

  /// 文件系统或系统调用失败。
  ioError,
}

/// 安装结果。
class InstallResult {
  const InstallResult.success() : failure = null, message = '';
  const InstallResult.failure(this.failure, this.message);

  final InstallFailure? failure;
  final String message;

  bool get ok => failure == null;
}

/// 分平台把下载好的包落地安装。
///
/// - Android：交给系统 PackageInstaller（需要 `REQUEST_INSTALL_PACKAGES`）；
/// - Windows：绿色版 zip，解压后生成批处理，等主进程退出再覆盖并重启；
/// - Web / 其它：不支持自动安装（Web 刷新即最新）。
class UpdateInstaller {
  UpdateInstaller._();

  static const MethodChannel _channel = MethodChannel('guanzi/update');

  /// 下载目录：Android 用应用私有 cache（FileProvider 可共享，免存储权限），
  /// Windows 用临时目录（更新完即可丢弃）。
  static Future<Directory> downloadDirectory() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}guanzi_updates');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ==================== Android ====================

  /// 是否已获得「安装未知应用」权限。
  ///
  /// Android 8.0 以下没有这个开关，统一返回 true。
  static Future<bool> canInstallPackages() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('canRequestInstall');
      return result ?? false;
    } catch (e) {
      DebugLog.log('Update', '查询安装权限失败: $e');
      return false;
    }
  }

  /// 跳到系统「安装未知应用」授权页。
  static Future<bool> openInstallPermissionSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('openInstallSettings');
      return result ?? false;
    } catch (e) {
      DebugLog.log('Update', '打开安装权限设置失败: $e');
      return false;
    }
  }

  /// 调起系统安装器。
  static Future<InstallResult> installAndroidApk(String apkPath) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const InstallResult.failure(
        InstallFailure.unsupportedPlatform,
        '当前平台不支持安装 APK',
      );
    }
    try {
      final result = await _channel.invokeMethod<bool>(
        'installApk',
        {'path': apkPath},
      );
      if (result == true) return const InstallResult.success();
      return const InstallResult.failure(
        InstallFailure.installPermissionDenied,
        '没有安装权限，请先允许「安装未知应用」',
      );
    } on PlatformException catch (e) {
      DebugLog.log('Update', '调起安装器失败: ${e.code} ${e.message}');
      final code = e.code;
      if (code == 'PERMISSION_DENIED') {
        return InstallResult.failure(
          InstallFailure.installPermissionDenied,
          e.message ?? '没有安装权限',
        );
      }
      return InstallResult.failure(
        InstallFailure.ioError,
        e.message ?? '调起安装器失败',
      );
    } catch (e) {
      DebugLog.log('Update', '调起安装器异常: $e');
      return InstallResult.failure(InstallFailure.ioError, e.toString());
    }
  }

  // ==================== Windows ====================

  /// 解压 zip 并安排「退出后替换 → 重启」。
  ///
  /// 注意：调用方拿到 success 后必须尽快退出应用，批处理会等进程结束后覆盖文件。
  static Future<InstallResult> applyWindowsUpdate(String zipPath) async {
    if (kIsWeb || !Platform.isWindows) {
      return const InstallResult.failure(
        InstallFailure.unsupportedPlatform,
        '当前平台不支持自动更新',
      );
    }

    try {
      final workRoot = Directory(
        '${(await getTemporaryDirectory()).path}'
        '${Platform.pathSeparator}guanzi_update_payload',
      );
      if (await workRoot.exists()) {
        await workRoot.delete(recursive: true);
      }
      await workRoot.create(recursive: true);

      final extracted = await _extractZipSafely(
        zipPath: zipPath,
        destination: workRoot,
      );
      if (!extracted) {
        return const InstallResult.failure(
          InstallFailure.payloadInvalid,
          '更新包解压失败',
        );
      }

      // 安装目录 = 当前 exe 所在目录；解压后必须能在里面找到同名 exe。
      final exePath = Platform.resolvedExecutable;
      final installDir = File(exePath).parent.path;
      final exeName = exePath.split(Platform.pathSeparator).last;
      if (!File('${workRoot.path}${Platform.pathSeparator}$exeName').existsSync()) {
        return InstallResult.failure(
          InstallFailure.payloadInvalid,
          '更新包里没有 $exeName，请检查发布产物',
        );
      }

      final batPath =
          '${workRoot.parent.path}${Platform.pathSeparator}guanzi_apply_update.bat';
      final script = _buildWindowsApplyScript(
        payloadDir: workRoot.path,
        installDir: installDir,
        exeName: exeName,
      );
      await File(batPath).writeAsString(script, flush: true);

      DebugLog.log('Update', 'Windows 更新脚本已生成: $batPath');
      await Process.start(
        'cmd.exe',
        ['/c', batPath],
        mode: ProcessStartMode.detached,
        runInShell: false,
        workingDirectory: installDir,
      );
      return const InstallResult.success();
    } catch (e) {
      DebugLog.log('Update', 'Windows 更新失败: $e');
      return InstallResult.failure(InstallFailure.ioError, e.toString());
    }
  }

  /// 生成自替换批处理。
  ///
  /// 关键点：
  /// 1. 必须先等 `movie_app.exe` 退出——运行中的 exe 被占用，robocopy 会跳过；
  /// 2. 用 robocopy `/IS /IT` 强制覆盖同名文件（保留目录结构）；
  /// 3. 重启新版本后再删除自身，避免删除失败。
  static String _buildWindowsApplyScript({
    required String payloadDir,
    required String installDir,
    required String exeName,
  }) {
    final nl = '\r\n';
    return <String>[
      '@echo off',
      'setlocal',
      'set "SRC=$payloadDir"',
      'set "DST=$installDir"',
      'set "EXE=$exeName"',
      // 最多等 60 秒，避免进程异常残留导致永远不覆盖。
      'for /l %%i in (1,1,60) do (',
      '  tasklist /FI "IMAGENAME eq %EXE%" 2>nul | find /I "%EXE%" >nul',
      '  if errorlevel 1 goto :copy',
      '  timeout /t 1 /nobreak >nul',
      ')',
      ':copy',
      'robocopy "%SRC%" "%DST%" /E /IS /IT /NFL /NDL /NJH /NJS /NC /NS /NP >nul',
      'if errorlevel 8 goto :failed',
      'start "" /d "%DST%" "%DST%\\%EXE%"',
      'goto :cleanup',
      ':failed',
      'echo 更新失败，未能覆盖文件。日志: %~dp0update_error.log',
      'robocopy "%SRC%" "%DST%" /E /IS /IT >"%~dp0update_error.log" 2>&1',
      'pause',
      ':cleanup',
      'cd /d "%TEMP%"',
      'timeout /t 2 /nobreak >nul',
      '(goto) 2>nul & del "%~f0"',
      '',
    ].join(nl) +
        nl;
  }

  /// 解压 zip，并防目录穿越（zip slip）。
  static Future<bool> _extractZipSafely({
    required String zipPath,
    required Directory destination,
  }) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final root = destination.absolute.path;

    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      if (name.isEmpty) continue;
      final targetPath = '${destination.path}${Platform.pathSeparator}'
          '${name.replaceAll('/', Platform.pathSeparator)}';
      final normalized = File(targetPath).absolute.path;
      // 拒绝 ../ 逃逸到目标目录之外。
      if (!normalized.startsWith('$root${Platform.pathSeparator}') &&
          normalized != root) {
        DebugLog.log('Update', '拒绝可疑压缩项: $name');
        continue;
      }
      if (entry.isFile) {
        final content = entry.content;
        if (content is! List<int>) continue;
        final file = File(normalized);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(content, flush: true);
      } else {
        await Directory(normalized).create(recursive: true);
      }
    }
    return true;
  }

  // ==================== 统一入口 ====================

  /// 按当前平台安装。[downloadedPath] 是 [UpdateService.download] 的产物。
  static Future<InstallResult> install(
    String downloadedPath, {
    required UpdatePlatform platform,
  }) async {
    switch (platform) {
      case UpdatePlatform.android:
        return installAndroidApk(downloadedPath);
      case UpdatePlatform.windows:
        return applyWindowsUpdate(downloadedPath);
      case UpdatePlatform.web:
      case UpdatePlatform.unsupported:
        return const InstallResult.failure(
          InstallFailure.unsupportedPlatform,
          '当前平台不支持自动更新',
        );
    }
  }
}
