import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/search_intent_service.dart';

Map<String, dynamic> _entry(
  List<String> roles, {
  String type = 'movie',
  String title = '功夫',
  String year = '2004',
}) =>
    <String, dynamic>{
      'roles': roles,
      'work': <String, dynamic>{
        'type': type,
        'title': title,
        'year': year,
      },
    };

void main() {
  group('parseWorkEntry（豆瓣作品全集 → 他参演的电影）', () {
    test('「演员 (饰 宋兵甲)」这种龙套也算他的作品', () {
      final w = SearchIntentService.parseWorkEntry(
        _entry(['演员 (饰 宋兵甲)'], title: '射雕英雄传', year: '1983'),
      );
      expect(w?.title, '射雕英雄传');
      expect(w?.year, '1983');
    });

    test('纯「演员 - 自己」是不算作品（哪怕标成电影）', () {
      final w = SearchIntentService.parseWorkEntry(
        _entry(['演员 - 自己'], title: '锵锵三人行', year: '1998'),
      );
      expect(w, isNull);
    });

    test('纯「演员 - 嘉宾」同样剔除', () {
      expect(
        SearchIntentService.parseWorkEntry(
          _entry(['演员 - 嘉宾'], title: '看见', year: '2010'),
        ),
        isNull,
      );
    });

    test('混合身份（演员 + 导演 + 监制）保留：这部片他确实演了', () {
      final w = SearchIntentService.parseWorkEntry(
        _entry(['演员 (饰 星)', '音乐', '导演', '制片人 - 监制']),
      );
      expect(w?.title, '功夫');
    });

    test('纯幕后（导演/编剧/监制）也算作品（2026-10-28 用户要求）', () {
      final w = SearchIntentService.parseWorkEntry(
        _entry(['导演', '编剧', '制片人 - 监制'], title: '美人鱼', year: '2016'),
      );
      expect(w?.title, '美人鱼');
      expect(w?.year, '2016');
    });

    test('只有导演身份、自己没演的也保留（西游降魔篇 / 新喜剧之王）', () {
      expect(
        SearchIntentService.parseWorkEntry(
          _entry(['导演'], title: '西游降魔篇', year: '2013'),
        )?.title,
        '西游降魔篇',
      );
    });

    test('导演 + 本色出镜混合：有非本色身份就留', () {
      expect(
        SearchIntentService.parseWorkEntry(
          _entry(['导演', '演员 - 自己'], title: '美人鱼', year: '2016'),
        )?.title,
        '美人鱼',
      );
    });

    test('roles 为空时保留（老片豆瓣没标身份，丢掉会漏片）', () {
      expect(
        SearchIntentService.parseWorkEntry(_entry(const [], title: '霹雳先锋'))?.title,
        '霹雳先锋',
      );
    });

    test('默认只取电影，剧集要显式 includeTv', () {
      final tv = _entry(['演员 (饰 韦小宝)'], type: 'tv', title: '鹿鼎记', year: '1984');
      expect(SearchIntentService.parseWorkEntry(tv), isNull);
      expect(
        SearchIntentService.parseWorkEntry(tv, includeTv: true)?.title,
        '鹿鼎记',
      );
    });

    test('剧集条目带 isTv 标记，供「电影先出、剧集后补」分阶段检索', () {
      final tv = _entry(['演员 (饰 韦小宝)'], type: 'tv', title: '鹿鼎记', year: '1984');
      final movie = _entry(['演员'], type: 'movie', title: '功夫', year: '2004');
      expect(SearchIntentService.parseWorkEntry(tv, includeTv: true)?.isTv, isTrue);
      expect(SearchIntentService.parseWorkEntry(movie)?.isTv, isFalse);
    });

    test('includeTv 时综艺（type=show）也收，纪录片按电影收', () {
      final show = _entry(['嘉宾'], type: 'show', title: '周星驰的综艺');
      // 纯「嘉宾」身份会被当成本色出镜剔掉，这里只验类型闸门。
      expect(SearchIntentService.parseWorkEntry(show, includeTv: true), isNull);
      final doc = _entry(['导演'], type: 'movie', title: '纪录片作品');
      expect(
        SearchIntentService.parseWorkEntry(doc)?.isTv,
        isFalse,
        reason: '纪录片在豆瓣的 type 就是 movie，不能被任何类型闸门砍掉',
      );
    });

    test('未上映的占位年份（2030/2040）不算作品', () {
      expect(
        SearchIntentService.parseWorkEntry(_entry(['演员'], year: '2030')),
        isNull,
      );
      expect(
        SearchIntentService.parseWorkEntry(_entry(['演员'], year: '2040')),
        isNull,
      );
    });

    test('年份缺失时保留（老片常没有），只清空 year 字段', () {
      final w = SearchIntentService.parseWorkEntry(_entry(['演员'], year: ''));
      expect(w, isNotNull);
      expect(w!.year, '');
    });

    test('片名为空 / work 结构异常 → null（不抛异常）', () {
      expect(SearchIntentService.parseWorkEntry(_entry(['演员'], title: '')), isNull);
      expect(
        SearchIntentService.parseWorkEntry(<String, dynamic>{'roles': ['演员']}),
        isNull,
      );
    });
  });
}
