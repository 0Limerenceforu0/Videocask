import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/playback_route_selector.dart';

void main() {
  group('PlaybackRouteSelector scoring', () {
    test('routeQualityScore ranks 4K above 标清', () {
      expect(
        PlaybackRouteSelector.routeQualityScore('4K超清'),
        greaterThan(PlaybackRouteSelector.routeQualityScore('标清流畅')),
      );
    });

    test('defaultQualityBonus matches configured clarity', () {
      expect(
        PlaybackRouteSelector.defaultQualityBonus('蓝光1080线路', '1080P'),
        greaterThan(0),
      );
      expect(
        PlaybackRouteSelector.defaultQualityBonus('标清', '1080P'),
        0,
      );
    });
  });
}
