import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../services/storage_service.dart';

/// 播放列表状态管理
class PlaylistProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();

  /// 播放列表集合
  List<Playlist> _playlists = [];

  /// 播放列表集合
  List<Playlist> get playlists => _playlists;

  /// 是否正在加载
  bool _isLoading = false;

  /// 是否正在加载
  bool get isLoading => _isLoading;

  /// 初始化
  Future<void> init() async {
    await loadPlaylists();
  }

  /// 加载所有播放列表
  Future<void> loadPlaylists() async {
    _isLoading = true;
    notifyListeners();

    _playlists = _storage.getAllPlaylists();
    _isLoading = false;
    notifyListeners();
  }

  /// 获取所有播放列表
  List<Playlist> getPlaylists() => _playlists;

  /// 根据ID获取播放列表
  Playlist? getPlaylist(String id) {
    try {
      return _playlists.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 创建播放列表
  Future<Playlist> createPlaylist(String name) async {
    final now = DateTime.now();
    final playlist = Playlist(
      id: now.millisecondsSinceEpoch.toString(),
      name: name,
      items: [],
      createdAt: now,
      updatedAt: now,
    );

    await _storage.savePlaylist(playlist);
    _playlists.insert(0, playlist);
    notifyListeners();
    return playlist;
  }

  /// 删除播放列表
  Future<void> deletePlaylist(String id) async {
    await _storage.deletePlaylist(id);
    _playlists.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  /// 重命名播放列表
  Future<void> renamePlaylist(String id, String name) async {
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index == -1) return;

    final updated = _playlists[index].copyWith(
      name: name,
      updatedAt: DateTime.now(),
    );

    await _storage.savePlaylist(updated);
    _playlists[index] = updated;
    notifyListeners();
  }

  /// 向播放列表添加影片
  Future<void> addItem(String playlistId, PlaylistItem item) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;

    // 检查是否已存在
    final exists = _playlists[index].items.any(
          (i) => i.movieId == item.movieId && i.sourceId == item.sourceId,
        );
    if (exists) return;

    final newItems = [..._playlists[index].items, item];
    final updated = _playlists[index].copyWith(
      items: newItems,
      updatedAt: DateTime.now(),
    );

    await _storage.savePlaylist(updated);
    _playlists[index] = updated;
    notifyListeners();
  }

  /// 从播放列表移除影片
  Future<void> removeItem(String playlistId, String movieId) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;

    final newItems =
        _playlists[index].items.where((i) => i.movieId != movieId).toList();
    final updated = _playlists[index].copyWith(
      items: newItems,
      updatedAt: DateTime.now(),
    );

    await _storage.savePlaylist(updated);
    _playlists[index] = updated;
    notifyListeners();
  }

  /// 重新排序播放列表中的影片
  Future<void> reorderItems(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;

    final items = List<PlaylistItem>.from(_playlists[index].items);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);

    final updated = _playlists[index].copyWith(
      items: items,
      updatedAt: DateTime.now(),
    );

    await _storage.savePlaylist(updated);
    _playlists[index] = updated;
    notifyListeners();
  }

  /// 检查影片是否在指定播放列表中
  bool isItemInPlaylist(
    String playlistId,
    String movieId, {
    String sourceId = '',
  }) {
    final playlist = getPlaylist(playlistId);
    if (playlist == null) return false;
    return playlist.items.any(
      (i) => i.movieId == movieId && i.sourceId == sourceId,
    );
  }

  /// 播放列表数量
  int get count => _playlists.length;
}
