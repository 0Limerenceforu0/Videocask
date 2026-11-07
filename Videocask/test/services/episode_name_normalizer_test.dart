import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/episode_name_normalizer.dart';

void main() {
  group('历史集名归一化（只改展示）', () {
    test('第01集 / 第001集 / 第 1 集 都收敛成 第1集', () {
      expect(normalizeEpisodeName('第01集'), '第1集');
      expect(normalizeEpisodeName('第001集'), '第1集');
      expect(normalizeEpisodeName('第 1 集'), '第1集');
    });

    test('两位数集数不被吃掉前导零以外的东西', () {
      expect(normalizeEpisodeName('第012集'), '第12集');
      expect(normalizeEpisodeName('第12集'), '第12集');
    });

    test('非「第N集」格式原样保留', () {
      expect(normalizeEpisodeName('EP01'), 'EP01');
      expect(normalizeEpisodeName('上集'), '上集');
      expect(normalizeEpisodeName(''), '');
      expect(normalizeEpisodeName('  第03集  '), '第3集');
    });

    test('一句里多个集名都能归一化', () {
      expect(
        normalizeEpisodeName('第01集-第02集 合集'),
        '第1集-第2集 合集',
      );
    });
  });
}
