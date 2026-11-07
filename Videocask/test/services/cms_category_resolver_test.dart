import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/cms_category_resolver.dart';

/// 分类表 fixture：**2026-09-29 真实抓包**，不是手工编造的形态。
///
/// 关键事实（决定了「影视数量太少」这一 bug）：
/// - ffzy / lzi：`t=电影片(1)` 返回 0~1 条，内容全在子类（动作片 229 页…）；
/// - hongniu / bdzy：`ac=list` 不返回 `type_pid`，只能靠命名归类；
/// - hongniu：`t=短剧(30)` 为 0 条，短剧内容散落在「古装仙侠 / 现代都市 …」题材类下。
Map<int, CmsCategoryNode> _ffzyTree() {
  const rows = <List<Object>>[
    [1, '电影片', 0],
    [2, '连续剧', 0],
    [3, '综艺片', 0],
    [4, '动漫片', 0],
    [6, '动作片', 1],
    [7, '喜剧片', 1],
    [8, '爱情片', 1],
    [9, '科幻片', 1],
    [10, '恐怖片', 1],
    [11, '剧情片', 1],
    [12, '战争片', 1],
    [13, '国产剧', 2],
    [14, '香港剧', 2],
    [15, '韩国剧', 2],
    [16, '欧美剧', 2],
    [20, '记录片', 1],
    [21, '台湾剧', 2],
    [22, '日本剧', 2],
    [23, '海外剧', 2],
    [24, '泰国剧', 2],
    [25, '大陆综艺', 3],
    [26, '港台综艺', 3],
    [27, '日韩综艺', 3],
    [28, '欧美综艺', 3],
    [29, '国产动漫', 4],
    [30, '日韩动漫', 4],
    [31, '欧美动漫', 4],
    [32, '港台动漫', 4],
    [33, '海外动漫', 4],
    [34, '伦理片', 1],
    [36, '短剧', 2],
  ];
  return {
    for (final r in rows)
      r[0] as int: CmsCategoryNode(
        id: r[0] as int,
        name: r[1] as String,
        parentId: r[2] as int,
      ),
  };
}

Map<int, CmsCategoryNode> _hongniuTree() {
  // 该源不返回 type_pid（全为 0）。
  const rows = <List<Object>>[
    [1, '电影'],
    [2, '连续剧'],
    [3, '综艺'],
    [4, '动漫'],
    [5, '动作片'],
    [6, '喜剧片'],
    [7, '爱情片'],
    [8, '科幻片'],
    [9, '恐怖片'],
    [10, '剧情片'],
    [11, '战争片'],
    [12, '国产剧'],
    [19, '纪录片'],
    [20, '动漫电影'],
    [21, '伦理片'],
    [30, '短剧'],
    [31, '预告片'],
    [36, '中国动漫'],
    [39, '大陆综艺'],
    [43, '古装仙侠'],
    [44, '现代都市'],
    [45, '穿越年代'],
    [46, '言情总裁'],
    [47, '重生民国'],
  ];
  return {
    for (final r in rows)
      r[0] as int: CmsCategoryNode(
        id: r[0] as int,
        name: r[1] as String,
      ),
  };
}

void main() {
  group('resolveTypeIds 展开父类/子类', () {
    test('ffzy：电影展开为全部电影子类，且不取空壳父类 1', () {
      final ids = CmsCategoryResolver.resolveTypeIds(_ffzyTree(), '电影');
      expect(ids, [6, 7, 8, 9, 10, 11, 12, 20, 34]);
      expect(ids.contains(1), isFalse);
    });

    test('ffzy：剧集不把「短剧」混进来（短剧挂在连续剧子类下）', () {
      final ids = CmsCategoryResolver.resolveTypeIds(_ffzyTree(), '剧集');
      expect(ids, [13, 14, 15, 16, 21, 22, 23, 24]);
      expect(ids.contains(36), isFalse);
    });

    test('ffzy：短剧本身无子类时取自身', () {
      expect(CmsCategoryResolver.resolveTypeIds(_ffzyTree(), '短剧'), [36]);
    });

    test('ffzy：综艺/动漫各自展开到子类', () {
      final tree = _ffzyTree();
      expect(CmsCategoryResolver.resolveTypeIds(tree, '综艺'), [25, 26, 27, 28]);
      expect(
          CmsCategoryResolver.resolveTypeIds(tree, '动漫'), [29, 30, 31, 32, 33]);
    });

    test('hongniu：无 type_pid 时靠命名归类（电影 = 各「X片」子类）', () {
      final ids = CmsCategoryResolver.resolveTypeIds(_hongniuTree(), '电影');
      expect(ids, [5, 6, 7, 8, 9, 10, 11, 21]);
      // 纪录片 / 动漫电影 / 预告片 不属于电影
      expect(ids.contains(19), isFalse);
      expect(ids.contains(20), isFalse);
      expect(ids.contains(31), isFalse);
    });

    test('hongniu：短剧要带上散落的题材类，否则该频道为空', () {
      final ids = CmsCategoryResolver.resolveTypeIds(_hongniuTree(), '短剧');
      // 实测（2026-10-01）：hongniu `t=30` 短剧主类 **total=0**（空壳），
      // 内容全在题材子类里（43 古装仙侠 5797 条 / 44 现代都市 14715 条 / 45 穿越年代 1984 条）。
      // 故期望**不含** 30 —— 与 ffzy「不取空壳父类 1」是同一条约定。
      expect(ids, [43, 44, 45, 46, 47]);
      expect(ids.contains(30), isFalse);
    });

    test('hongniu：剧集不吞掉短剧题材类', () {
      final ids = CmsCategoryResolver.resolveTypeIds(_hongniuTree(), '剧集');
      expect(ids, [12]);
      expect(ids.any((id) => [43, 44, 45, 46, 47, 30].contains(id)), isFalse);
    });

    test('站点没有该分类时返回空（不得退化成全站请求）', () {
      final withoutShort = _ffzyTree()
        ..removeWhere((_, n) => n.name.contains('短剧'));
      expect(CmsCategoryResolver.resolveTypeIds(withoutShort, '短剧'), isEmpty);
      expect(CmsCategoryResolver.resolveTypeIds(const {}, '电影'), isEmpty);
    });

    test('子类过多时截断到上限，避免请求爆炸', () {
      final many = <int, CmsCategoryNode>{
        1: const CmsCategoryNode(id: 1, name: '电影片'),
        for (var i = 0; i < 40; i++)
          i + 2: CmsCategoryNode(id: i + 2, name: '类型${i}片', parentId: 1),
      };
      final ids = CmsCategoryResolver.resolveTypeIds(many, '电影');
      expect(ids.length, CmsCategoryResolver.maxTypeIdsPerCategory);
    });
  });

  group('matchGenreTypeId 类型筛选落到站点同族子类', () {
    test('「动作」命中「动作片」', () {
      final tree = _ffzyTree();
      final all = CmsCategoryResolver.resolveTypeIds(tree, '电影');
      expect(CmsCategoryResolver.matchGenreTypeId(tree, all, '动作'), 6);
      expect(CmsCategoryResolver.matchGenreTypeId(tree, all, '科幻'), 9);
    });

    test('站点没有的类型返回 null（交给本地过滤）', () {
      final tree = _ffzyTree();
      final all = CmsCategoryResolver.resolveTypeIds(tree, '电影');
      expect(CmsCategoryResolver.matchGenreTypeId(tree, all, '家庭'), isNull);
      expect(CmsCategoryResolver.matchGenreTypeId(tree, all, '全部'), isNull);
    });

    test('不会跨分类命中（剧集的动作片不在候选里）', () {
      final tree = _ffzyTree();
      final drama = CmsCategoryResolver.resolveTypeIds(tree, '剧集');
      expect(CmsCategoryResolver.matchGenreTypeId(tree, drama, '动作'), isNull);
    });
  });

  group('genreMatches 本地过滤', () {
    test('「动作」命中 vod_class / type_name 里的动作片', () {
      expect(CmsCategoryResolver.genreMatches('动作', ['动作片', '剧情']), isTrue);
      expect(CmsCategoryResolver.genreMatches('动作', ['动作', '犯罪']), isTrue);
      expect(CmsCategoryResolver.genreMatches('动作', ['喜剧片']), isFalse);
    });

    test('「全部」放行一切', () {
      expect(CmsCategoryResolver.genreMatches('全部', const []), isTrue);
    });

test('normalizeGenreName 去掉片/剧后缀', () {
 expect(CmsCategoryResolver.normalizeGenreName('动作片'), '动作');
      expect(CmsCategoryResolver.normalizeGenreName('国产剧'), '国产');
      expect(CmsCategoryResolver.normalizeGenreName('家庭'), '家庭');
    });

    test('类型标签为空时放行，而非把整个类目清空', () {
      // 复现用户症状：动漫 + 「热血」只剩两条。
      // `ac=list` 不返回 `vod_class` → `Movie.genreTags` 为空 → 无法判定 → 放行。
      expect(CmsCategoryResolver.genreMatches('热血', const []), isTrue);
    });

    test('真实类型存在时仍严格匹配（不被放行规则稀释）', () {
      expect(CmsCategoryResolver.genreMatches('热血', ['热血', '战斗']), isTrue);
      expect(CmsCategoryResolver.genreMatches('热血', ['热血青春']), isTrue);
      expect(CmsCategoryResolver.genreMatches('热血', ['悬疑', '犯罪']), isFalse);
    });
  });

  group('regionMatches 地区过滤', () {
    const regions = ['全部', '中国大陆', '中国香港', '美国', '其他'];

    test('同义写法都能命中', () {
      expect(
        CmsCategoryResolver.regionMatches('中国大陆', '大陆', knownRegions: regions),
        isTrue,
      );
      expect(
        CmsCategoryResolver.regionMatches('中国大陆', '中国', knownRegions: regions),
        isTrue,
      );
      expect(
        CmsCategoryResolver.regionMatches('中国香港', '香港', knownRegions: regions),
        isTrue,
      );
    });

    test('「其他」= 不属于任何已知地区', () {
      expect(
        CmsCategoryResolver.regionMatches('其他', '西班牙', knownRegions: regions),
        isTrue,
      );
      expect(
        CmsCategoryResolver.regionMatches('其他', '中国大陆', knownRegions: regions),
        isFalse,
      );
    });

    test('地区为空时放行而非排除（列表接口不返回 vod_area）', () {
      // 2026-10-21 实测：lzi / ffzy 的 `ac=list` 只有 8 个字段，无 `vod_area`。
      // 若把「查不到地区」当成「不匹配」，选任一地区都会把列表清空到只剩零星几条。
      expect(
        CmsCategoryResolver.regionMatches('美国', '', knownRegions: regions),
        isTrue,
      );
      expect(
        CmsCategoryResolver.regionMatches('全部', '', knownRegions: regions),
        isTrue,
      );
      // 「其他」在地区未知时同样不该命中，也不该排除。
      expect(
        CmsCategoryResolver.regionMatches('其他', '', knownRegions: regions),
        isTrue,
      );
    });

    test('地区已知时仍严格匹配', () {
      expect(
        CmsCategoryResolver.regionMatches('美国', '美国', knownRegions: regions),
        isTrue,
      );
      expect(
        CmsCategoryResolver.regionMatches('美国', '中国大陆', knownRegions: regions),
        isFalse,
      );
    });
  });

  group('typeNameBelongsTo 类目归属（2026-10-21 第七批）', () {
    // 轮播候选过滤用：采集站子类里混进的异类（真人剧、动画电影）不能当 banner。
    test('同族分类名命中', () {
      expect(CmsCategoryResolver.typeNameBelongsTo('动漫', '国产动漫'), isTrue);
      expect(CmsCategoryResolver.typeNameBelongsTo('动漫', '海外动漫'), isTrue);
      expect(CmsCategoryResolver.typeNameBelongsTo('动漫', '动漫片'), isTrue);
      expect(CmsCategoryResolver.typeNameBelongsTo('动漫', '动画片'), isTrue);
      expect(CmsCategoryResolver.typeNameBelongsTo('剧集', '海外剧'), isTrue);
      expect(CmsCategoryResolver.typeNameBelongsTo('剧集', '国产剧'), isTrue);
      expect(CmsCategoryResolver.typeNameBelongsTo('剧集', '连续剧'), isTrue);
      expect(CmsCategoryResolver.typeNameBelongsTo('电影', '动作片'), isTrue);
      expect(CmsCategoryResolver.typeNameBelongsTo('电影', '电影片'), isTrue);
      expect(CmsCategoryResolver.typeNameBelongsTo('综艺', '日韩综艺'), isTrue);
      expect(CmsCategoryResolver.typeNameBelongsTo('纪录片', '记录片'), isTrue);
    });

    test('异类分类名不命中', () {
      expect(CmsCategoryResolver.typeNameBelongsTo('动漫', '连续剧'), isFalse);
      expect(CmsCategoryResolver.typeNameBelongsTo('动漫', '海外剧'), isFalse);
      expect(CmsCategoryResolver.typeNameBelongsTo('剧集', '动漫片'), isFalse);
      expect(CmsCategoryResolver.typeNameBelongsTo('剧集', '动画片'), isFalse);
      expect(CmsCategoryResolver.typeNameBelongsTo('电影', '动画片'), isFalse);
      expect(CmsCategoryResolver.typeNameBelongsTo('电影', '记录片'), isFalse);
      expect(CmsCategoryResolver.typeNameBelongsTo('电影', '电影解说'), isFalse);
      expect(CmsCategoryResolver.typeNameBelongsTo('综艺', '动漫'), isFalse);
    });

    test('短剧不算剧集族（与 resolveTypeIds 的排除规则一致）', () {
      expect(CmsCategoryResolver.typeNameBelongsTo('剧集', '短剧'), isFalse);
      expect(CmsCategoryResolver.typeNameBelongsTo('剧集', '爽文短剧'), isFalse);
      expect(CmsCategoryResolver.typeNameBelongsTo('短剧', '爽文短剧'), isTrue);
    });

    test('type_name 为空时放行（未知 ≠ 不属于）', () {
      expect(CmsCategoryResolver.typeNameBelongsTo('动漫', ''), isTrue);
      expect(CmsCategoryResolver.typeNameBelongsTo('剧集', '   '), isTrue);
    });
  });
}
