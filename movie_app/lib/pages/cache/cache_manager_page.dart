import 'dart:async' show unawaited;

import 'package:cached_network_image/cached_network_image.dart';

import '../../utils/web_http_stub.dart'
    if (dart.library.html) '../../utils/web_http.dart' as web_http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/cache_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/cache_service.dart';
import '../../models/cache_item.dart';
import '../../utils/cache_playback_helper.dart';
import '../../widgets/empty_widget.dart';

/// 缓存管理页面
class CacheManagerPage extends StatelessWidget {
  const CacheManagerPage({super.key});

  Future<void> _setOnlyWifi(BuildContext context, bool value) async {
    await context.read<SettingsProvider>().setOnlyWifiCache(value);
    if (!context.mounted) return;
    await context.read<CacheProvider>().setOnlyWifi(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
        title: Text(l10n.cacheManagerTitle),
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          Switch(
            value: cacheProvider.onlyWifi,
            onChanged: (value) => unawaited(_setOnlyWifi(context, value)),
            activeThumbColor: theme.colorScheme.primary,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                l10n.cacheManagerOnlyWifi,
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
                        l10n.cacheWebBanner,
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
                      l10n.cacheManagerStorageTitle,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (cacheProvider.cacheItems.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          showDialog<void>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: Text(l10n.cacheManagerClearConfirmTitle),
                              content: Text(l10n.cacheManagerClearConfirmBody),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  child: Text(l10n.detailClose),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await cacheProvider.clearAllCache();
                                    if (dialogContext.mounted) {
                                      Navigator.of(dialogContext).pop();
                                    }
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            l10n.cacheManagerClearDone,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: Text(
                                    l10n.cacheManagerClearAll,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Text(
                          l10n.cacheManagerClearAll,
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: cacheProvider.storageUsageRatio,
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
                      CacheService.maxCacheBytes <= 0
                          ? '已用 ${cacheProvider.formattedTotalSize} · 不设上限'
                          : l10n.cacheManagerUsedLabel(
                              cacheProvider.formattedTotalSize,
                              cacheProvider.formattedMaxCacheSize,
                            ),
                      style: TextStyle(color: subTextColor, fontSize: 12),
                    ),
                    Text(
                      l10n.cacheManagerCompletedCount(
                        cacheProvider.completedCount,
                      ),
                      style: TextStyle(color: subTextColor, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
                        l10n: l10n,
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

  Widget _buildBiliCacheItem(
    BuildContext context,
    ThemeData theme,
    CacheItem item,
    CacheProvider provider, {
    required AppLocalizations l10n,
    required Color cardColor,
    required Color textColor,
    required Color subTextColor,
  }) {
    final progress = (item.progressPercent * 100).toInt();

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
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 48,
                child: item.movieCover.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: web_http.webProxiedImageUrl(
                          item.movieCover,
                        ),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: statusColor.withValues(alpha: 0.1),
                          child: Icon(statusIcon, color: statusColor, size: 22),
                        ),
                      )
                    : Container(
                        color: statusColor.withValues(alpha: 0.1),
                        child: item.isDownloading
                            ? Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      statusColor,
                                    ),
                                  ),
                                ),
                              )
                            : Icon(statusIcon, color: statusColor, size: 22),
                      ),
              ),
            ),
            const SizedBox(width: 14),
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
                  if (item.isDownloading && item.speed > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.cacheDownloadSpeed(item.formattedSpeed),
                      style: TextStyle(color: subTextColor, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            _buildActionButtons(context, item, provider, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    CacheItem item,
    CacheProvider provider,
    AppLocalizations l10n,
  ) {
    if (item.isDownloading) {
      return IconButton(
        tooltip: l10n.detailCachePause,
        icon: const Icon(Icons.pause, size: 20),
        onPressed: () => provider.pauseDownload(item.id),
      );
    }
    if (item.isPaused || item.isFailed || item.isWaiting) {
      return IconButton(
        tooltip: l10n.detailCacheResume,
        icon: const Icon(Icons.play_arrow, size: 20),
        onPressed: () => unawaited(provider.resumeDownload(item.id)),
      );
    }
    if (item.isCompleted) {
      return IconButton(
        tooltip: l10n.cachePlayOffline,
        icon: const Icon(Icons.play_circle, size: 20, color: Colors.green),
        onPressed: () =>
            unawaited(CachePlaybackHelper.playCachedItem(context, item)),
      );
    }
    return const SizedBox.shrink();
  }
}
