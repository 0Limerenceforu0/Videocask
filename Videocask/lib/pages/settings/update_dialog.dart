import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config/app_navigator.dart';
import '../../services/debug_log.dart';
import '../../services/update/update_installer.dart';
import '../../services/update/update_policy.dart';
import '../../services/update/update_service.dart';

/// 手动/自动检查更新的统一入口与弹窗。
///
/// 交互约定：
/// - 启动静默检查只在新版本时弹窗，失败一声不响；
/// - 手动检查一定会给反馈（最新 / 有新版 / 还没发版 / 网络失败）；
/// - 强制更新（正文含 `[强制更新]`）时不可关闭、不可「稍后」。

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

  final result = await UpdateService.instance.checkForUpdate(forceRefresh: true);
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
  );
  if (!shouldPrompt) return;

  final context = _rootContext();
  if (context == null || !context.mounted) return;
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

/// 打开更新弹窗。
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

/// 更新弹窗主体。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info, required this.manual});

  final UpdateInfo info;
  final bool manual;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  _Phase _phase = _Phase.idle;
  double _progress = 0;
  String _statusText = '';
  String? _error;
  String? _downloadedPath;
  String? _androidAbi;
  CancelToken? _cancelToken;

  UpdateInfo get _info => widget.info;
  bool get _busy => _phase == _Phase.downloading || _phase == _Phase.installing;

  @override
  void initState() {
    super.initState();
    // ABI 提前取好：既用于显示准确体积，也保证「下载」按钮按下时无需再等平台通道。
    unawaited(_loadAbi());
  }

  Future<void> _loadAbi() async {
    final abi = await UpdateService.instance.androidAbi();
    if (!mounted || abi == null) return;
    setState(() => _androidAbi = abi);
  }

  @override
  void dispose() {
    _cancelToken?.cancel('dialog disposed');
    super.dispose();
  }

  Future<void> _startDownload() async {
    final platform = UpdateService.instance.platform;
    if (platform == UpdatePlatform.unsupported) {
      setState(() {
        _error = '当前平台不支持自动更新，请到 Release 页面手动下载。';
        _phase = _Phase.failed;
      });
      return;
    }

    final abi = _androidAbi ?? await UpdateService.instance.androidAbi();
    final asset = _info.assetFor(platform, androidAbi: abi);
    if (asset == null) {
      setState(() {
        _error = '这个版本没有提供适合当前设备的安装包，请到 Release 页面手动选择。';
        _phase = _Phase.failed;
      });
      return;
    }

    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _statusText = '正在连接…';
      _error = null;
    });

    try {
      final dir = await UpdateInstaller.downloadDirectory();
      final ext = platform == UpdatePlatform.android ? '.apk' : '.zip';
      final savePath =
          '${dir.path}${Platform.pathSeparator}guanzi-update-${_info.version.label}$ext';
      final token = CancelToken();
      _cancelToken = token;

      await UpdateService.instance.download(
        url: asset.downloadUrl,
        savePath: savePath,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _progress = total <= 0 ? 0 : received / total;
            _statusText = _progressLabel(received, total);
          });
        },
      );

      if (!mounted) return;
      _downloadedPath = savePath;
      setState(() {
        _phase = _Phase.readyToInstall;
        _progress = 1;
        _statusText = '下载完成';
      });
      await _install();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = '下载失败：${e.message ?? e.type.name}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = '下载失败：$e';
      });
    }
  }

  String _progressLabel(int received, int total) {
    final mb = received / (1024 * 1024);
    if (total <= 0) return '已下载 ${mb.toStringAsFixed(1)} MB';
    final totalMb = total / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} / ${totalMb.toStringAsFixed(1)} MB';
  }

  Future<void> _install() async {
    final path = _downloadedPath;
    if (path == null) return;
    final platform = UpdateService.instance.platform;

    if (platform == UpdatePlatform.android) {
      final allowed = await UpdateInstaller.canInstallPackages();
      if (!allowed) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.failed;
          _error = '需要「安装未知应用」权限才能完成更新。';
        });
        return;
      }
    }

    setState(() {
      _phase = _Phase.installing;
      _statusText = platform == UpdatePlatform.windows ? '正在准备替换文件…' : '正在调起安装器…';
      _error = null;
    });

    final result = await UpdateInstaller.install(path, platform: platform);
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _phase = _Phase.failed;
        _error = result.message;
      });
      return;
    }

    if (platform == UpdatePlatform.windows) {
      // 批处理已经启动并在等本进程退出，这里只给用户一句提示再退出。
      setState(() {
        _phase = _Phase.done;
        _statusText = '应用即将退出，随后自动替换并重启。';
      });
      await Future<void>.delayed(const Duration(seconds: 2));
      exit(0);
      return;
    }

    setState(() {
      _phase = _Phase.done;
      _statusText = '已调起系统安装器，请按提示完成安装。';
    });
  }

  Future<void> _openPermissionSettings() async {
    await UpdateInstaller.openInstallPermissionSettings();
  }

  void _later() {
    if (_info.isMandatory) return;
    unawaited(UpdateService.instance.skipBuild(_info.version.build));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final current = UpdateService.instance.currentVersion();
    final mandatory = _info.isMandatory;
    final theme = Theme.of(context);

    return PopScope(
      canPop: !mandatory && !_busy,
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
        title: Row(
          children: [
            Icon(Icons.system_update, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(mandatory ? '发现重要更新' : '发现新版本')),
            if (!mandatory && !_busy)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: '稍后再说',
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
                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                ),
              ),
              if (_info.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Text(
                      _info.notes.replaceAll('[强制更新]', '').replaceAll(
                            '[mandatory]',
                            '',
                          ),
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                  ),
                ),
              ],
              if (_busy || _phase == _Phase.readyToInstall) ...[
                const SizedBox(height: 18),
                LinearProgressIndicator(
                  value: _phase == _Phase.downloading && _progress > 0
                      ? _progress
                      : null,
                ),
                const SizedBox(height: 8),
                Text(_statusText, style: theme.textTheme.bodySmall),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (_phase == _Phase.done) ...[
                const SizedBox(height: 14),
                Text(
                  _statusText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        actions: _buildActions(mandatory),
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

  List<Widget> _buildActions(bool mandatory) {
    if (_phase == _Phase.done) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ];
    }
    if (_busy) {
      return [
        if (_phase == _Phase.downloading)
          TextButton(
            onPressed: () {
              _cancelToken?.cancel('用户取消');
              setState(() {
                _phase = _Phase.idle;
                _statusText = '';
                _progress = 0;
              });
            },
            child: const Text('取消'),
          ),
      ];
    }
    if (_phase == _Phase.failed) {
      return [
        if (_error != null && _error!.contains('权限'))
          TextButton(
            onPressed: _openPermissionSettings,
            child: const Text('去授权'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
        FilledButton(
          onPressed: _retry,
          child: const Text('重试'),
        ),
      ];
    }
    if (_phase == _Phase.readyToInstall) {
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
    if (_downloadedPath != null) {
      unawaited(_install());
    } else {
      unawaited(_startDownload());
    }
  }
}

enum _Phase { idle, downloading, readyToInstall, installing, done, failed }
