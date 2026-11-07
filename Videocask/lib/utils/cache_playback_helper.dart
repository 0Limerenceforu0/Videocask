import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/routes.dart';
import '../l10n/app_localizations.dart';
import '../models/cache_item.dart';
import '../models/movie.dart';

/// 缓存列表「播放」：移动端进详情离线播，桌面用系统默认程序打开文件。
class CachePlaybackHelper {
  CachePlaybackHelper._();

  static Movie movieFromCacheItem(CacheItem item) {
    return Movie(
      id: item.movieId,
      sourceId: item.sourceId,
      name: item.movieName,
      cover: item.movieCover,
      updateStatus: item.episodeName,
    );
  }

  static bool get isDesktopOpenWithSystemPlayer {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  static Future<void> playCachedItem(
    BuildContext context,
    CacheItem item,
  ) async {
    if (item.localPath.isEmpty) {
      _snack(context, _l10n(context).cacheFileMissing);
      return;
    }
    if (kIsWeb) {
      _snack(context, _l10n(context).cacheWebPlayUnsupported);
      return;
    }

    final file = File(item.localPath);
    if (!await file.exists()) {
      if (!context.mounted) return;
      _snack(context, _l10n(context).cacheFileMissing);
      return;
    }

    if (isDesktopOpenWithSystemPlayer) {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', item.localPath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [item.localPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [item.localPath]);
      }
      return;
    }

    if (!context.mounted) return;
    AppRoutes.toDetailFromCache(context, item);
  }

  static AppLocalizations _l10n(BuildContext context) {
    return AppLocalizations.of(context)!;
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
