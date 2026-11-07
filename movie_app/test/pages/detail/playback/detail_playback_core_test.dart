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

    test('凭空前跳（PTS 跳变）同样判 discontinuity，进度不被弹走', () {
      final playhead = PlayheadAuthority();
      final t0 = DateTime(2026, 11, 5, 12, 0, 0);
      playhead.setExplicit(const Duration(minutes: 5));
      // 200ms 后 mpv 突然报 5 分钟之后的位置 —— 真实时间解释不了
      expect(
        playhead.ingest(
          const Duration(minutes: 10),
          now: t0.add(const Duration(milliseconds: 200)),
        ),
        PlayheadTickAction.discontinuity,
      );
      expect(playhead.authoritative, const Duration(minutes: 5));
    });

    test('正常 2x 播放的前进不被误判', () {
      final playhead = PlayheadAuthority();
      final t0 = DateTime(2026, 11, 5, 12, 0, 0);
      playhead
        ..setExplicit(const Duration(minutes: 5))
        ..ingest(const Duration(minutes: 5), now: t0);
      // 1 秒后到 5:02（2x），属于可解释范围
      expect(
        playhead.ingest(
          const Duration(minutes: 5, seconds: 2),
          now: t0.add(const Duration(seconds: 1)),
        ),
        PlayheadTickAction.accept,
      );
      expect(playhead.authoritative, const Duration(minutes: 5, seconds: 2));
    });

    test('切后台挂起后的一次性补报不被当成跳变（按墙钟放宽）', () {
      final playhead = PlayheadAuthority();
      final t0 = DateTime(2026, 11, 5, 12, 0, 0);
      playhead
        ..setExplicit(const Duration(minutes: 5))
        ..ingest(const Duration(minutes: 5), now: t0);
      // 5 分钟没上报，回前台第一条直接到 10:00 —— 这是真进度，必须接受
      expect(
        playhead.ingest(
          const Duration(minutes: 10),
          now: t0.add(const Duration(minutes: 5)),
        ),
        PlayheadTickAction.accept,
      );
      expect(playhead.authoritative, const Duration(minutes: 10));
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

  group('adoptPlayerPosition', () {
    test('续播点失效导致权威值脱节时对齐到实际上报', () {
      final coordinator = DetailPlaybackCoordinator();
      // 权威值钉在失效的旧续播点（2944s），播放器实际从头播到 167s。
      coordinator.session.playhead.setExplicit(const Duration(seconds: 2944));

      final changed = coordinator.adoptPlayerPosition(
        const Duration(seconds: 167),
      );

      expect(changed, isTrue);
      expect(coordinator.authoritativePosition, const Duration(seconds: 167));
    });

    test('偏差在容差内视为抖动不改写', () {
      final coordinator = DetailPlaybackCoordinator();
      coordinator.session.playhead.setExplicit(const Duration(seconds: 600));

      final changed = coordinator.adoptPlayerPosition(
        const Duration(seconds: 603),
      );

      expect(changed, isFalse);
      expect(coordinator.authoritativePosition, const Duration(seconds: 600));
    });

    test('播放器尚未上报(0)时忽略', () {
      final coordinator = DetailPlaybackCoordinator();
      coordinator.session.playhead.setExplicit(const Duration(seconds: 600));

      final changed = coordinator.adoptPlayerPosition(Duration.zero);

      expect(changed, isFalse);
      expect(coordinator.authoritativePosition, const Duration(seconds: 600));
    });

    test('容差大于偏差时拒绝采纳（迟到的小幅旧位置不拽回用户）', () {
      final coordinator = DetailPlaybackCoordinator();
      // 用户刚拖到 27:00，mpv 稍后可能先报出略旧的 26:30。
      coordinator.session.playhead.setExplicit(const Duration(minutes: 27));

      final changed = coordinator.adoptPlayerPosition(
        const Duration(minutes: 26, seconds: 30),
        tolerance: const Duration(minutes: 1),
      );

      expect(changed, isFalse);
      expect(coordinator.authoritativePosition, const Duration(minutes: 27));
    });

    test('偏差远超容差时仍采纳（续播点彻底失效的兜底）', () {
      final coordinator = DetailPlaybackCoordinator();
      coordinator.session.playhead.setExplicit(const Duration(minutes: 27));

      final changed = coordinator.adoptPlayerPosition(
        const Duration(minutes: 3),
        tolerance: const Duration(minutes: 1),
      );

      expect(changed, isTrue);
      expect(coordinator.authoritativePosition, const Duration(minutes: 3));
    });
  });
}
