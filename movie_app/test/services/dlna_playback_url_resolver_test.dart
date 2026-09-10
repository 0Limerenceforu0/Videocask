import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/dlna_playback_url_resolver.dart';
import 'package:movie_app/utils/lan_address.dart';

void main() {
  group('LanAddress', () {
    test('rewriteLocalHost replaces loopback host', () {
      expect(
        LanAddress.rewriteLocalHost(
          'http://127.0.0.1:8765/stream/1',
          '192.168.1.8',
        ),
        'http://192.168.1.8:8765/stream/1',
      );
    });
  });

  group('DlnaPlaybackUrlResolver', () {
    test('uses activeStreamUrl for magnet playback', () async {
      final resolver = DlnaPlaybackUrlResolver();
      final result = await resolver.resolve(
        currentPlayUrl: 'magnet-file://3',
        activeStreamUrl: 'http://127.0.0.1:8765/stream/3',
        movieId: 'm1',
        episodeIndex: 0,
      );
      expect(result.failure, DlnaResolveFailure.noLanIp);
    });

    test('rejects empty magnet stream without active url', () async {
      final resolver = DlnaPlaybackUrlResolver();
      final result = await resolver.resolve(
        currentPlayUrl: 'magnet-file://1',
        movieId: 'm1',
        episodeIndex: 0,
      );
      expect(result.failure, DlnaResolveFailure.noActiveStream);
    });
  });
}
