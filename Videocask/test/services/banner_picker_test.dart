import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/services/banner_picker.dart';

Movie _m(String id, {String? cover, double rating = 8.0, String typeName = ''}) {
  return Movie(
    id: id,
    name: '影片$id',
    cover: cover ?? 'http://x/$id.jpg',
    rating: rating,
    typeName: typeName,
  );
}

void main() {
  group('pickBannerMovies', () {
    test('输入已按评分降序时保持该顺序', () {
      final sorted = [
    _m('a', rating: 9.0),
    _m('b', rating: 8.0),
    _m('c', rating: 7.0),
  ];

      final picked = pickBannerMovies(sorted);

      expect(picked.map((m) => m.id).toList(), ['a', 'b', 'c']);
    });

test('跳过无封面条目，避免轮播视觉上都是空白块', () {
    final sorted = [
    _m('nocover', cover: ''),
        _m('ok1'),
        _m('norating', rating: 0),
        _m('ok2'),
        _m('ok3'),
      ];

      final picked = pickBannerMovies(sorted);

      // 可用条目只有 3 条（< limit=5），不足则按原顺序用其余条目补齐。
      expect(
picked.map((m) => m.id).toList(),
  ['ok1', 'ok2', 'ok3', 'nocover', 'norating'],
      );
    });

    test('可用条目足够时不混入无封面条目', () {
      final sorted = [
        _m('nocover', cover: ''),
        _m('a'),
        _m('b'),
        _m('c'),
        _m('d'),
        _m('e'),
        _m('f'),
      ];

      final picked = pickBannerMovies(sorted);

      expect(picked.map((m) => m.id).toList(), ['a', 'b', 'c', 'd', 'e']);
    });

    test('空白封面（仅空格）同样视为无封面', () {
      final sorted = [_m('blank', cover: '   '), _m('a'), _m('b')];

      final picked = pickBannerMovies(sorted, limit: 1);

      expect(picked.map((m) => m.id).toList(), ['a']);
    });

    test('limit 可调', () {
      final sorted = List.generate(10, (i) => _m('$i'));

      expect(pickBannerMovies(sorted, limit: 3).length, 3);
      expect(pickBannerMovies(sorted, limit: 0), isEmpty);
    });

    test('空输入返回空列表（类目无数据时轮播整块消失而非崩溃）', () {
      expect(pickBannerMovies(const []), isEmpty);
    });

    test('不修改入参列表', () {
      final sorted = [_m('nocover', cover: ''), _m('a')];

      pickBannerMovies(sorted, limit: 5);

      expect(sorted.map((m) => m.id).toList(), ['nocover', 'a']);
    });

    test('条目 id 重复时只取一次', () {
      final sorted = [_m('a'), _m('a')];

      final picked = pickBannerMovies(sorted, limit: 5);

      expect(picked.map((m) => m.id).toList(), ['a']);
    });
  });

  group('pickBannerMovies 类目过滤（2026-10-21 第七批）', () {
    // 背景：多源合并的类目列表会混进异类（实测 lzi「海外动漫」里有印度真人剧、
    // 某源「连续剧」里有动画电影）。按评分降序挑轮播时异类直接霸占 banner，
    // 用户看到「动漫 Tab 顶部放着剧集简介」。轮播候选必须先按类目过滤。

    test('异类高分会落选：动漫 Tab 的轮播不要真人剧', () {
      final sorted = [
        _m('drama', rating: 10.0, typeName: '连续剧'), // 异类：剧集混进动漫
        _m('anime1', rating: 9.0, typeName: '国产动漫'),
        _m('anime2', rating: 8.0, typeName: '日本动漫'),
      ];

      final picked = pickBannerMovies(sorted, category: '动漫');

      expect(picked.map((m) => m.id).toList(), ['anime1', 'anime2']);
    });

    test('剧集 Tab 过滤掉动画电影（type_name=动漫片/动画片）', () {
      final sorted = [
        _m('turbo', rating: 10.0, typeName: '动漫片'),
        _m('legit', rating: 9.0, typeName: '海外剧'),
      ];

      final picked = pickBannerMovies(sorted, category: '剧集');

      expect(picked.map((m) => m.id).toList(), ['legit']);
    });

    test('电影 Tab 保留动作片、排除纪录片与动漫', () {
      final sorted = [
        _m('doc', rating: 10.0, typeName: '记录片'),
        _m('anime', rating: 9.5, typeName: '动画片'),
        _m('action', rating: 9.0, typeName: '动作片'),
      ];

      final picked = pickBannerMovies(sorted, category: '电影');

      expect(picked.map((m) => m.id).toList(), ['action']);
    });

    test('type_name 为空的条目保留（未知 ≠ 不属于）', () {
      final sorted = [
        _m('unknown', rating: 10.0),
        _m('anime', rating: 9.0, typeName: '国产动漫'),
      ];

      final picked = pickBannerMovies(sorted, category: '动漫');

      expect(picked.map((m) => m.id).toList(), ['unknown', 'anime']);
    });

    test('全部被滤掉时退回全量（轮播消失比展示异类更糟）', () {
      final sorted = [
        _m('a', rating: 10.0, typeName: '连续剧'),
        _m('b', rating: 9.0, typeName: '欧美剧'),
      ];

      final picked = pickBannerMovies(sorted, category: '动漫');

      expect(picked.map((m) => m.id).toList(), ['a', 'b']);
    });

    test('category 为空（推荐页全站数据）时不过滤', () {
      final sorted = [
        _m('a', rating: 10.0, typeName: '连续剧'),
        _m('b', rating: 9.0, typeName: '动漫片'),
      ];

      final picked = pickBannerMovies(sorted);

      expect(picked.map((m) => m.id).toList(), ['a', 'b']);
    });

    test('短剧不混进剧集 Tab 轮播', () {
      final sorted = [
        _m('short', rating: 10.0, typeName: '爽文短剧'),
        _m('drama', rating: 9.0, typeName: '国产剧'),
      ];

      final picked = pickBannerMovies(sorted, category: '剧集');

      expect(picked.map((m) => m.id).toList(), ['drama']);
    });

    test('负向验证：不过滤时异类会赢（证明类目过滤有用）', () {
      final sorted = [
        _m('drama', rating: 10.0, typeName: '连续剧'),
        _m('anime1', rating: 9.0, typeName: '国产动漫'),
      ];

      // 不带 category = 不过滤的旧行为：异类直接当上 banner。
      final picked = pickBannerMovies(sorted);

      expect(picked.first.id, 'drama');
    });
  });
}