import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config/app_navigator.dart';
import '../../services/update/update_download_manager.dart';
import '../../services/update/update_installer.dart';
import '../../services/update/update_policy.dart';
import '../../services/update/update_service.dart';

/// 手动/自动检查更新的统一入口与弹窗。
///
/// 交互约定：
/// - 启动静默检查只在新版本时弹窗，失败一声不响；
/// - 手动检查一定会给反馈（最新 / 有新版 / 还没发版 / 网络失败）；
/// - 强制更新（正文含 `[强制更新]`）时不可关闭、不可「稍后」。
///
/// 下载模型：弹窗只是「下载管理器」的**观察者**——下载任务由
/// [UpdateDownloadManager] 这个单例持有，关掉弹窗下载照常继续，App 切到后台也能
/// 在系统通知栏看到进度（用户要的「系统通知式后台下载」）。

/// 手动检查更新（设置页入口）。
Future<void> checkUpdateManually(BuildContext context) async {
  final scaffold = ScaffoldMessenger.maybeOf(context);
  // 先用一个不可关闭的 loading 弹窗挡住重复点击，检查完再换结果。
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CheckingDialog(),
    ),
  );

  final result =
      await UpdateService.instance.checkForUpdate(forceRefresh: true);
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // 关掉 loading

  if (!context.mounted) return;
  switch (result.status) {
    case UpdateCheckStatus.available:
      await showUpdateDialog(context, result.info!, manual: true);
    case UpdateCheckStatus.upToDate:
      scaffold?.showSnackBar(
        SnackBar(
          content: Text(
            '已是最新版本 v${UpdateService.instance.currentVersion().label}',
          ),
        ),
      );
    case UpdateCheckStatus.noRelease:
      scaffold?.showSnackBar(
        const SnackBar(content: Text('仓库还没有发布任何版本')),
      );
    case UpdateCheckStatus.failed:
      scaffold?.showSnackBar(
        SnackBar(content: Text(result.error ?? '检查更新失败，请稍后重试')),
      );
  }
}

/// 启动后的静默检查：只在有新版本时弹窗，任何失败都静默。
///
/// 由 [scheduleStartupUpdateCheck] 延迟调用，避免和首屏加载抢带宽。
///
/// 「同一版本只提醒一次」：弹窗**展示前**就把该版本记为已提示。用户无论点
/// 「稍后」、点关闭、点右上角 ×、按 Esc 还是直接杀进程，下次启动都不会再被
/// 同一个版本打扰；下一个新版本发布时仍会提醒一次。
Future<void> runStartupUpdateCheck() async {
  final result = await UpdateService.instance.checkForUpdate();
  if (!result.hasUpdate) return;
  final info = result.info!;
  final current = UpdateService.instance.currentVersion();
  final shouldPrompt = shouldPromptUpdate(
    current: current,
    latest: info.version,
    mandatory: info.isMandatory,
    skippedBuild: UpdateService.instance.skippedBuild(),
    promptedVersion: UpdateService.instance.promptedVersion(),
  );
  if (!shouldPrompt) return;

  final context = _rootContext();
  if (context == null || !context.mounted) return;
  // 先落盘、再弹窗：宁可这一次没弹成（例如页面正在切换），也不要每次启动都骚扰。
  await UpdateService.instance.markVersionPrompted(info.version);
  if (!context.mounted) return;
  await showUpdateDialog(context, info, manual: false);
}

/// 延迟一段时间再检查，避免拖慢冷启动。
void scheduleStartupUpdateCheck({
  Duration delay = const Duration(seconds: 5),
}) {
  if (kIsWeb) return; // Web 刷新即最新，不做启动检查。
  Timer(delay, () => unawaited(runStartupUpdateCheck()));
}

/// 取根导航的 context（`appRootNavigatorKey` 与 go_router 共用同一个 key）。
BuildContext? _rootContext() => appRootNavigatorKey.currentContext;

/// 打开更新弹窗。若该版本已在后台下载中，弹窗会自动「接管」显示实时进度。
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo info, {
  required bool manual,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !info.isMandatory,
    builder: (_) => UpdateDialog(info: info, manual: manual),
  );
}

/// 检查中的占位弹窗。
class _CheckingDialog extends StatelessWidget {
  const _CheckingDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 16),
          Text('正在检查更新…'),
        ],
      ),
    );
  }
}

/// 更新弹窗主体（下载管理器的观察者）。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info, required this.manual});

  final UpdateInfo info;
  final bool manual;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  late UpdateDownloadState _snap;
  String? _androidAbi;
  bool _autoInstallTriggered = false;

  UpdateInfo get _info => widget.info;

  @override
  void initState() {
    super.initState();
    _snap = UpdateDownloadManager.instance.state.value;
    UpdateDownloadManager.instance.setDialogOpen(true);
    UpdateDownloadManager.instance.state.addListener(_onManagerState);
    unawaited(_loadAbi());
    // 若打开弹窗时该版本已在后台下载/就绪，立即同步到当前状态。
    _maybeAutoInstall();
  }

  @override
  void dispose() {
    UpdateDownloadManager.instance.state.removeListener(_onManagerState);
    UpdateDownloadManager.instance.setDialogOpen(false);
    super.dispose();
  }

  void _onManagerState() {
    final next = UpdateDownloadManager.instance.state.value;
    if (!mounted) return;
    setState(() => _snap = next);
    _maybeAutoInstall();

    // Windows 自替换：管理器已把状态置为 done，这里负责退出当前进程。
    if (next.phase == DownloadPhase.done &&
        next.platform == UpdatePlatform.windows) {
      // 给批处理一点时间接管，再退出。
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        // ignore: avoid_print
        print('update: exiting for windows self-replace');
        // 仅在确实仍在当前弹窗时退出，避免从通知路径误退出。
        if (mounted) exit(0);
      });
    }
  }

  /// 下载完成且用户正看着弹窗 → 自动触发安装（体验连贯）。
  /// 若用户已切到后台，则只留「点击安装」通知，由用户回来再装。
  void _maybeAutoInstall() {
    if (_snap.phase == DownloadPhase.readyToInstall && !_autoInstallTriggered) {
      _autoInstallTriggered = true;
      unawaited(UpdateDownloadManager.instance.install());
    }
  }

  Future<void> _loadAbi() async {
    final abi = await UpdateService.instance.androidAbi();
    if (!mounted || abi == null) return;
    setState(() => _androidAbi = abi);
  }

  Future<void> _startDownload() async {
    await UpdateDownloadManager.instance.start(_info, abi: _androidAbi);
  }

  /// 中止下载（桌面端入口；Android 走通知栏的「取消下载」动作）。
  void _cancelDownload() => UpdateDownloadManager.instance.cancel();

  Future<void> _install() async {
    await UpdateDownloadManager.instance.install();
  }

  Future<void> _openPermissionSettings() async {
    await UpdateInstaller.openInstallPermissionSettings();
  }

  void _later() {
    if (_info.isMandatory) return;
    // 只在「还没开始下载」时点稍后才有意义；下载中关弹窗是后台继续，不算跳过。
    if (_snap.phase == DownloadPhase.idle) {
      unawaited(UpdateService.instance.skipBuild(_info.version.build));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final current = UpdateService.instance.currentVersion();
    final mandatory = _info.isMandatory;
    final theme = Theme.of(context);
    final snap = _snap;
    final busy = snap.busy;
    final hasError = snap.phase == DownloadPhase.failed && snap.error != null;

    return PopScope(
      // 后台下载：允许在下载中点关闭（下载继续在后台跑）；强制更新仍可拦截。
      canPop: !mandatory && snap.phase != DownloadPhase.installing,
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
        title: Row(
          children: [
            Icon(Icons.system_update, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(mandatory ? '发现重要更新' : '发现新版本')),
            if (!mandatory && !busy)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: _snap.phase == DownloadPhase.downloading
                    ? '后台继续下载'
                    : '稍后再说',
                onPressed: _later,
              ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                describeVersionChange(current, _info.version),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _subtitle(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                ),
              ),
              if (_info.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Text(
                      _info.notes
                          .replaceAll('[强制更新]', '')
                          .replaceAll('[mandatory]', ''),
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                  ),
                ),
              ],
              if (busy || snap.phase == DownloadPhase.readyToInstall) ...[
                const SizedBox(height: 18),
                LinearProgressIndicator(
                  value: snap.phase == DownloadPhase.downloading &&
                          snap.progress > 0
                      ? snap.progress
                      : null,
                ),
                const SizedBox(height: 8),
                Text(snap.statusText, style: theme.textTheme.bodySmall),
                if (snap.phase == DownloadPhase.downloading)
                  Text(
                    // 桌面端没有下载通知（UpdateNotifier 只在 Android 弹），别把它写死进文案。
                    (!kIsWeb &&
                            defaultTargetPlatform == TargetPlatform.android)
                        ? '（可关闭此弹窗，下载将在后台继续，进度见系统通知；需要中止请点通知里的「取消下载」）'
                        : '（可关闭此弹窗，下载将在后台继续；需要中止请点「取消下载」）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color
                          ?.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
              ],
              if (hasError) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    snap.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (snap.phase == DownloadPhase.done) ...[
                const SizedBox(height: 14),
                Text(
                  snap.statusText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        actions: _buildActions(mandatory, snap),
      ),
    );
  }

  String _subtitle() {
    final platform = UpdateService.instance.platform;
    final parts = <String>[];
    switch (platform) {
      case UpdatePlatform.android:
        parts.add('Android');
      case UpdatePlatform.windows:
        parts.add('Windows');
      case UpdatePlatform.web:
        parts.add('Web');
      case UpdatePlatform.unsupported:
        break;
    }
    final asset = _info.assetFor(platform, androidAbi: _androidAbi);
    if (asset != null && asset.sizeLabel.isNotEmpty) parts.add(asset.sizeLabel);
    if (_info.publishedAt != null) {
      final d = _info.publishedAt!;
      parts.add('${d.year}-${_two(d.month)}-${_two(d.day)}');
    }
    return parts.isEmpty ? '发布于 GitHub Releases' : parts.join(' · ');
  }

  static String _two(int v) => v < 10 ? '0$v' : '$v';

  List<Widget> _buildActions(bool mandatory, UpdateDownloadState snap) {
    if (snap.phase == DownloadPhase.done) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ];
    }
    if (snap.busy) {
      // Android 有系统通知栏承载「取消下载」，弹窗里只留「关闭」，避免两个按钮语义打架。
      // 桌面端 UpdateNotifier 不弹通知（没有取消入口），因此仍保留一个「取消下载」，
      // 否则下载开始后用户没有任何中止手段。
      if (snap.phase != DownloadPhase.downloading) return const [];
      final hasNotificationBar =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      return [
        if (!hasNotificationBar)
          TextButton(
            onPressed: _cancelDownload,
            child: const Text('取消下载'),
          ),
        if (!mandatory)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
      ];
    }
    if (snap.phase == DownloadPhase.failed) {
      return [
        if (snap.error != null && snap.error!.contains('权限'))
          TextButton(
            onPressed: _openPermissionSettings,
            child: const Text('去授权'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _retry,
          child: const Text('重试'),
        ),
      ];
    }
    if (snap.phase == DownloadPhase.readyToInstall) {
      return [
        FilledButton(onPressed: _install, child: const Text('立即安装')),
      ];
    }
    return [
      if (!mandatory) TextButton(onPressed: _later, child: const Text('稍后')),
      FilledButton(
        onPressed: _startDownload,
        child: Text(mandatory ? '立即更新' : '下载并更新'),
      ),
    ];
  }

  void _retry() {
    // 已经下载好就直接重试安装，否则重新下载。
    if (_snap.downloadedPath != null) {
      unawaited(_install());
    } else {
      unawaited(_startDownload());
    }
  }
}
