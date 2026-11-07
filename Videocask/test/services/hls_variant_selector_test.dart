import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/hls_variant_selector.dart';

/// master playlist 采样（4 档）。
const String _master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720
hd/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
fhd/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=15000000,RESOLUTION=3840x2160
uhd/index.m3u8
''';

void main() {
  group('HlsVariantSelector', () {
    test('自动 → 仍取最高码率（保持原行为）', () {
      expect(
        HlsVariantSelector.pick(
          content: _master,
          baseUrl: 'https://cdn.example.com/a/master.m3u8',
          quality: '自动',
        ),
        'https://cdn.example.com/a/uhd/index.m3u8',
      );
    });

    test('1080P → 选 1080 档，不选 4K', () {
      expect(
        HlsVariantSelector.pick(
          content: _master,
          baseUrl: 'https://cdn.example.com/a/master.m3u8',
          quality: '1080P',
        ),
        'https://cdn.example.com/a/fhd/index.m3u8',
      );
    });

    test('高清（720）→ 选 720 档', () {
      expect(
        HlsVariantSelector.pick(
          content: _master,
          baseUrl: 'https://cdn.example.com/a/master.m3u8',
          quality: '高清',
        ),
        'https://cdn.example.com/a/hd/index.m3u8',
      );
    });

    test('标清 → 选最低档', () {
      expect(
        HlsVariantSelector.pick(
          content: _master,
          baseUrl: 'https://cdn.example.com/a/master.m3u8',
          quality: '标清',
        ),
        'https://cdn.example.com/a/low/index.m3u8',
      );
    });

    test('目标高于所有档位 → 取最高的一档而不是 null', () {
      expect(
        HlsVariantSelector.pick(
          content: '#EXTM3U\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080\n'
              'only/index.m3u8\n',
          baseUrl: 'https://cdn.example.com/a/master.m3u8',
          quality: '4K',
        ),
        'https://cdn.example.com/a/only/index.m3u8',
      );
    });

    test('全部高于目标（只有 4K）→ 退而取最低', () {
      final content = '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=15000000,RESOLUTION=3840x2160\n'
          'uhd/index.m3u8\n';
      expect(
        HlsVariantSelector.pick(
          content: content,
          baseUrl: 'https://cdn.example.com/a/master.m3u8',
          quality: '标清',
        ),
        'https://cdn.example.com/a/uhd/index.m3u8',
      );
    });

    test('缺 RESOLUTION 时按带宽估算档位', () {
      const content = '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=900000\n'
          'a.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=4800000\n'
          'b.m3u8\n';
      expect(
        HlsVariantSelector.pick(
          content: content,
          baseUrl: 'https://cdn.example.com/master.m3u8',
          quality: '高清',
        ),
        'https://cdn.example.com/a.m3u8',
      );
    });

    test('绝对地址保持原样，相对地址按 base 解析', () {
      const content = '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080\n'
          'https://other.example.com/x.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720\n'
          '../hd/x.m3u8\n';
      expect(
        HlsVariantSelector.pick(
          content: content,
          baseUrl: 'https://cdn.example.com/a/b/master.m3u8',
          quality: '1080P',
        ),
        'https://other.example.com/x.m3u8',
      );
      expect(
        HlsVariantSelector.pick(
          content: content,
          baseUrl: 'https://cdn.example.com/a/b/master.m3u8',
          quality: '高清',
        ),
        'https://cdn.example.com/a/hd/x.m3u8',
      );
    });

    test('没有 STREAM-INF 的 media playlist → null', () {
      expect(
        HlsVariantSelector.pick(
          content: '#EXTM3U\n#EXTINF:6,\nseg1.ts\n',
          baseUrl: 'https://cdn.example.com/a.m3u8',
          quality: '1080P',
        ),
        isNull,
      );
    });

    test('清晰度映射', () {
      expect(HlsVariantSelector.targetHeightOf('标清'), 480);
      expect(HlsVariantSelector.targetHeightOf('高清'), 720);
      expect(HlsVariantSelector.targetHeightOf('1080P'), 1080);
      expect(HlsVariantSelector.targetHeightOf('4K'), 2160);
      expect(HlsVariantSelector.targetHeightOf('自动'), isNull);
      expect(HlsVariantSelector.targetHeightOf('未知档'), isNull);
    });
  });
}
