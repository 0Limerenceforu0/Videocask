import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/search_type_word.dart';

void main() {
  group('SearchTypeWord.categoryOf 一级分类词', () {
    test('标准分类词命中', () {
      expect(SearchTypeWord.categoryOf('电影'), '电影');
      expect(SearchTypeWord.categoryOf('剧集'), '剧集');
      expect(SearchTypeWord.categoryOf('动漫'), '动漫');
      expect(SearchTypeWord.categoryOf('综艺'), '综艺');
      expect(SearchTypeWord.categoryOf('纪录片'), '纪录片');
      expect(SearchTypeWord.categoryOf('短剧'), '短剧');
    });

    test('别名命中（用户更常搜的词）', () {
      expect(SearchTypeWord.categoryOf('电视剧'), '剧集');
      expect(SearchTypeWord.categoryOf('连续剧'), '剧集');
      expect(SearchTypeWord.categoryOf('美剧'), '剧集');
      expect(SearchTypeWord.categoryOf('韩剧'), '剧集');
      expect(SearchTypeWord.categoryOf('动画'), '动漫');
      expect(SearchTypeWord.categoryOf('动画片'), '动漫');
      expect(SearchTypeWord.categoryOf('番剧'), '动漫');
      expect(SearchTypeWord.categoryOf('记录片'), '纪录片');
      expect(SearchTypeWord.categoryOf('真人秀'), '综艺');
    });

    test('带空白的输入先 trim', () {
      expect(SearchTypeWord.categoryOf('  动漫  '), '动漫');
    });

    test('片名不得误判为分类词（子串不命中）', () {
      // 「喜剧之王」含「喜剧」，但整词不是分类/类型词 → 普通片名搜索。
      expect(SearchTypeWord.categoryOf('喜剧之王'), isNull);
      expect(SearchTypeWord.categoryOf('流浪地球'), isNull);
      expect(SearchTypeWord.categoryOf('海贼王'), isNull);
      expect(SearchTypeWord.categoryOf('动漫之城'), isNull);
      expect(SearchTypeWord.categoryOf(''), isNull);
    });

    test('普通词返回 null', () {
      expect(SearchTypeWord.categoryOf('周星驰'), isNull);
      expect(SearchTypeWord.categoryOf('复仇者联盟'), isNull);
    });
  });

  group('SearchTypeWord.genreOf 细分类型词', () {
    test('标准类型词命中', () {
      expect(SearchTypeWord.genreOf('动作'), '动作');
      expect(SearchTypeWord.genreOf('喜剧'), '喜剧');
      expect(SearchTypeWord.genreOf('爱情'), '爱情');
      expect(SearchTypeWord.genreOf('科幻'), '科幻');
      expect(SearchTypeWord.genreOf('悬疑'), '悬疑');
      expect(SearchTypeWord.genreOf('恐怖'), '恐怖');
    });

    test('「片」后缀写法命中主干', () {
      expect(SearchTypeWord.genreOf('动作片'), '动作');
      expect(SearchTypeWord.genreOf('科幻片'), '科幻');
      expect(SearchTypeWord.genreOf('爱情片'), '爱情');
    });

    test('分类词优先于类型词（不返回 genre）', () {
      // 「动画」是分类词（→ 动漫），不是类型词。
      expect(SearchTypeWord.genreOf('动画'), isNull);
      expect(SearchTypeWord.genreOf('动漫'), isNull);
      expect(SearchTypeWord.genreOf('电影'), isNull);
    });

    test('去掉后缀后不在词表的原样返回（不误削片名）', () {
      // 「红楼梦」去「楼」不在任何表 → 不是类型词。
      expect(SearchTypeWord.genreOf('红楼梦'), isNull);
      expect(SearchTypeWord.genreOf('恐怖片'), '恐怖');
      expect(SearchTypeWord.genreOf(''), isNull);
    });
  });
}
