import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/detail_playback_coordinator.dart';
import 'package:movie_app/pages/detail/playback/playback_lifecycle.dart';
import 'package:movie_app/pages/detail/playback/playhead_authority.dart';
import 'package:movie_app/pages/detail/playback/route_fallback_policy.dart';

void main() {
  group('PlayheadAuthority', () {
    test('authoritative monotonic on forward reports', () {
      final playhead = PlayheadAuthority();
      expect(playhead.ingest(const Duration(seconds: 10)),
          PlayheadTickAction.accept);
      expect(playhead.authoritative, const Duration(seconds: 10));
      expect(playhead.ingest(const Duration(seconds: 20)),
          PlayheadTickAction.accept);
      expect(playhead.authoritative, const Duration(seconds: 20));
    });

    test('discontinuity when mpv snaps near zero after long watch', () {
      final playhead = PlayheadAuthority();
      playhead.setExplicit(const Duration(minutes: 8));
      expect(
        playhead.ingest(Duration.zero),
        PlayheadTickAction.discontinuity,
      );
      expect(playhead.authoritative, const Duration(minutes: 8));
    });

    test('preserveForMediaSwitch returns null near end', () {
      final playhead = PlayheadAuthority();
      playhead.setExplicit(const Duration(minutes: 59, seconds: 58));
      expect(
        playhead.preserveForMediaSwitch(
          duration: const Duration(hours: 1),
        ),
        isNull,
      );
    });

    test('isPrematureComplete detects short HLS duration', () {
      final playhead = PlayheadAuthority();
      playhead.setExplicit(const Duration(minutes: 5));
      expect(
        playhead.isPrematureComplete(const Duration(minutes: 6)),
        isTrue,
      );
    });
  });

  group('RouteFallbackPolicy', () {
    test('blocks during opening and after stable watch', () {
      expect(
        RouteFallbackPolicy.allow(
          lifecycle: PlaybackLifecycle.opening,
          authoritativePosition: Duration.zero,
          isMagnet: false,
          isApplyingResume: false,
          hasPendingResume: false,
        ),
        isFalse,
      );
      expect(
        RouteFallbackPolicy.allow(
          lifecycle: PlaybackLifecycle.playing,
          authoritativePosition: const Duration(minutes: 5),
          isMagnet: false,
          isApplyingResume: false,
          hasPendingResume: false,
        ),
        isFalse,
      );
    });

    test('allows early buffering fallback', () {
      expect(
        RouteFallbackPolicy.allow(
          lifecycle: PlaybackLifecycle.playing,
          authoritativePosition: const Duration(minutes: 1),
          isMagnet: false,
          isApplyingResume: false,
          hasPendingResume: false,
        ),
        isTrue,
      );
    });
  });

  group('DetailPlaybackCoordinator', () {
    test('prepareOpen preserves playhead on route switch', () {
      final coordinator = DetailPlaybackCoordinator();
      coordinator.session.playhead.setExplicit(const Duration(minutes: 12));

      final plan = coordinator.prepareOpen(
        isNewEpisode: false,
        explicitPreserve: const Duration(minutes: 12),
      );

      expect(plan.startAt, const Duration(minutes: 12));
      expect(coordinator.lifecycle, PlaybackLifecycle.opening);
      expect(coordinator.authoritativePosition, const Duration(minutes: 12));
    });

    test('prepareOpen resets playhead for new episode', () {
      final coordinator = DetailPlaybackCoordinator();
      coordinator.session.playhead.setExplicit(const Duration(minutes: 12));

      coordinator.prepareOpen(isNewEpisode: true);

      expect(coordinator.authoritativePosition, Duration.zero);
    });
  });
}
