import 'package:flutter/material.dart';

/// 空状态组件（B站风格：插图+提示文字）
class EmptyWidget extends StatelessWidget {
  /// 提示文字
  final String message;

  /// 图标
  final IconData icon;

  /// 图标大小
  final double iconSize;

  /// 操作按钮文字
  final String? actionText;

  /// 操作按钮回调
  final VoidCallback? onAction;

  const EmptyWidget({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.iconSize = 80,
    this.actionText,
    this.onAction,
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
            // B站风格圆形背景图标
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 56,
                color: theme.hintColor.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.hintColor,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionText != null && onAction != null) ...[
              const SizedBox(height: 24),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: onAction,
                child: Text(actionText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 无收藏空状态
class NoFavoriteWidget extends StatelessWidget {
  final VoidCallback? onGoHome;

  const NoFavoriteWidget({
    super.key,
    this.onGoHome,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyWidget(
      message: '还没有收藏任何影片',
      icon: Icons.favorite_border,
      actionText: '去看看',
      onAction: onGoHome,
    );
  }
}

/// 无历史空状态
class NoHistoryWidget extends StatelessWidget {
  final VoidCallback? onGoHome;

  const NoHistoryWidget({
    super.key,
    this.onGoHome,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyWidget(
      message: '还没有观看记录',
      icon: Icons.history,
      actionText: '去看看',
      onAction: onGoHome,
    );
  }
}

/// 无搜索结果空状态
class NoSearchResultWidget extends StatelessWidget {
  final String keyword;
  final VoidCallback? onRetry;

  const NoSearchResultWidget({
    super.key,
    required this.keyword,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyWidget(
      message: '没有找到"$keyword"相关内容',
      icon: Icons.search_off,
      actionText: onRetry != null ? '重新搜索' : null,
      onAction: onRetry,
    );
  }
}

/// 无缓存空状态
class NoCacheWidget extends StatelessWidget {
  final VoidCallback? onGoHome;

  const NoCacheWidget({
    super.key,
    this.onGoHome,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyWidget(
      message: '还没有缓存任何影片',
      icon: Icons.download_done,
      actionText: '去缓存',
      onAction: onGoHome,
    );
  }
}
