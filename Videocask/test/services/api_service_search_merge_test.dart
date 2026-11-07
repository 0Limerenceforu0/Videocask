import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/services/api_service.dart';

/// 多源搜索「同名合并」回归测试。
///
/// 背景（2026-09-15 用户反馈）：搜索「万妖图录传」只出 3 条，而采集站
/// 实际返回第一~第十一季共 20+ 条。原因是合并判定会先抹掉「第 X 季」
/// 再比较名称，导致不同季被判为同一部影片而合并成一行。
///
/// 数据取自真实采集站响应（非凡资源 / 暴风资源）。
void main() {
  Movie m(String name, {String year = '2026', List<String> genres = const []}) {
    return Movie(id: name, name: name, year: year, genres: genres);
  }

  group('seasonKeyOfName 季数解析', () {
    test('中文数字', () {
      expect(ApiService.seasonKeyOfName('万妖图录传第七季'), 'S7');
      expect(ApiService.seasonKeyOfName('万妖图录传第十季'), 'S10');
      expect(ApiService.seasonKeyOfName('万妖图录传第十一季'), 'S11');
      expect(ApiService.seasonKeyOfName('某剧第二部'), 'S2');
    });

    test('阿拉伯数字与英文写法', () {
      expect(ApiService.seasonKeyOfName('万妖图录传 第10季'), 'S10');
      expect(ApiService.seasonKeyOfName('Some Show Season 3'), 'S3');
      expect(ApiService.seasonKeyOfName('Some Show S03'), 'S3');
    });

    test('无季数返回空串', () {
      expect(ApiService.seasonKeyOfName('万妖图录传'), '');
      expect(ApiService.seasonKeyOfName('万妖图录传！'), '');
    });
  });

  group('isSameMovieForMerge 合并判定', () {
    test('同一部剧的不同季不能合并', () {
      final s7 = m('万妖图录传第七季', genres: const ['国产动漫']);
      final s9 = m('万妖图录传第九季', genres: const ['国产动漫']);
      final s10 = m('万妖图录传第十季', genres: const ['国产动漫']);
      expect(ApiService.isSameMovieForMerge(s7, s9), isFalse);
      expect(ApiService.isSameMovieForMerge(s9, s10), isFalse);
    });

    test('同一季不同写法（第7季 / 第七季）视为同一部', () {
      expect(
        ApiService.isSameMovieForMerge(
          m('万妖图录传第七季', genres: const ['国产动漫']),
          m('万妖图录传 第7季', genres: const ['国产动漫']),
        ),
        isTrue,
      );
    });

    test('同名同季但类型无交集（不同剧集版本）不合并', () {
      expect(
        ApiService.isSameMovieForMerge(
          m('万妖图录传第七季', genres: const ['国产动漫']),
          m('万妖图录传第七季', genres: const ['AI漫剧']),
        ),
        isFalse,
      );
    });

    test('年份不同不合并', () {
      expect(
        ApiService.isSameMovieForMerge(
          m('万妖图录传', year: '2025', genres: const ['国产动漫']),
          m('万妖图录传', year: '2026', genres: const ['国产动漫']),
        ),
        isFalse,
      );
    });
  });

  test('真实多源结果不再被合并成一行（回归：曾只剩 3 条）', () {
    // 非凡资源返回（全为「国产动漫」）
    const ffzy = [
      '万妖图录传第七季',
      '万妖图录传第十季',
      '万妖图录传第九季',
      '万妖图录传第八季',
      '万妖图录传第六季',
      '万妖图录传第四季',
      '万妖图录传第三季',
      '万妖图录传第二季',
      '万妖图录传第一季',
      '万妖图录传第五季',
    ];
    // 暴风资源返回
    const bfzyAi = [
      '万妖图录传！',
      '万妖图录传第七季',
      '万妖图录传第一季',
      '万妖图录传第六季',
      '万妖图录传第二季',
      '万妖图录传第三季',
      '万妖图录传第四季',
      '万妖图录传第五季',
      '万妖图录传第八季',
      '万妖图录传第九季',
    ];

    final all = <Movie>[
      for (final n in ffzy) m(n, genres: const ['国产动漫']),
      for (final n in bfzyAi) m(n, genres: const ['AI漫剧']),
      m('万妖图录传 第十季', genres: const ['国产动漫']),
      m('万妖图录传 第十一季', genres: const ['国产动漫']),
    ];

    // 模拟 _mergeMultiSourceSearchResults 的合并过程
    final merged = <Movie>[];
    for (final movie in all) {
      final idx = merged.indexWhere(
        (e) => ApiService.isSameMovieForMerge(e, movie),
      );
      if (idx < 0) merged.add(movie);
    }

    final names = merged.map((e) => e.name).toList();
    // ignore: avoid_print
    print('合并后 ${merged.length} 条: $names');

    expect(merged.length, greaterThan(3), reason: '修复前只剩 3 条');
    expect(
      names.any((n) => n.contains('第一季')),
      isTrue,
      reason: '第一季应独立成条',
    );
    expect(
      names.any((n) => n.contains('第十一季')),
      isTrue,
      reason: '第十一季应独立成条',
    );
    // 「万妖图录传 第十季」与「万妖图录传第十季」是同季同类型 → 合并
    expect(
      merged.where((e) => e.name.contains('第十季')).length,
      1,
      reason: '同季同类型应合并成一条',
    );
  });

  /// 2026-10-28 用户反馈：搜「流浪地球」时「影视资源」有 154 条，
  /// 一大半跟搜索词不相干（采集站模糊搜索带出来的续集/短片/无关片）。
  /// 这里锁住「相关性过滤」的契约：该留的留、该丢的丢、跨语种不能误杀。
  group('isSearchResultRelevant 相关性判定', () {
    test('完全同名 / 关键词是片名前缀 → 相关', () {
      expect(ApiService.isSearchResultRelevant('流浪地球', '流浪地球'), isTrue);
      expect(
        ApiService.isSearchResultRelevant('流浪地球', '流浪地球2：飞跃2020特别版'),
        isTrue,
        reason: '续集片名包含原片名，属于相关结果',
      );
    });

    test('片名带标点/空格/副标题 → 仍判相关', () {
      expect(
        ApiService.isSearchResultRelevant('流浪地球', '《流浪地球》'),
        isTrue,
      );
      expect(
        ApiService.isSearchResultRelevant('盗梦空间', '盗梦空间 Inception'),
        isTrue,
      );
    });

    test('关键词包含片名（多打了年份/副标题）→ 相关', () {
      expect(
        ApiService.isSearchResultRelevant('流浪地球 2019', '流浪地球'),
        isTrue,
      );
    });

    test('毫不相干的片名 → 丢弃', () {
      expect(ApiService.isSearchResultRelevant('流浪地球', '熊出没之重返地球'), isFalse);
      expect(ApiService.isSearchResultRelevant('流浪地球', '满江红'), isFalse);
      expect(ApiService.isSearchResultRelevant('盗梦空间', '盗墓笔记'), isFalse);
    });

    test('跨语种（中文关键词 vs 英文片名）→ 放行，避免整源清空', () {
      expect(
        ApiService.isSearchResultRelevant('流浪地球', 'The Wandering Earth'),
        isTrue,
      );
      expect(
        ApiService.isSearchResultRelevant('Inception', '盗梦空间'),
        isTrue,
      );
    });

    test('空关键词 → 放行；空片名 → 丢弃', () {
      expect(ApiService.isSearchResultRelevant('', '随便什么'), isTrue);
      expect(ApiService.isSearchResultRelevant('流浪地球', ''), isFalse);
    });
  });

  /// 2026-10-28 第二次反馈：「怎么跟二极管一样」。
  ///
  /// 严格过滤把「搜《死侍》出《战狼》」修好了，但如果一个源严格命中为 0，
  /// 整个源就被清空 → 用户从「看到错的」变成「什么都看不到」。
  /// 这里锁住兜底契约：严格为 0 时放宽到「命中任意一个词」，
  /// 一个词都不沾的仍然丢弃。
  group('isSearchResultLooselyRelevant 严格为空时的放宽判定', () {
    test('严格判不相关但命中一个词 → 放宽后保留', () {
      // 归一化后关键词不包含片名，只能靠分词命中；
      // 3 个词里只命中「药神」1 个 → 严格判定（要求过半）不通过。
      const keyword = '药神 徐峥 主演';
      expect(
        ApiService.isSearchResultRelevant(keyword, '我不是药神'),
        isFalse,
        reason: '3 个词只命中 1 个，严格判定要求过半',
      );
      expect(
        ApiService.isSearchResultLooselyRelevant(keyword, '我不是药神'),
        isTrue,
        reason: '兜底档：至少沾到一个词就该留下',
      );
    });

    test('一个词都不沾 → 放宽也丢弃（宁可空，也不要无关条目）', () {
      expect(
        ApiService.isSearchResultLooselyRelevant('我不是药神', '熊出没之重返地球'),
        isFalse,
      );
      expect(
        ApiService.isSearchResultLooselyRelevant('科幻 动作', '满江红'),
        isFalse,
      );
    });

    test('跨语种仍放行（无法判定，不误杀）', () {
      expect(
        ApiService.isSearchResultLooselyRelevant('流浪地球', 'The Wandering Earth'),
        isTrue,
      );
    });
  });

  /// 人名搜索的第二步：豆瓣给了「周星驰的代表作 = 功夫(2004)」，
  /// 源站 `wd=功夫` 却返回 83 条（功夫女足 / 功夫星猫 / 功夫小子闯佛山…）。
  /// 这里锁住「作品名 + 年份」的精确匹配契约。
  group('matchesTitleQuery 人名搜索的作品匹配', () {
    test('完全同名 → 命中', () {
      expect(
        ApiService.matchesTitleQuery(
          '少林足球',
          '2001',
          const TitleQuery('少林足球', year: '2001'),
        ),
        isTrue,
      );
      expect(
        ApiService.matchesTitleQuery(
          '喜剧之王',
          '1999',
          const TitleQuery('喜剧之王', year: '1999'),
        ),
        isTrue,
      );
    });

    test('包含作品名但年份不符（同名衍生内容）→ 丢弃', () {
      const work = TitleQuery('功夫', year: '2004');
      expect(ApiService.matchesTitleQuery('功夫女足', '2026', work), isFalse);
      expect(ApiService.matchesTitleQuery('功夫星猫', '2009', work), isFalse);
      expect(ApiService.matchesTitleQuery('功夫小子闯佛山', '2025', work), isFalse);
    });

    test('包含作品名且年份一致 → 命中（源站片名带副标题/年份）', () {
      const work = TitleQuery('喜剧之王', year: '1999');
      expect(ApiService.matchesTitleQuery('喜剧之王 1999', '1999', work), isTrue);
      expect(ApiService.matchesTitleQuery('《喜剧之王》', '1999', work), isTrue);
    });

    test('源站没给年份 → 放行（宁可多留，不可错杀）', () {
      expect(
        ApiService.matchesTitleQuery(
          '功夫',
          '',
          const TitleQuery('功夫', year: '2004'),
        ),
        isTrue,
      );
    });

    test('毫不相干的片名 → 丢弃', () {
      expect(
        ApiService.matchesTitleQuery(
          '流浪地球',
          '2019',
          const TitleQuery('功夫', year: '2004'),
        ),
        isFalse,
      );
      expect(
        ApiService.matchesTitleQuery('', '2004', const TitleQuery('功夫')),
        isFalse,
      );
    });
  });
}
