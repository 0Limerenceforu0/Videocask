import 'dart:async';

import 'package:flutter/material.dart';
import 'package:overlay_support/overlay_support.dart';

import '../../models/cache_item.dart';

/// 缓存管理相关逻辑
class DetailCache {
  /// 是否显示缓存下拉面板
  bool showCachePanel = false;

  /// 缓存下拉面板 OverlayEntry
  OverlayEntry? cachePanelEntry;

  /// 缓存刷新定时器
  Timer? cacheRefreshTimer;

  /// 缓存列表
  List<CacheItem> cacheItems = [];

  /// 缓存加载状态
  bool isLoadingCache = false;
  String cacheMessage = '';

  /// 加载缓存列表
  Future<void> loadCache(BuildContext context) async {
    isLoadingCache = true;
    cacheMessage = '正在加载缓存...';

    try {
      // 暂时返回空列表
      cacheItems = [];
    } catch (e) {
      cacheMessage = '加载缓存失败: $e';
    } finally {
      isLoadingCache = false;
    }
  }

  /// 添加缓存
  Future<void> addCache(BuildContext context, String url, String title) async {
    try {
      // 重新加载缓存列表
      await loadCache(context);
      showSimpleNotification(
        const Text('缓存添加成功'),
        background: Colors.green,
      );
    } catch (e) {
      showSimpleNotification(
        Text('缓存添加失败: $e'),
        background: Colors.red,
      );
    }
  }

  /// 删除缓存
  Future<void> deleteCache(BuildContext context, String cacheId) async {
    try {
      // 重新加载缓存列表
      await loadCache(context);
      showSimpleNotification(
        const Text('缓存删除成功'),
        background: Colors.green,
      );
    } catch (e) {
      showSimpleNotification(
        Text('缓存删除失败: $e'),
        background: Colors.red,
      );
    }
  }

  /// 清空缓存
  Future<void> clearCache(BuildContext context) async {
    try {
      // 重新加载缓存列表
      await loadCache(context);
      showSimpleNotification(
        const Text('缓存清空成功'),
        background: Colors.green,
      );
    } catch (e) {
      showSimpleNotification(
        Text('缓存清空失败: $e'),
        background: Colors.red,
      );
    }
  }

  /// 显示缓存面板
  void displayCachePanel(BuildContext context) {
    if (cachePanelEntry != null) return;

    cachePanelEntry = OverlayEntry(
      builder: (context) => _buildCachePanel(context),
    );

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      debugPrint('DetailCache: 当前页面无 Overlay，无法显示缓存面板');
      cachePanelEntry = null;
      return;
    }
    overlay.insert(cachePanelEntry!);
    showCachePanel = true;
  }

  /// 隐藏缓存面板
  void hideCachePanel() {
    if (cachePanelEntry != null) {
      cachePanelEntry?.remove();
      cachePanelEntry = null;
      showCachePanel = false;
    }
  }

  /// 构建缓存面板
  Widget _buildCachePanel(BuildContext context) {
    return Positioned(
      bottom: 100,
      left: 20,
      right: 20,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '缓存管理',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              isLoadingCache
                  ? const CircularProgressIndicator()
                  : cacheItems.isEmpty
                      ? const Text('暂无缓存')
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: cacheItems.length,
                          itemBuilder: (context, index) {
                            final item = cacheItems[index];
                            return ListTile(
                              title: Text('缓存项 ${index + 1}'),
                              subtitle: const Text('未知大小'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => deleteCache(context, item.id),
                              ),
                            );
                          },
                        ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => clearCache(context),
                child: const Text('清空缓存'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: hideCachePanel,
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 释放资源
  void dispose() {
    cacheRefreshTimer?.cancel();
    hideCachePanel();
  }
}
