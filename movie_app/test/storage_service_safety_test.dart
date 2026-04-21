import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/cache_item.dart';
import 'package:movie_app/models/favorite.dart';
import 'package:movie_app/models/play_source.dart';
import 'package:movie_app/models/playlist.dart';
import 'package:movie_app/models/user.dart';
import 'package:movie_app/models/watch_history.dart';
import 'package:movie_app/services/storage_service.dart';

void main() {
  group('StorageService safety without init', () {
    final storage = StorageService();

    test('read methods return safe defaults', () {
      expect(storage.getAllHistory(), isEmpty);
      expect(storage.getAllFavorites(), isEmpty);
      expect(storage.getAllCacheItems(), isEmpty);
      expect(storage.getAllSources(), isEmpty);
      expect(storage.getCurrentUser(), isNull);
      expect(storage.getSetting('missing'), isNull);
      expect(storage.getAllPlaylists(), isEmpty);
      expect(storage.isFavorite('m1'), isFalse);
      expect(storage.getHistory('m1'), isNull);
    });

    test('write methods do not throw', () async {
      final history = WatchHistory(
        id: 'h1',
        movieId: 'm1',
        sourceId: 's1',
        movieName: 'movie',
        episodeName: 'ep1',
        progress: 10,
        duration: 100,
        lastWatchTime: DateTime.now(),
      );
      final favorite = Favorite(
        id: 'f1',
        movieId: 'm1',
        sourceId: 's1',
        movieName: 'movie',
        movieCover: '',
        favoriteTime: DateTime.now(),
      );
      final cache = CacheItem(
        id: 'c1',
        movieId: 'm1',
        sourceId: 's1',
        movieName: 'movie',
        episodeName: 'ep1',
        url: 'https://example.com/v.mp4',
        status: 'downloading',
        createdAt: DateTime.now(),
      );
      final source = PlaySource(
        id: 's1',
        name: 'source',
        url: 'https://example.com',
      );
      final playlist = Playlist(
        id: 'p1',
        name: 'playlist',
        updatedAt: DateTime.now(),
        createdAt: DateTime.now(),
        items: const [],
      );

      await storage.saveHistory(history);
      await storage.deleteHistory('m1', sourceId: 's1');
      await storage.clearHistory();

      await storage.saveFavorite(favorite);
      await storage.deleteFavorite('m1', sourceId: 's1');
      await storage.clearFavorites();

      await storage.saveCacheItem(cache);
      await storage.deleteCacheItem('c1');
      await storage.clearCacheItems();

      await storage.saveSource(source);
      await storage.saveAllSources([source]);
      await storage.deleteSource('s1');
      await storage.clearSources();

      await storage.saveCurrentUser(User.guest());
      await storage.clearCurrentUser();

      await storage.saveSetting('k', 'v');
      await storage.saveBoolSetting('kb', true);
      await storage.saveIntSetting('ki', 1);
      await storage.saveDoubleSetting('kd', 1.5);

      await storage.savePlaylist(playlist);
      await storage.deletePlaylist('p1');

      expect(() => storage.exportAllData(), returnsNormally);
      expect(await storage.importData('{"invalid":true}'), isFalse);
    });
  });
}
