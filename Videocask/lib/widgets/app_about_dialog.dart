import 'package:flutter/material.dart';

import '../config/constants.dart';

/// 全 App 唯一的「关于」弹窗。
///
/// 之前「我的」页与设置页各写了一份 `showAboutDialog`，legalese 文案还不一致；
/// 诊断说明也散落在设置页。这里把关于信息与「帮助与反馈」合并维护一份。
void showAppAboutDialog(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: AppConstants.appName,
    applicationVersion: AppConstants.appVersion,
    applicationLegalese: '纯客户端、零服务器、无广告\n覆盖 Android、PC、Web 三端',
    children: [
      const SizedBox(height: 12),
      Text(
        '帮助与反馈',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      const SizedBox(height: 6),
      Text(
        '遇到跳剧情 / 闪退 / 卡顿等问题时：先正常使用该功能复现一次，'
        '再到「设置 → 诊断 → 导出诊断日志」把整个 videocask_logs'
        '（含 crash_*.txt 崩溃栈）打包发我即可——无需电脑、无需文件管理器权限。',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
      ),
    ],
  );
}
