import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/douban_lookup_service.dart';

void main() {
  group('DoubanLookupService.parseSubject', () {
    test('解析中文剧情简介（优先完整版）+ 类型/导演/主演/地区/年份', () {
      const html = '''
<html><body>
<span property="v:summary" class="">
  可见的截断简介……<br/>
</span>
<span class="all hidden">这是完整的剧情简介，描述了主角在命运漩涡中的挣扎与救赎。</span>
<span property="v:genre">剧情</span>
<span property="v:genre">犯罪</span>
<a rel="v:directedBy" href="/celebrity/100/">弗兰克·德拉邦特</a>
<a rel="v:starring" href="/celebrity/200/">蒂姆·罗宾斯</a>
<a rel="v:starring" href="/celebrity/300/">摩根·弗里曼</a>
<span class="pl">制片国家/地区:</span> 美国 / 英国
<span property="v:initialReleaseDate" content="1994-09-10">1994</span>
</body></html>''';

      final d = DoubanLookupService.parseSubject(html);
      expect(d, isNotNull);
      expect(
        d!.summary,
        '这是完整的剧情简介，描述了主角在命运漩涡中的挣扎与救赎。',
      );
      expect(d.genres, ['剧情', '犯罪']);
      expect(d.director, '弗兰克·德拉邦特');
      expect(d.actors, ['蒂姆·罗宾斯', '摩根·弗里曼']);
      expect(d.region, '美国 / 英国');
      expect(d.year, '1994');
    });

    test('无完整版时回退到可见摘要段', () {
      const html = '''
<span property="v:summary" class="">只有可见简介，没有隐藏全文。</span>
<span property="v:genre">喜剧</span>
''';
      final d = DoubanLookupService.parseSubject(html);
      expect(d, isNotNull);
      expect(d!.summary, '只有可见简介，没有隐藏全文。');
      expect(d.genres, ['喜剧']);
    });

    test('反爬页 / 无结构化数据返回 null', () {
      const html = '<html><body>检测到有异常请求，请输入验证码</body></html>';
      expect(DoubanLookupService.parseSubject(html), isNull);
      expect(DoubanLookupService.parseSubject(''), isNull);
    });
  });
}
