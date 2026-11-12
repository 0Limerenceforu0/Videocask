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

  /// 降级被系统拦截：已装的 versionCode 比新包更高（常见于残留的测试包）。
  /// 此时系统弹「已存在更高版本」，我们提前拦截并给出「先卸载旧版本」的明确引导。
  downgradeBlocked,
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

  static const MethodChannel _channel = MethodChannel('videocask/update');

  /// 下载目录：Android 用应用私有 cache（FileProvider 可共享，免存储权限），
  /// Windows 用临时目录（更新完即可丢弃）。
  static Future<Directory> downloadDirectory() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}videocask_updates');
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
    // 安装前先做「降级拦截」：若设备上已装的 versionCode 比新包更高
    // （典型场景是之前装过更高版本号的测试包），系统会报「已存在更高版本」且原因含糊。
    // 这里提前识别，给出「先卸载旧版本」的可操作引导，而不是把系统错误甩给用户。
    final downgrade = await _checkDowngrade(apkPath);
    if (downgrade != null) return downgrade;
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

  /// 安装前比对已装版本与新包版本：已装 versionCode 更高则判为降级，拦截并给出引导文案。
  /// 读取失败（如无法解析 APK）时放行，由系统兜底，不阻断正常安装。
  static Future<InstallResult?> _checkDowngrade(String apkPath) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'verifyUpdateInstall',
        {'path': apkPath},
      );
      if (res == null) return null;
      final allowed = res['allowed'] == true;
      if (allowed) return null;
      final installed = res['installedVersionCode'];
      final apk = res['apkVersionCode'];
      return InstallResult.failure(
        InstallFailure.downgradeBlocked,
        '当前已安装更高版本（versionCode $installed），无法降级安装到 $apk。\n'
        '请先在系统「设置 → 应用」中卸载旧版本（含测试包）后重试。',
      );
    } catch (e) {
      DebugLog.log('Update', '降级预检失败，放行: $e');
      return null;
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
        '${Platform.pathSeparator}videocask_update_payload',
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

      // 安装目录 = 当前 exe 所在目录。
      // 更新包里的可执行文件名可能与当前运行的不同：历史版本是 movie_app.exe，
      // 新版本改为 罐子.exe。这里只校验包根目录存在 exe，实际文件名交给批处理
      // 在运行时解析——避免把中文文件名写进 .bat（cmd 按 GBK 读 UTF-8 会乱码）。
      final exePath = Platform.resolvedExecutable;
      final installDir = File(exePath).parent.path;
      final runningExeName = exePath.split(Platform.pathSeparator).last;
      final payloadExes = workRoot
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.exe'))
          .toList();
      final hasSameName = payloadExes.any(
        (f) =>
            f.path.split(Platform.pathSeparator).last.toLowerCase() ==
            runningExeName.toLowerCase(),
      );
      if (payloadExes.isEmpty || (payloadExes.length > 1 && !hasSameName)) {
        return const InstallResult.failure(
          InstallFailure.payloadInvalid,
          '更新包里没有可执行文件，请检查发布产物',
        );
      }

      final batPath =
          '${workRoot.parent.path}${Platform.pathSeparator}videocask_apply_update.bat';
      final script = _buildWindowsApplyScript(
        payloadDirName: workRoot.path.split(Platform.pathSeparator).last,
        processId: pid,
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
  /// 1. 先等**当前进程**退出——运行中的 exe 被占用，robocopy 会跳过。用 PID
  ///    等待而不是按 IMAGENAME，避免中文 exe 名在 .bat 里乱码。
  /// 2. 包内 exe 名由批处理在运行时从 `%SRC%\*.exe` 解析（历史版本是
  ///    movie_app.exe，新版本是 罐子.exe），因此脚本本身保持纯 ASCII。
  /// 3. 用 robocopy `/IS /IT` 强制覆盖同名文件（保留目录结构），并把改名前的
  ///    旧 exe（如 movie_app.exe）删掉，避免新旧两个可执行文件并存。
  /// 4. 重启新版本后再删除自身，避免删除失败。
  static String _buildWindowsApplyScript({
    required String payloadDirName,
    required int processId,
  }) {
    final nl = '\r\n';
    return <String>[
      '@echo off',
      'setlocal',
      // %~dp0 = 本 .bat 所在目录（TEMP），载荷解压在同级的固定子目录。
      'set "SRC=%~dp0$payloadDirName"',
      // %CD% = 调用方传入的 workingDirectory，即 exe 所在安装目录。
      'set "DST=%CD%"',
      'set "EXE="',
      'for %%f in ("%SRC%\\*.exe") do set "EXE=%%~nxf"',
      'if not defined EXE goto :failed',
      // 最多等 60 秒，避免进程异常残留导致永远不覆盖。
      'for /l %%i in (1,1,60) do (',
      '  tasklist /FI "PID eq $processId" /NH 2>nul | find "$processId" >nul',
      '  if errorlevel 1 goto :copy',
      '  timeout /t 1 /nobreak >nul',
      ')',
      ':copy',
      'robocopy "%SRC%" "%DST%" /E /IS /IT /NFL /NDL /NJH /NJS /NC /NS /NP >nul',
      'if errorlevel 8 goto :failed',
      // 覆盖成功后清理改名前的旧 exe（如 movie_app.exe）。
      'for %%f in ("%DST%\\*.exe") do if /I not "%%~nxf"=="%EXE%" del /f /q "%%~f" >nul 2>&1',
      'start "" /d "%DST%" "%DST%\\%EXE%"',
      'goto :cleanup',
      ':failed',
      'echo Update failed: could not overwrite files. See update_error.log',
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
