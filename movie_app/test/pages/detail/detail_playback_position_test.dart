import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/detail_player.dart';
import 'package:movie_app/pages/detail/playback/playhead_authority.dart';

void main() {
  group('DetailPlayer playback position preserve', () {
    test('uses authoritative playhead when position drops', () {
      final player = DetailPlayer();
      player.playback.confirmExplicitPosition(const Duration(minutes: 45));
      player.duration = const Duration(hours: 1);
      player.position = Duration.zero;

      expect(
        player.playbackPositionToPreserve(),
        const Duration(minutes: 45),
      );
    });

    test('returns null near end', () {
      final player = DetailPlayer();
      player.playback.confirmExplicitPosition(
        const Duration(minutes: 59, seconds: 58),
      );
      player.duration = const Duration(hours: 1);

      expect(player.playbackPositionToPreserve(), isNull);
    });

    test('ingest detects discontinuity snap-back', () {
      final player = DetailPlayer();
      player.playback.confirmExplicitPosition(const Duration(minutes: 8));

      expect(
        player.playback.ingestPlayerPosition(Duration.zero),
        PlayheadTickAction.discontinuity,
      );
    });

    test('resetResumeConsumeForNewOpen keeps playhead when preserving', () {
      final player = DetailPlayer();
      player.playback.confirmExplicitPosition(const Duration(minutes: 12));

      player.resetResumeConsumeForNewOpen(
        preservePeak: const Duration(minutes: 12),
      );

      expect(player.peakPlaybackPosition, const Duration(minutes: 12));
    });
  });
}
