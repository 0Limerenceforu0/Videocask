import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../providers/settings_provider.dart';

/// WebDAV 配置弹窗（「我的 → 云备份」与「设置 → WebDAV同步」共用）。
///
/// 之前只在设置页里有一份私有实现，从「我的」页点进去只能跳到设置页顶部，
/// 用户还要自己滚到倒数第二屏。这里抽成公共方法，两个入口都直接弹窗。
Future<void> showWebDavConfigSheet(BuildContext context) async {
  final settings = context.read<SettingsProvider>();
  final urlController = TextEditingController(
    text: settings.webdavConfig?.serverUrl ?? '',
  );
  final userController = TextEditingController(
    text: settings.webdavConfig?.username ?? '',
  );
  final passController = TextEditingController(
    text: settings.webdavConfig?.password ?? '',
  );
  final pathController = TextEditingController(
    text: settings.webdavConfig?.remotePath ?? '/movie_app/',
  );

  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        decoration: BoxDecoration(
          color: Theme.of(sheetContext).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.cloud_outlined,
                    color: Theme.of(sheetContext).colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'WebDAV 配置',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: settings.webdavConfig?.presetName ?? '自定义',
                decoration: const InputDecoration(
                  labelText: '服务商',
                  border: OutlineInputBorder(),
                ),
                items: AppConstants.webdavPresets
                    .map(
                      (preset) => DropdownMenuItem<String>(
                        value: preset['name'],
                        child: Text(preset['name'] ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  for (final preset in AppConstants.webdavPresets) {
                    if (preset['name'] == value) {
                      urlController.text = preset['url'] ?? '';
                      break;
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: userController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pathController,
                decoration: const InputDecoration(
                  labelText: '远程路径',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        settings.disconnectWebDav();
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('断开连接'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final success = await settings.configureWebDav(
                          serverUrl: urlController.text.trim(),
                          username: userController.text.trim(),
                          password: passController.text.trim(),
                          remotePath: pathController.text.trim(),
                          presetName: '自定义',
                        );
                        if (!sheetContext.mounted) return;
                        Navigator.of(sheetContext).pop();
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          SnackBar(
                            content: Text(success ? '连接成功' : '连接失败'),
                          ),
                        );
                      },
                      child: const Text('连接'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    urlController.dispose();
    userController.dispose();
    passController.dispose();
    pathController.dispose();
  }
}
