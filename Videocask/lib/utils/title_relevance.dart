import 'package:movie_app/models/movie.dart';

/// 词面相关性拆分结果：主列表 + 「其他相关结果」。
class RelevanceSplit {
  /// 片名与查询词**真的对得上**的结果，直接铺在主列表里。
  final List<Movie> primary;

  /// 来自采集站模糊检索兜底、片名对不上的结果（`007别传`、`小不列颠`）。
  /// 不再丢弃 —— 用户明确要求「折叠」，所以收进可展开的分组。
  final List<Movie> others;

  const RelevanceSplit(this.primary, this.others);

  bool get isEmpty => primary.isEmpty && others.isEmpty;
  int get total => primary.length + others.length;
}

/// 搜索结果的**词面相关性**判定（纯函数，可单测）。
///
/// 为什么需要它：采集站的 `wd=` 是「模糊/全文检索 + 相关推荐兜底」，不是精确
/// 匹配。实测搜「周星驰」会返回《007别传》《小不列颠》《情圣2016》—— 它们
/// 和查询词一个字都不沾，属于源站的推荐位。旧实现为了放行演员结果把片名
/// 相关性过滤整个关掉了，噪声就全涌进主列表。
///
/// 现在的做法是**不再关、也不再丢**：
/// * 词面对得上的 → 主列表；
/// * 对不上的 → 折叠的「其他相关结果」，用户想翻还能翻到；
/// * 人名通道的作品（豆瓣作品全集命中的）由调用方通过 [trusted] 传入，
///   它们是「片名不含人名但确实相关」的合法结果，不参与词面判定。
class TitleRelevance {
  TitleRelevance._();

  /// 归一化：去掉空白与各类标点，只留可比较的字符。
  ///
  /// 采集站的片名里 `《》`、`[]`、全角冒号、`·` 满天飞，直接比会漏。
  /// 用双引号 raw string 是为了能安全包含单引号（单引号 raw string 里
  /// 出现 `''` 会把字符串截断，之前踩过一次）。
  static final RegExp _noise = RegExp(
    r'[\s\u3000《》〈〉「」『』【】\[\]()（）·•:：;；,，.。!！?？\-_—/\\|~～+*"\u201c\u201d\u2018\u2019]',
  );

  static String normalize(String raw) => raw.toLowerCase().replaceAll(_noise, '');

  /// [title] 是否与 [query] 在词面上相关。
  ///
  /// 双向包含：`功夫` ⊂ `功夫女足`（源站返回的衍生内容，算相关），
  /// `武状元苏乞儿` ⊃ `苏乞儿`（来源是简称，也算相关）。
  /// 单字（任一侧）只认完全相等，否则搜「夫」会把所有带「夫」的片收进来。
  static bool isRelated(String title, String query) {
    final t = normalize(title);
    final q = normalize(query);
    if (q.isEmpty || t.isEmpty) return false;
    if (t == q) return true;
    if (t.length < 2 || q.length < 2) return false;
    return t.contains(q) || q.contains(t);
  }

  /// 把结果拆成「主列表」和「其他相关结果」。
  ///
  /// [trusted] 是**可信片名库**（已归一化）：人名通道拿到的豆瓣作品全集
  /// 标题，加上作品通道实际命中的结果片名。判定用「相关」而不是「相等」，
  /// 因为源站片名普遍带后缀 —— 豆瓣叫《喜剧之王》，源站叫《喜剧之王1999》，
  /// 精确相等会把正片错折进噪声组（真机实测「其他相关结果」里全是
  /// 周星驰的正片，用户只会更困惑）。
  static RelevanceSplit split(
    List<Movie> movies,
    String query, {
    Set<String> trusted = const {},
  }) {
    if (movies.isEmpty) return const RelevanceSplit([], []);
    final primary = <Movie>[];
    final others = <Movie>[];
    for (final m in movies) {
      final key = normalize(m.name);
      final hit = (trusted.isNotEmpty &&
              trusted.any((t) => _relatedNormalized(key, t))) ||
          isRelated(m.name, query);
      (hit ? primary : others).add(m);
    }
    return RelevanceSplit(primary, others);
  }

  /// 已归一化的两个词是否相关（避免在循环里反复跑正则）。
  static bool _relatedNormalized(String t, String q) {
    if (t.isEmpty || q.isEmpty) return false;
    if (t == q) return true;
    if (t.length < 2 || q.length < 2) return false;
    return t.contains(q) || q.contains(t);
  }
}
