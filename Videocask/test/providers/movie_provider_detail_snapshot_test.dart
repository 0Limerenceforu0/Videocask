import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/providers/movie_provider.dart';

void main() {
  group('MovieProvider detail snapshot', () {
    test('push and pop restore CMS detail after magnet overlay', () {
      final provider = MovieProvider();
      final cms = Movie(id: '42', sourceId: 'src1', name: 'CMS 影片');
      provider.completeDetailWithMovie(cms);

      provider.pushDetailSnapshot();
      provider.primeDetailLoad('magnet_btih');
      provider.completeDetailWithMovie(
        Movie(
          id: 'magnet_btih',
          sourceId: 'magnet',
          name: '磁力占位',
        ),
      );

      expect(provider.currentMovie?.id, 'magnet_btih');

      provider.popDetailSnapshot();

      expect(provider.currentMovie?.id, '42');
      expect(provider.currentMovie?.name, 'CMS 影片');
      expect(provider.errorMessage, isEmpty);
      expect(provider.isLoadingDetail, isFalse);
    });
  });
}
