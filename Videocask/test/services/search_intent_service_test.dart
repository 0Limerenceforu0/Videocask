import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/search_intent_service.dart';

/// 「搜索框要同时认得片名、人名、类型、分类」的契约测试。
///
/// 背景（2026-10-28 用户反馈）：
/// 为了修「搜《死侍》出《战狼》」，给搜索结果加了一道片名相关性过滤，
/// 结果搜「周星驰」「科幻」全部 0 条。用户原话是「你怎么跟二极管一样，
/// 没有方案能完美平衡吗」。
///
/// 平衡方案 = 先判断查询语义，再选通道与过滤字段：
/// * 分类词 / 类型词 —— 本地词表识别，走分类或类型子类通道；
/// * 人名 —— 豆瓣联想识别（`type=celebrity` 且标题完全等于关键词），
///   拿它的代表作逐部按片名搜；
/// * 其余 —— 片名，严格过滤（严格为 0 时上层放宽一档）。
void main() {
  group('looksLikePersonName：哪些词值得问一次豆瓣', () {
    test('2~6 个汉字的中文人名 → 值得探测', () {
      expect(SearchIntentService.looksLikePersonName('周星驰'), isTrue);
      expect(SearchIntentService.looksLikePersonName('吴京'), isTrue);
      expect(SearchIntentService.looksLikePersonName('摩根弗里曼'), isTrue);
    });

    test('带年份 / 空格 / 标点 / 太长 → 不是人名（按片名处理）', () {
      expect(SearchIntentService.looksLikePersonName('流浪地球 2019'), isFalse);
      expect(SearchIntentService.looksLikePersonName('周星驰 喜剧'), isFalse);
      expect(SearchIntentService.looksLikePersonName('哈利波特与魔法石'), isFalse);
      expect(SearchIntentService.looksLikePersonName('周'), isFalse);
      expect(SearchIntentService.looksLikePersonName('Inception'), isFalse);
    });

    test('6 字以内的中文片名也会被探测一次 —— 代价是几百毫秒，'
        '换来「周星驰」这类查询能落地', () {
      // 这类词会问一次豆瓣，但首条是 movie 而不是 celebrity，
      // parsePersonHit 返回 null，随后按片名搜索，行为不变。
      expect(SearchIntentService.looksLikePersonName('肖申克的救赎'), isTrue);
      expect(SearchIntentService.looksLikePersonName('流浪地球'), isTrue);
    });
  });

  group('parsePersonHit：豆瓣响应里的人名识别', () {
    /// 真实响应（2026-10-28 实测 `q=周星驰`），删掉了 poster 的转义。
    final realResponse = <dynamic>[
      {
        'title': '周星驰',
        'sub_title': 'Stephen Chow',
        'type': 'celebrity',
        'id': '1048026',
      },
      {'title': '功夫女足', 'year': '2026', 'type': 'movie', 'id': '36452545'},
      {'title': '少林足球', 'year': '2001', 'type': 'movie', 'id': '1297747'},
      {'title': '喜剧之王', 'year': '1999', 'type': 'movie', 'id': '1302425'},
      {'title': '功夫', 'year': '2004', 'type': 'movie', 'id': '1291543'},
    ];

    test('人物条目 + 代表作都能拿到（一次请求两件事）', () {
      final hit = SearchIntentService.parsePersonHit(realResponse, '周星驰');
      expect(hit, isNotNull);
      expect(hit!.name, '周星驰');
      expect(hit.englishName, 'Stephen Chow');
      expect(hit.doubanId, '1048026');
      expect(hit.hasWorks, isTrue);
      expect(
        hit.works.map((w) => w.title).toList(),
        containsAll(<String>['少林足球', '喜剧之王', '功夫']),
      );
    });

    test('片名首条、没有 celebrity → 不是人名（「功夫」不能被当成人名）', () {
      final movieResponse = <dynamic>[
        {'title': '功夫', 'year': '2004', 'type': 'movie', 'id': '1291543'},
        {'title': '功夫熊猫', 'year': '2008', 'type': 'movie', 'id': '1'},
      ];
      expect(SearchIntentService.parsePersonHit(movieResponse, '功夫'), isNull);
    });

    test('celebrity 排在第三位以后 → 不抢走这次搜索', () {
      final lateCelebrity = <dynamic>[
        {'title': '功夫', 'type': 'movie', 'id': '1291543'},
        {'title': '功夫熊猫', 'type': 'movie', 'id': '1'},
        {'title': '功夫', 'type': 'celebrity', 'id': '999'},
      ];
      expect(
        SearchIntentService.parsePersonHit(lateCelebrity, '功夫'),
        isNull,
        reason: '用户搜的是片名，同名人物排在后面不该抢语义',
      );
    });

    test('标题不完全相等 → 不算（「周星驰电影」不是人名）', () {
      final hit = SearchIntentService.parsePersonHit(realResponse, '周星驰电影');
      expect(hit, isNull);
    });

    test('没有作品列表时人名仍成立，但 hasWorks=false（上层回退片名搜索）', () {
      final onlyPerson = <dynamic>[
        {'title': '周星驰', 'type': 'celebrity', 'id': '1048026'},
      ];
      final hit = SearchIntentService.parsePersonHit(onlyPerson, '周星驰');
      expect(hit, isNotNull);
      expect(hit!.hasWorks, isFalse);
    });

    test('代表作去重、最多 8 部', () {
      final many = <dynamic>[
        {'title': '周星驰', 'type': 'celebrity', 'id': '1'},
        for (var i = 0; i < 12; i++)
          {'title': '作品$i', 'type': 'movie', 'id': '$i'},
        {'title': '作品0', 'type': 'movie', 'id': 'dup'},
      ];
      final hit = SearchIntentService.parsePersonHit(many, '周星驰');
      expect(hit!.works.length, 8);
      expect(hit.works.where((w) => w.title == '作品0').length, 1);
    });
  });

  group('resolve：本地词表优先，不为人名探测付额外延迟', () {
    test('一级分类词 → category，不发网络请求', () async {
      final intent = await SearchIntentService.instance.resolve('动漫');
      expect(intent.kind, SearchIntentKind.category);
      expect(intent.term, '动漫');
      expect(intent.person, isNull);
    });

    test('细分类型词 → genre（「动作片」也能归一化命中）', () async {
      final g1 = await SearchIntentService.instance.resolve('科幻');
      expect(g1.kind, SearchIntentKind.genre);
      expect(g1.term, '科幻');

      final g2 = await SearchIntentService.instance.resolve('动作片');
      expect(g2.kind, SearchIntentKind.genre);
      expect(g2.term, '动作');
    });

    test('probePerson=false → 片名语义，不发豆瓣请求（详情页磁力搜索用）',
        () async {
      final intent = await SearchIntentService.instance.resolve(
        '周星驰',
        probePerson: false,
      );
      expect(intent.kind, SearchIntentKind.title);
      expect(intent.term, '周星驰');
    });
  });

  group('stripDecorations（书名号等装饰标点）', () {
    test('《权力的游戏》→ 权力的游戏（源站 wd= 逐字匹配，带书名号 total=0）', () {
      expect(SearchIntentService.stripDecorations('《权力的游戏》'), '权力的游戏');
    });

    test('中英文引号 / 括号 / 方括号都清掉', () {
      expect(SearchIntentService.stripDecorations('「周星驰」'), '周星驰');
      expect(SearchIntentService.stripDecorations('"Inception"'), 'Inception');
      expect(SearchIntentService.stripDecorations('【流浪地球】'), '流浪地球');
      expect(SearchIntentService.stripDecorations('(沙丘)'), '沙丘');
    });

    test('片名内部的冒号 / 间隔号不动（很多源里它们是片名的一部分）', () {
      expect(
        SearchIntentService.stripDecorations('蜘蛛侠：英雄归来'),
        '蜘蛛侠：英雄归来',
      );
      expect(SearchIntentService.stripDecorations('花·木兰'), '花·木兰');
    });

    test('只有装饰标点 / 空串 → 回退原词，不会把查询清成空', () {
      expect(SearchIntentService.stripDecorations('  《》  '), '《》');
      expect(SearchIntentService.stripDecorations(''), '');
    });

    test('清理后的人名仍能被词表/人名识别命中', () {
      // 用户经常带书名号搜人名，清理后才能走到人名通道。
      expect(
        SearchIntentService.looksLikePersonName(
          SearchIntentService.stripDecorations('《周星驰》'),
        ),
        isTrue,
      );
    });
  });
}
