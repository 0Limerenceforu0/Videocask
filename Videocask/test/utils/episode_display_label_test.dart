import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/utils/episode_display_label.dart';

void main() {
  group('EpisodeDisplayLabel.forEpisode', () {
    test('empty name falls back to index', () {
      final label = EpisodeDisplayLabel.forEpisode(name: '', index: 4);
      expect(label.primary, '5');
      expect(label.full, '5');
      expect(label.secondary, isNull);
    });

    test('extracts 第N期 from long variety title', () {
      final label = EpisodeDisplayLabel.forEpisode(
        name: '奔跑吧兄弟 20250101期 第12期 嘉宾特辑',
        index: 0,
      );
      expect(label.primary, '第12期');
      expect(label.full, '奔跑吧兄弟 20250101期 第12期 嘉宾特辑');
      expect(label.secondary, isNotNull);
    });

    test('extracts 第N集', () {
      final label = EpisodeDisplayLabel.forEpisode(
        name: '某某剧 第3集 高清',
        index: 0,
      );
      expect(label.primary, '第3集');
    });

    test('extracts S01E05', () {
      final label = EpisodeDisplayLabel.forEpisode(
        name: 'Show.Name.S01E05.1080p',
        index: 0,
      );
      expect(label.primary, 'S01 E05');
    });

    test('extracts date from title', () {
      final label = EpisodeDisplayLabel.forEpisode(
        name: '2025-03-08期 快乐大本营',
        index: 0,
      );
      expect(label.primary, '2025-03-08');
    });

    test('short name used as primary', () {
      final label = EpisodeDisplayLabel.forEpisode(name: '预告', index: 0);
      expect(label.primary, '预告');
      expect(label.secondary, isNull);
    });

    test('long name without pattern uses index as primary', () {
      final label = EpisodeDisplayLabel.forEpisode(
        name: '这是一段没有任何期数标记的超长综艺标题名称',
        index: 6,
      );
      expect(label.primary, '7');
      expect(label.secondary, isNotNull);
    });
  });

  group('EpisodeDisplayLabel.episodesPreferListLayout', () {
    test('true when any episode has long variety title', () {
      final episodes = [
        Episode(index: 0, name: '第1集', url: 'u'),
        Episode(
          index: 1,
          name: '奔跑吧兄弟 20250101期 第12期 嘉宾特辑',
          url: 'u',
        ),
      ];
      expect(EpisodeDisplayLabel.episodesPreferListLayout(episodes), isTrue);
    });

    test('false for short numbered episodes', () {
      final episodes = List.generate(
        12,
        (i) => Episode(index: i, name: '第${i + 1}集', url: 'u'),
      );
      expect(EpisodeDisplayLabel.episodesPreferListLayout(episodes), isFalse);
    });
  });
}
