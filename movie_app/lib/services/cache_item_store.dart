import '../models/cache_item.dart';
import 'storage_service.dart';

/// 缓存任务持久化抽象（便于单测注入内存实现）。
abstract class CacheItemStore {
  List<CacheItem> getAllCacheItems();
  Future<void> saveCacheItem(CacheItem item);
  Future<void> deleteCacheItem(String id);
  Future<void> clearCacheItems();
  bool getBoolSetting(String key, {required bool defaultValue});
  Future<void> saveBoolSetting(String key, bool value);
}

/// 生产环境：委托 [StorageService]。
class StorageCacheItemStore implements CacheItemStore {
  StorageCacheItemStore([StorageService? storage])
      : _storage = storage ?? StorageService();

  final StorageService _storage;

  @override
  List<CacheItem> getAllCacheItems() => _storage.getAllCacheItems();

  @override
  Future<void> saveCacheItem(CacheItem item) => _storage.saveCacheItem(item);

  @override
  Future<void> deleteCacheItem(String id) => _storage.deleteCacheItem(id);

  @override
  Future<void> clearCacheItems() => _storage.clearCacheItems();

  @override
  bool getBoolSetting(String key, {required bool defaultValue}) =>
      _storage.getBoolSetting(key, defaultValue: defaultValue);

  @override
  Future<void> saveBoolSetting(String key, bool value) =>
      _storage.saveBoolSetting(key, value);
}

/// 测试用内存存储。
class InMemoryCacheItemStore implements CacheItemStore {
  final Map<String, CacheItem> _items = {};
  final Map<String, bool> _bools = {};

  @override
  List<CacheItem> getAllCacheItems() => _items.values.toList();

  @override
  Future<void> saveCacheItem(CacheItem item) async {
    _items[item.id] = item;
  }

  @override
  Future<void> deleteCacheItem(String id) async {
    _items.remove(id);
  }

  @override
  Future<void> clearCacheItems() async {
    _items.clear();
  }

  @override
  bool getBoolSetting(String key, {required bool defaultValue}) {
    return _bools[key] ?? defaultValue;
  }

  @override
  Future<void> saveBoolSetting(String key, bool value) async {
    _bools[key] = value;
  }

  CacheItem? item(String id) => _items[id];
}
