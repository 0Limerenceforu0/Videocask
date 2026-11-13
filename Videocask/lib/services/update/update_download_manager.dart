import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../config/app_navigator.dart';
import '../../pages/settings/update_dialog.dart';
import '../debug_log.dart';
import '../download_storage.dart';
import 'update_installer.dart';
import 'update_notifier.dart';
import 'update_policy.dart';
import 'update_service.dart';

/// 后台下载的全局状态机。
///
/// 关键设计：下载任务由**单例**持有，与「更新弹窗」的生命周期解耦——
/// 关掉弹窗下载照常继续，App 切到后台也能在系统通知栏看到进度。
/// 这样就把「下载」从原来「锁死在弹窗里（下载时 canPop=false）」升级为「系统通知式后台下载」。
enum DownloadPhase {
  idle,
  downloading,
  readyToInstall,
  installing,
  done,
  failed,
}

/// 下载状态的不可变快照（UI 订阅它来刷新）。
class UpdateDownloadState {
  const UpdateDownloadState({
    this.phase = DownloadPhase.idle,
    this.progress = 0,
    this.received = 0,
    this.total = 0,
    this.statusText = '',
    this.error,
    this.downloadedPath,
    this.platform = UpdatePlatform.unsupported,
    this.versionLabel = '',
  });

  final DownloadPhase phase;
  final double progress;
  final int received;
  final int total;
  final String statusText;
  final String? error;
  final String? downloadedPath;
  final UpdatePlatform platform;
  final String versionLabel;

  bool get busy =>
      phase == DownloadPhase.downloading || phase == DownloadPhase.installing;

  UpdateDownloadState copyWith({
    DownloadPhase? phase,
    double? progress,
    int? received,
    int? total,
    String? statusText,
    String? error,
    String? downloadedPath,
    UpdatePlatform? platform,
    String? versionLabel,
  }) =>
      UpdateDownloadState(
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
        received: received ?? this.received,
        total: total ?? this.total,
        statusText: statusText ?? this.statusText,
        error: error,
        downloadedPath: downloadedPath ?? this.downloadedPath,
        platform: platform ?? this.platform,
        versionLabel: versionLabel ?? this.versionLabel,
      );
}

/// 应用内更新的后台下载管理器（单例）。
///
/// 用法：
/// - [start]：开始下载（若已在下载则忽略）。会弹系统通知显示进度。
/// - [install]：下载完成后调起安装。
/// - [cancel]：取消下载（同时撤掉通知）。
/// - [state]：ValueNotifier，弹窗/通知订阅它刷新 UI。
/// - [onNotificationTap]：通知被点击时由 [UpdateNotifier] 回调，用于重开弹窗。
class UpdateDownloadManager {
  UpdateDownloadManager._();

  static final UpdateDownloadManager instance = UpdateDownloadManager._();

  final ValueNotifier<UpdateDownloadState> state =
      ValueNotifier(const UpdateDownloadState());

  UpdateInfo? _info;
  CancelToken? _cancelToken;
  bool _dialogOpen = false;
  int _lastNotifyTs = 0;

  /// 当前是否已有下载在进行中（避免重复 start）。
  bool get isActive => state.value.busy;

  /// 弹窗可见时由弹窗在 initState/dispose 调用，避免通知点回来后再叠一个弹窗。
  void setDialogOpen(bool open) => _dialogOpen = open;

  /// 开始后台下载。已在下载中则直接返回。
  ///
  /// [abi] 是提前取到的设备 ABI（决定下载哪个架构的包），为空时内部再取一次。
  Future<void> start(UpdateInfo info, {String? abi}) async {
    if (state.value.phase == DownloadPhase.downloading ||
        state.value.phase == DownloadPhase.installing) {
      return;
    }

    _info = info;
    final platform = UpdateService.instance.platform;
    if (platform == UpdatePlatform.unsupported) {
      state.value = state.value.copyWith(
        phase: DownloadPhase.failed,
        error: '当前平台不支持自动更新，请到 Release 页面手动下载。',
      );
      return;
    }

    final resolvedAbi = abi ?? await UpdateService.instance.androidAbi();
    final asset = info.assetFor(platform, androidAbi: resolvedAbi);
    if (asset == null) {
      state.value = state.value.copyWith(
        phase: DownloadPhase.failed,
        error: '这个版本没有提供适合当前设备的安装包，请到 Release 页面手动选择。',
      );
      return;
    }

    // 真正要弹下载通知前再请求权限，避免启动就打扰用户。
    unawaited(UpdateNotifier.instance.requestPermission());

    final dir = await UpdateInstaller.downloadDirectory();
    final ext = platform == UpdatePlatform.android ? '.apk' : '.zip';
    final savePath =
        '${dir.path}${Platform.pathSeparator}videocask-update-${info.version.label}$ext';
    final token = CancelToken();
    _cancelToken = token;
    _lastNotifyTs = 0;

    state.value = state.value.copyWith(
      phase: DownloadPhase.downloading,
      progress: 0,
      received: 0,
      total: 0,
      statusText: '正在连接…',
      error: null,
      downloadedPath: null,
      platform: platform,
      versionLabel: info.version.label,
    );
    await UpdateNotifier.instance.showProgress(
      percent: 0,
      title: '正在下载更新 v${info.version.label}',
      text: '正在连接…',
    );

    try {
      await UpdateService.instance.download(
        url: asset.downloadUrl,
        savePath: savePath,
        cancelToken: token,
        onProgress: (received, total) {
          final p = total <= 0 ? 0.0 : received / total;
          state.value = state.value.copyWith(
            progress: p,
            received: received,
            total: total,
            statusText: _progressLabel(received, total),
          );
          _maybeNotifyProgress(received, total, p);
        },
      );

      state.value = state.value.copyWith(
        phase: DownloadPhase.readyToInstall,
        progress: 1,
        statusText: '下载完成',
        downloadedPath: savePath,
      );
      await UpdateNotifier.instance.showComplete(
        title: '更新已下载完成',
        text: '点击安装 v${info.version.label}',
      );
      // Android：再存一份到公共「下载」目录，卸载应用后仍能从文件管理器找到安装包。
      if (platform == UpdatePlatform.android) {
        unawaited(_publishPackage(savePath, info.version.label));
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        // 用户取消：回到初始态（通知已撤），不报错。
        _reset();
        return;
      }
      state.value = state.value.copyWith(
        phase: DownloadPhase.failed,
        error: '下载失败：${e.message ?? e.type.name}',
      );
      await UpdateNotifier.instance.showError(
        title: '下载失败',
        text: 'v${info.version.label} 下载失败，点击重试',
      );
    } catch (e) {
      state.value = state.value.copyWith(
        phase: DownloadPhase.failed,
        error: '下载失败：$e',
      );
      await UpdateNotifier.instance.showError(
        title: '下载失败',
        text: 'v${info.version.label} 下载失败，点击重试',
      );
    }
  }

  /// 下载完成后调起系统安装器。
  Future<void> install() async {
    final path = state.value.downloadedPath;
    if (path == null) return;
    final platform = state.value.platform;

    if (platform == UpdatePlatform.android) {
      final allowed = await UpdateInstaller.canInstallPackages();
      if (!allowed) {
        state.value = state.value.copyWith(
          phase: DownloadPhase.failed,
          error: '需要「安装未知应用」权限才能完成更新。',
        );
        return;
      }
    }

    // 安装交给系统，撤掉我们的进度/完成通知，避免和系统安装器叠在一起。
    await UpdateNotifier.instance.cancel();

    state.value = state.value.copyWith(
      phase: DownloadPhase.installing,
      statusText: platform == UpdatePlatform.windows
          ? '正在准备替换文件…'
          : '正在调起安装器…',
      error: null,
    );

    final result = await UpdateInstaller.install(path, platform: platform);
    if (state.value.downloadedPath == null) return; // 已被取消/重置

    if (!result.ok) {
      state.value = state.value.copyWith(
        phase: DownloadPhase.failed,
        error: result.message,
      );
      return;
    }

    if (platform == UpdatePlatform.windows) {
      state.value = state.value.copyWith(
        phase: DownloadPhase.done,
        statusText: '应用即将退出，随后自动替换并重启。',
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      // 与更新弹窗里的 Windows 路径保持一致：批处理已启动并在等本进程退出。
      // ignore: avoid_print
      print('update: exiting for windows self-replace');
      // 不在库里直接 exit，交给调用方（弹窗）处理，避免从通知路径误退出。
      return;
    }

    state.value = state.value.copyWith(
      phase: DownloadPhase.done,
      statusText: '已调起系统安装器，请按提示完成安装。',
    );
  }

  /// 取消下载并撤掉通知。
  void cancel() {
    _cancelToken?.cancel('用户取消');
    _cancelToken = null;
    unawaited(UpdateNotifier.instance.cancel());
    _reset();
  }

  /// 把安装包另存一份到公共「下载」目录：
  /// 应用被卸载后，用户仍能在文件管理器里找到安装包并直接点开安装。
  /// 失败不影响已经在私有目录里的安装包，仅记录日志。
  Future<void> _publishPackage(String path, String versionLabel) async {
    try {
      final dest = await DownloadStorage.publish(
        sourcePath: path,
        name: '罐子_v$versionLabel.apk',
        isVideo: false,
      );
      DebugLog.log('Update', '安装包已保存到公共目录: $dest');
      if (state.value.downloadedPath == path) {
        state.value = state.value.copyWith(
          statusText: '下载完成，安装包同时保存在 $dest',
        );
      }
    } catch (e) {
      DebugLog.log('Update', '安装包保存到公共目录失败: $e');
    }
  }

  /// 通知被点击：重开更新弹窗（它自己会显示当前进度 / 安装按钮）。
  void onNotificationTap() {
    if (_info == null) return;
    if (_dialogOpen) return; // 已经有弹窗在，不重复堆叠
    // 延迟一帧，确保导航栈稳定；context 在回调内重新取，避免跨异步间隙使用。
    Future<void>.delayed(Duration.zero, () {
      if (_dialogOpen || _info == null) return;
      final ctx = appRootNavigatorKey.currentContext;
      if (ctx == null) return;
      showUpdateDialog(ctx, _info!, manual: false);
    });
  }

  void _reset() {
    _cancelToken = null;
    state.value = const UpdateDownloadState();
  }

  /// 进度通知做节流：最多每 400ms 更新一次，避免高频 show 抖动。
  void _maybeNotifyProgress(int received, int total, double p) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final percent = (p * 100).round();
    if (now - _lastNotifyTs < 400 && percent < 100) return;
    _lastNotifyTs = now;
    unawaited(
      UpdateNotifier.instance.showProgress(
        percent: percent,
        title: '正在下载更新 v${state.value.versionLabel}',
        text: _progressLabel(received, total),
      ),
    );
  }

  String _progressLabel(int received, int total) {
    final mb = received / (1024 * 1024);
    if (total <= 0) return '已下载 ${mb.toStringAsFixed(1)} MB';
    final totalMb = total / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} / ${totalMb.toStringAsFixed(1)} MB';
  }
}
