import 'package:flutter/material.dart';
import '../models/favorite.dart';
import '../models/movie.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import 'movie_provider.dart';

/// 收藏状态管理
class FavoriteProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();

  /// 收藏列表
  List<Favorite> _favorites = [];

  /// 收藏列表
  List<Favorite> get favorites => _favorites;

  /// 是否正在加载
  bool _isLoading = false;

  /// 是否正在加载
  bool get isLoading => _isLoading;

  /// 有更新的影片ID集合
  final Set<String> _updatedMovieIds = {};

  /// 有更新的影片ID集合
  Set<String> get updatedMovieIds => _updatedMovieIds;

  /// 影片更新集数映射（影片ID -> 新增集数）
  final Map<String, int> _updateCounts = {};

  /// 获取指定影片的更新集数
  int getUpdateCount(String movieId) {
    return _updateCounts[movieId] ?? 0;
  }

  /// 清除指定影片的更新计数
  void clearUpdateCount(String movieId) {
    if (_updateCounts.containsKey(movieId)) {
      _updateCounts.remove(movieId);
      _updatedMovieIds.remove(movieId);
      notifyListeners();
    }
  }

  /// 总更新数（所有影片的新增集数之和）
  int get totalUpdateCount {
    return _updateCounts.values.fold(0, (sum, count) => sum + count);
  }

  /// 初始化
  Future<void> init() async {
    await loadFavorites();
  }

  /// 加载收藏列表
  Future<void> loadFavorites() async {
    _isLoading = true;
    notifyListeners();

    _favorites = _storage.getAllFavorites();
    _isLoading = false;
    notifyListeners();
  }

  /// 添加收藏
  Future<void> addFavorite({
    required String movieId,
    required String movieName,
    required String movieCover,
    String sourceId = '',
    double rating = 0.0,
    List<String> genres = const [],
    String updateStatus = '',
  }) async {
    // 检查是否已收藏
    if (isFavorite(movieId, sourceId: sourceId)) return;

    final favorite = Favorite(
      id: '${sourceId}_$movieId',
      movieId: movieId,
      sourceId: sourceId,
      movieName: movieName,
      movieCover: movieCover,
      rating: rating,
      genres: genres,
      updateStatus: updateStatus,
    );

    await _storage.saveFavorite(favorite);
    _favorites.insert(0, favorite);
    notifyListeners();
  }

  /// 取消收藏
  Future<void> removeFavorite(String movieId, {String sourceId = ''}) async {
    if (!_favorites
        .any((f) => f.movieId == movieId && f.sourceId == sourceId)) {
      return;
    }
    await _storage.deleteFavorite(movieId, sourceId: sourceId);
    _favorites.removeWhere(
      (f) => f.movieId == movieId && f.sourceId == sourceId,
    );
    // 同时移除更新标记
    final key = '${sourceId}_$movieId';
    _updatedMovieIds.remove(key);
    _updateCounts.remove(key);
    notifyListeners();
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite({
    required String movieId,
    required String movieName,
    required String movieCover,
    String sourceId = '',
    double rating = 0.0,
    List<String> genres = const [],
    String updateStatus = '',
  }) async {
    if (isFavorite(movieId, sourceId: sourceId)) {
      await removeFavorite(movieId, sourceId: sourceId);
      return false;
    } else {
      await addFavorite(
        movieId: movieId,
        movieName: movieName,
        movieCover: movieCover,
        sourceId: sourceId,
        rating: rating,
        genres: genres,
        updateStatus: updateStatus,
      );
      return true;
    }
  }

  /// 检查是否已收藏
  bool isFavorite(String movieId, {String sourceId = ''}) {
    return _favorites.any(
      (f) => f.movieId == movieId && f.sourceId == sourceId,
    );
  }

  /// 检查指定影片是否有更新
  bool hasUpdate(String movieId, {String sourceId = ''}) {
    return _updatedMovieIds.contains('${sourceId}_$movieId');
  }

  /// 检查更新状态
  ///
  /// 对比收藏列表中保存的集数信息和API返回的最新影片信息。
  /// 如果API返回的集数更多，标记为"有更新"。
  void checkForUpdates(List<Movie> latestMovies) {
    _updatedMovieIds.clear();
    _updateCounts.clear();

    for (final fav in _favorites) {
      // 从最新影片列表中查找对应影片
      final latestMovie = latestMovies
          .where(
            (m) => m.id == fav.movieId && m.sourceId == fav.sourceId,
          )
          .firstOrNull;

      if (latestMovie != null) {
        // 对比集数：从 updateStatus 中提取集数信息
        final savedCount = _extractEpisodeCount(fav.updateStatus);
        final latestCount = _extractEpisodeCount(latestMovie.updateStatus);

        // 如果最新集数大于保存的集数，标记为有更新
        if (latestCount > savedCount && savedCount > 0) {
          final key = '${fav.sourceId}_${fav.movieId}';
          _updatedMovieIds.add(key);
          _updateCounts[key] = latestCount - savedCount;
        }
        // 如果更新状态发生了变化（如从"更新至第12集"变为"更新至第15集"）
        else if (fav.updateStatus != latestMovie.updateStatus &&
            latestMovie.updateStatus.isNotEmpty) {
          final latestCountNew = _extractEpisodeCount(latestMovie.updateStatus);
          final savedCountNew = _extractEpisodeCount(fav.updateStatus);
          if (latestCountNew > savedCountNew) {
            final key = '${fav.sourceId}_${fav.movieId}';
            _updatedMovieIds.add(key);
            _updateCounts[key] = latestCountNew - savedCountNew;
          }
        }
      }
    }

    if (_updatedMovieIds.isNotEmpty) {
      notifyListeners();
    }
  }

  /// 通过API请求检查收藏影片的更新（并发控制，每次最多3个请求）
  ///
  /// 遍历收藏列表，请求每个影片的最新详情，对比本地存储的总集数，
  /// 如果有更新则记录到 [_updateCounts]。
  Future<void> checkForUpdatesFromApi(MovieProvider movieProvider) async {
    if (_favorites.isEmpty) return;

    final api = movieProvider.apiService;

    _updateCounts.clear();
    _updatedMovieIds.clear();

    // 并发控制：每次最多3个请求，分批处理
    const maxConcurrent = 3;
    for (var i = 0; i < _favorites.length; i += maxConcurrent) {
      final batch = _favorites.skip(i).take(maxConcurrent).toList();
      await Future.wait(
        batch.map((fav) => _checkSingleUpdate(fav, api)),
      );
    }

    if (_updatedMovieIds.isNotEmpty) {
      notifyListeners();
    }
  }

  /// 检查单个收藏影片的更新
  Future<void> _checkSingleUpdate(Favorite fav, ApiService api) async {
    try {
      final movie = await api.getMovieDetail(fav.movieId);
      if (movie == null) return;

      final savedCount = _extractEpisodeCount(fav.updateStatus);
      final latestCount = _extractEpisodeCount(movie.updateStatus);

      if (latestCount > savedCount && savedCount > 0) {
        final key = '${fav.sourceId}_${fav.movieId}';
        _updatedMovieIds.add(key);
        _updateCounts[key] = latestCount - savedCount;
      } else if (fav.updateStatus != movie.updateStatus &&
          movie.updateStatus.isNotEmpty) {
        final latestCountNew = _extractEpisodeCount(movie.updateStatus);
        final savedCountNew = _extractEpisodeCount(fav.updateStatus);
        if (latestCountNew > savedCountNew) {
          final key = '${fav.sourceId}_${fav.movieId}';
          _updatedMovieIds.add(key);
          _updateCounts[key] = latestCountNew - savedCountNew;
        }
      }
    } catch (e) {
      debugPrint('检查更新失败: ${fav.movieName}, $e');
    }
  }

  /// 从更新状态文本中提取集数
  ///
  /// 支持格式：
  /// - "更新至第12集" -> 12
  /// - "共24集" -> 24
  /// - "HD中字" -> 0（电影）
  /// - "完结" -> 0
  int _extractEpisodeCount(String status) {
    if (status.isEmpty) return 0;

    // 匹配 "第XX集" 或 "更新至第XX集"
    final match1 = RegExp(r'第(\d+)集').firstMatch(status);
    if (match1 != null) {
      return int.tryParse(match1.group(1) ?? '') ?? 0;
    }

    // 匹配 "共XX集"
    final match2 = RegExp(r'共(\d+)集').firstMatch(status);
    if (match2 != null) {
      return int.tryParse(match2.group(1) ?? '') ?? 0;
    }

    // 匹配 "XX期"（综艺）
    final match3 = RegExp(r'(\d+)期').firstMatch(status);
    if (match3 != null) {
      return int.tryParse(match3.group(1) ?? '') ?? 0;
    }

    return 0;
  }

  /// 清空收藏
  Future<void> clearAll() async {
    await _storage.clearFavorites();
    _favorites.clear();
    _updatedMovieIds.clear();
    _updateCounts.clear();
    notifyListeners();
  }

  /// 收藏数量
  int get count => _favorites.length;

  /// 有更新的收藏数量
  int get updateCount => _updatedMovieIds.length;

  /// 获取指定影片的观看状态
  String getWatchStatus(String movieId, {String sourceId = ''}) {
    final fav = _favorites
        .where(
          (f) => f.movieId == movieId && f.sourceId == sourceId,
        )
        .firstOrNull;
    return fav?.watchStatus ?? '';
  }

  /// 设置影片的观看状态
  ///
  /// [status] 为 'want'（想看）、'watching'（在看）、'watched'（看过）或 ''（取消）
  Future<void> setWatchStatus(
    String movieId,
    String status, {
    String sourceId = '',
  }) async {
    final index = _favorites.indexWhere(
      (f) => f.movieId == movieId && f.sourceId == sourceId,
    );
    if (index < 0) return;

    final oldFav = _favorites[index];
    final newFav = oldFav.copyWith(watchStatus: status);
    _favorites[index] = newFav;
    await _storage.saveFavorite(newFav);
    notifyListeners();
  }
}
