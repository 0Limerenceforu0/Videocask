import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../providers/cache_provider.dart';
import '../../models/cache_item.dart';
import '../../widgets/empty_widget.dart';

/// 缓存管理页面
class CacheManagerPage extends StatelessWidget {
  const CacheManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cacheProvider = context.watch<CacheProvider>();

    final bgColor = isDark ? const Color(0xFF17181A) : const Color(0xFFF4F4F4);
    final cardColor = isDark ? const Color(0xFF222325) : Colors.white;
    final textColor =
        isDark ? const Color(0xFFE6E6E6) : const Color(0xFF212121);
    final subTextColor =
        isDark ? const Color(0xFF999999) : const Color(0xFF999999);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('缓存管理'),
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          // 仅WiFi开关
          Switch(
            value: cacheProvider.onlyWifi,
            onChanged: (value) => cacheProvider.setOnlyWifi(value),
            activeThumbColor: theme.colorScheme.primary,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                '仅WiFi',
                style: TextStyle(color: subTextColor, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (kIsWeb)
            Material(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.65),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Web 端本地缓存依赖浏览器存储，能力与桌面/移动应用不同；若列表长期为空属正常情况。',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 缓存信息栏（B站风格卡片）
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '存储空间',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (cacheProvider.cacheItems.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('清理缓存'),
                              content: const Text('确定要清理所有缓存吗？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await cacheProvider.clearAllCache();
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(content: Text('缓存已清理')),
                                      );
                                    }
                                  },
                                  child: const Text(
                                    '清理',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Text(
                          '清理全部',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // 空间进度条
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: 0.3, // 示意值
                    minHeight: 8,
                    backgroundColor: isDark
                        ? const Color(0xFF2E2F31)
                        : const Color(0xFFEEEEEE),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '已用: ${cacheProvider.formattedTotalSize}',
                      style: TextStyle(color: subTextColor, fontSize: 12),
                    ),
                    Text(
                      '已缓存 ${cacheProvider.completedCount} 个视频',
                      style: TextStyle(color: subTextColor, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 缓存列表
          Expanded(
            child: cacheProvider.cacheItems.isEmpty
                ? const NoCacheWidget()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: cacheProvider.cacheItems.length,
                    itemBuilder: (context, index) {
                      final item = cacheProvider.cacheItems[index];
                      return _buildBiliCacheItem(
                        context,
                        theme,
                        item,
                        cacheProvider,
                        cardColor: cardColor,
                        textColor: textColor,
                        subTextColor: subTextColor,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 构建B站风格缓存项
  Widget _buildBiliCacheItem(
    BuildContext context,
    ThemeData theme,
    CacheItem item,
    CacheProvider provider, {
    required Color cardColor,
    required Color textColor,
    required Color subTextColor,
  }) {
    final progress = (item.progressPercent * 100).toInt();

    // 状态图标和颜色
    final IconData statusIcon;
    final Color statusColor;
    if (item.isCompleted) {
      statusIcon = Icons.download_done;
      statusColor = const Color(0xFF66BB6A);
    } else if (item.isDownloading) {
      statusIcon = Icons.downloading;
      statusColor = theme.colorScheme.primary;
    } else if (item.isFailed) {
      statusIcon = Icons.error_outline;
      statusColor = const Color(0xFFE57373);
    } else {
      statusIcon = Icons.download;
      statusColor = const Color(0xFFBDBDBD);
    }

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        provider.deleteCache(item.id);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // 左侧状态图标
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: item.isDownloading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      ),
                    )
                  : Icon(statusIcon, color: statusColor, size: 24),
            ),
            const SizedBox(width: 14),
            // 右侧信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.movieName,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.episodeName} | ${item.quality}',
                    style: TextStyle(color: subTextColor, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  if (!item.isCompleted)
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: item.progressPercent,
                              minHeight: 6,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                item.isFailed
                                    ? Colors.red
                                    : theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$progress%',
                          style: TextStyle(color: subTextColor, fontSize: 11),
                        ),
                      ],
                    )
                  else
                    Text(
                      item.formattedSize,
                      style: TextStyle(color: subTextColor, fontSize: 11),
                    ),
                ],
              ),
            ),
            // 操作按钮
            _buildActionButtons(context, item, provider),
          ],
        ),
      ),
    );
  }

  /// 构建操作按钮
  Widget _buildActionButtons(
    BuildContext context,
    CacheItem item,
    CacheProvider provider,
  ) {
    if (item.isDownloading) {
      return IconButton(
        icon: const Icon(Icons.pause, size: 20),
        onPressed: () => provider.pauseDownload(item.id),
      );
    } else if (item.isPaused || item.isFailed || item.isWaiting) {
      return IconButton(
        icon: const Icon(Icons.play_arrow, size: 20),
        onPressed: () => provider.resumeDownload(item.id),
      );
    } else if (item.isCompleted) {
      return IconButton(
        icon: const Icon(Icons.play_circle, size: 20, color: Colors.green),
        onPressed: () async {
          final file = File(item.localPath);
          if (await file.exists()) {
            if (!context.mounted) return;
            // 桌面平台使用默认播放器打开
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
              if (Platform.isWindows) {
                await Process.run('cmd', ['/c', 'start', '', item.localPath]);
              } else if (Platform.isMacOS) {
                await Process.run('open', [item.localPath]);
              } else if (Platform.isLinux) {
                await Process.run('xdg-open', [item.localPath]);
              }
              if (!context.mounted) return;
            }
          } else {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('缓存文件不存在')),
            );
          }
        },
      );
    }
    return const SizedBox.shrink();
  }
}
