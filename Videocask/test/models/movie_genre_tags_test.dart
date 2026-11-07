import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';

/// `Movie.genreTags` 的语义（2026-10-21）。
///
/// 背景：用户报「动漫筛选『热血』只剩两条」。实测 lzi / ffzy 的 `ac=list`
/// **不返回 `vod_class`**（只有 8 个字段，加 `h` 参数也无效），于是列表里
/// `genres` 只剩 `fromCmsJson` 插入的 `type_name`（如「国产动漫」）。
/// 拿「国产动漫」去比「热血」必然全不匹配 → 整个类目被清空。
///
/// `genreTags` 用来区分「站点给的真实类型」与「我们塞进去的分类名」。
void main() {
  group('Movie.genreTags', () {
    test('列表接口形态（无 vod_class）：genreTags 为空，genres 仍含分类名', () {
      final m = Movie.fromCmsJson(<String, dynamic>{
        'vod_id': 1,
        'vod_name': '某动漫',
        'type_name': '国产动漫',
        'vod_play_from': 'ffm3u8',
        'vod_play_url': '第1集\$http://x/1.m3u8',
      });

      expect(m.genreTags, isEmpty);
      expect(m.genres, contains('国产动漫'));
    });

    test('详情接口形态（有 vod_class）：genreTags 只含 vod_class，不含分类名', () {
      final m = Movie.fromCmsJson(<String, dynamic>{
        'vod_id': 2,
        'vod_name': '某番剧',
        'type_name': '日本动漫',
        'vod_class': '热血,战斗,校园',
        'vod_play_from': 'ffm3u8',
        'vod_play_url': '第1集\$http://x/1.m3u8',
      });

      expect(m.genreTags, ['热血', '战斗', '校园']);
      expect(m.genreTags, isNot(contains('日本动漫')));
      // genres 仍是展示用的完整列表（含分类名）。
      expect(m.genres, containsAll(<String>['热血', '战斗', '校园', '日本动漫']));
    });

    test('vod_class 为空字符串视为无类型信息', () {
      final m = Movie.fromCmsJson(<String, dynamic>{
        'vod_id': 3,
        'vod_name': 'X',
        'type_name': '欧美综艺',
        'vod_class': '',
        'vod_play_from': 'ffm3u8',
        'vod_play_url': '第1集\$http://x/1.m3u8',
      });

      expect(m.genreTags, isEmpty);
    });

    test('copyWith 保留 genreTags', () {
      final m = Movie.fromCmsJson(<String, dynamic>{
        'vod_id': 4,
        'vod_name': 'Y',
        'type_name': '动作片',
        'vod_class': '动作,犯罪',
        'vod_play_from': 'ffm3u8',
        'vod_play_url': '第1集\$http://x/1.m3u8',
      }).copyWith(sourceId: 'src');

      expect(m.sourceId, 'src');
      expect(m.genreTags, ['动作', '犯罪']);
    });

    test('手写构造的影片默认无类型信息（不误判筛选）', () {
      final m = Movie(id: '5', name: 'Z', genres: const ['动作']);

      expect(m.genreTags, isEmpty);
    });
  });

  group('Movie.typeName', () {
    test('解析 type_name，用于判断条目是否属于当前 Tab 类目', () {
      final m = Movie.fromCmsJson(<String, dynamic>{
        'vod_id': 6,
        'vod_name': '某海外动画',
        'type_name': '海外动漫',
        'vod_class': '动画,冒险',
        'vod_play_from': 'ffm3u8',
        'vod_play_url': '第1集\$http://x/1.m3u8',
      });

      expect(m.typeName, '海外动漫');
    });

    test('源不给 type_name 时为空串（调用方按「未知」放行）', () {
      final m = Movie.fromCmsJson(<String, dynamic>{
        'vod_id': 7,
        'vod_name': '无分类名',
        'vod_play_from': 'ffm3u8',
        'vod_play_url': '第1集\$http://x/1.m3u8',
      });

      expect(m.typeName, isEmpty);
    });

    test('copyWith 透传 typeName', () {
      final m = Movie.fromCmsJson(<String, dynamic>{
        'vod_id': 8,
        'vod_name': 'W',
        'type_name': '欧美剧',
        'vod_play_from': 'ffm3u8',
        'vod_play_url': '第1集\$http://x/1.m3u8',
      }).copyWith(sourceId: 'src');

      expect(m.typeName, '欧美剧');
      expect(m.copyWith(typeName: '日本剧').typeName, '日本剧');
    });
  });
}