import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/services/person_works_merge.dart';

Movie _m(String name, {String year = '', String id = ''}) => Movie(
      id: id.isEmpty ? '$name-$year' : id,
      name: name,
      year: year,
    );

void main() {
  group('mergePersonWorks（代表作 + 关键词结果合并）', () {
    test('代表作排在前面：用户点进来看到的第一部就是精确命中', () {
      final merged = mergePersonWorks(
        [_m('功夫', year: '2004')],
        [_m('喜剧之王', year: '1999')],
      );
      expect(merged.map((e) => e.name).toList(), ['功夫', '喜剧之王']);
    });

    test('不覆盖：代表作 2 部 + 关键词 20 部 → 结果不能变少', () {
      final works = [_m('功夫', year: '2004'), _m('少林足球', year: '2001')];
      final keyword = [
        _m('功夫', year: '2004'),
        _m('少林足球', year: '2001'),
        for (var i = 0; i < 18; i++) _m('作品$i'),
      ];
      final merged = mergePersonWorks(works, keyword);
      // 两部重叠的只留一份：2 + 18。
      expect(merged.length, 20);
    });

    test('同一部片在不同线路下 id 不同也能去重（身份用片名+年份）', () {
      final merged = mergePersonWorks(
        [_m('功夫', year: '2004', id: 'lzi-1')],
        [_m('功夫', year: '2004', id: 'ffzy-9')],
      );
      expect(merged.length, 1);
      // 保留代表作那一条（id 来自代表作通道）。
      expect(merged.single.id, 'lzi-1');
    });

    test('同名不同年（翻拍）必须都留下', () {
      final merged = mergePersonWorks(
        [_m('喜剧之王', year: '1999')],
        [_m('喜剧之王', year: '2030')],
      );
      expect(merged.length, 2);
    });

    test('关键词结果为空时直接用代表作（人名通道抢在首屏之前的情况）', () {
      final works = [_m('功夫', year: '2004')];
      expect(mergePersonWorks(works, const []), works);
    });

    test('代表作为空时原样返回关键词结果（不把已有列表清空）', () {
      final keyword = [_m('功夫', year: '2004')];
      expect(mergePersonWorks(const [], keyword), same(keyword));
    });
  });
}
