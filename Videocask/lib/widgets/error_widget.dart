import 'package:flutter/material.dart';

/// 错误组件
class ErrorWidget extends StatelessWidget {
  /// 错误信息
  final String message;

  /// 错误图标
  final IconData icon;

  /// 重试回调
  final VoidCallback? onRetry;

  /// 重试按钮文字
  final String retryText;

  /// 文案颜色（例如深色 Scaffold 上需提高对比度时传入）
  final Color? messageColor;

  /// 图标颜色（默认使用 [Theme.colorScheme.error]）
  final Color? iconColor;

  const ErrorWidget({
    super.key,
    required this.message,
    this.icon = Icons.error_outline,
    this.onRetry,
    this.retryText = '重试',
    this.messageColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color:
                  iconColor ?? theme.colorScheme.error.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: messageColor ?? theme.hintColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(retryText),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 网络错误组件
class NetworkErrorWidget extends StatelessWidget {
  final VoidCallback? onRetry;

  const NetworkErrorWidget({
    super.key,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorWidget(
      message: '网络连接失败，请检查网络设置',
      icon: Icons.wifi_off,
      onRetry: onRetry,
    );
  }
}

/// 服务器错误组件
class ServerErrorWidget extends StatelessWidget {
  final VoidCallback? onRetry;

  const ServerErrorWidget({
    super.key,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorWidget(
      message: '服务器异常，请稍后重试',
      icon: Icons.cloud_off,
      onRetry: onRetry,
    );
  }
}
