import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/utils/title_relevance.dart';

Movie _movie(String name, {String year = '', String id = ''}) => Movie(
      id: id.isEmpty ? name : id,
      name: name,
      year: year,
    );

void main() {
  group('TitleRelevance.normalize', () {
    test('去掉书名号、括号、空白与标点', () {
      expect(TitleRelevance.normalize('《功夫》'), '功夫');
      expect(TitleRelevance.normalize('蜘蛛侠：英雄归来'), '蜘蛛侠英雄归来');
      expect(TitleRelevance.normalize('007 别传'), '007别传');
      expect(TitleRelevance.normalize('  '), '');
    });
  });

  group('TitleRelevance.isRelated', () {
    test('片名含查询词 → 相关', () {
      expect(TitleRelevance.isRelated('功夫', '功夫'), isTrue);
      expect(TitleRelevance.isRelated('功夫女足', '功夫'), isTrue);
      expect(TitleRelevance.isRelated('《功夫》', '功夫'), isTrue);
    });

    test('查询词含片名（简称）→ 相关', () {
      expect(TitleRelevance.isRelated('武状元苏乞儿', '苏乞儿'), isTrue);
    });

    test('采集站的相关推荐噪声 → 无关', () {
      // 2026-10-28 实测：搜「周星驰」时源站 wd= 返回这三条。
      expect(TitleRelevance.isRelated('007别传', '周星驰'), isFalse);
      expect(TitleRelevance.isRelated('小不列颠', '周星驰'), isFalse);
      expect(TitleRelevance.isRelated('情圣2016', '周星驰'), isFalse);
    });

    test('单字片名不做包含匹配，避免把整页都收进来', () {
      expect(TitleRelevance.isRelated('功夫', '夫'), isFalse);
      expect(TitleRelevance.isRelated('夫', '夫'), isTrue);
    });

    test('空查询 / 空片名 → 无关（不能全放行也不能全杀）', () {
      expect(TitleRelevance.isRelated('功夫', ''), isFalse);
      expect(TitleRelevance.isRelated('', '功夫'), isFalse);
    });
  });

  group('TitleRelevance.split', () {
    test('噪声进 others，正片进 primary，且一条都不丢', () {
      final movies = [
        _movie('功夫'),
        _movie('007别传'),
        _movie('功夫女足'),
        _movie('小不列颠'),
      ];
      final split = TitleRelevance.split(movies, '功夫');
      expect(split.primary.map((m) => m.name), ['功夫', '功夫女足']);
      expect(split.others.map((m) => m.name), ['007别传', '小不列颠']);
      expect(split.total, movies.length);
    });

    test('人名通道的可信片名即使不含查询词也留在主列表', () {
      final movies = [_movie('功夫'), _movie('喜剧之王')];
      final split = TitleRelevance.split(
        movies,
        '周星驰',
        trusted: {TitleRelevance.normalize('功夫'), TitleRelevance.normalize('喜剧之王')},
      );
      expect(split.primary.length, 2);
      expect(split.others, isEmpty);
    });

    test('源站片名带后缀时按「相关」匹配可信库（《喜剧之王》→《喜剧之王1999》）', () {
      final movies = [_movie('喜剧之王1999'), _movie('007别传')];
      final split = TitleRelevance.split(
        movies,
        '周星驰',
        trusted: {TitleRelevance.normalize('喜剧之王')},
      );
      expect(split.primary.map((m) => m.name), ['喜剧之王1999']);
      expect(split.others.map((m) => m.name), ['007别传']);
    });

    test('电影先出后剧集追加时，两阶段的片名都要算可信', () {
      final split = TitleRelevance.split(
        [_movie('功夫'), _movie('鹿鼎记')],
        '周星驰',
        trusted: {TitleRelevance.normalize('功夫'), TitleRelevance.normalize('鹿鼎记')},
      );
      expect(split.primary.map((m) => m.name), ['功夫', '鹿鼎记']);
    });

    test('空列表返回空拆分', () {
      final split = TitleRelevance.split(const [], '功夫');
      expect(split.isEmpty, isTrue);
      expect(split.total, 0);
    });
  });
}
