import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/m3u8_playlist_resolver.dart';

/// `M3u8PlaylistResolver.parseAes128Key` 的单元测试。
///
/// 覆盖 2026-10-18 修复的「#EXT-X-KEY 属性顺序不敏感」问题：规范允许
/// `URI=` 出现在 `METHOD=` 前后，旧的固定顺序正则会漏判加密流 → 重建播放
/// 列表时丢掉 KEY 行 → 播放器拿到未解密的乱码分片（安卓端花屏/闪退根因）。
void main() {
  const base = 'https://c.com/play/index.m3u8';

  group('标准写法', () {
    test('METHOD=AES-128,URI="..."（文档常见顺序）', () {
      final key = M3u8PlaylistResolver.parseAes128Key(
        '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="https://k.com/key.bin"\n',
        base,
      );
      expect(key, isNotNull);
      expect(key!.uri, 'https://k.com/key.bin');
      expect(key.ivHex, isNull);
    });

    test('URI 出现在 METHOD 之前也能识别（修复前漏判成明文）', () {
      final key = M3u8PlaylistResolver.parseAes128Key(
        '#EXTM3U\n#EXT-X-KEY:URI="https://k.com/key.bin",METHOD=AES-128\n',
        base,
      );
      expect(key, isNotNull);
      expect(key!.uri, 'https://k.com/key.bin');
    });

    test('IV=0x 前缀被剥离，只留十六进制位', () {
      final key = M3u8PlaylistResolver.parseAes128Key(
        '#EXTM3U\n'
        '#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x1F2E3D4C5B6A7988\n',
        base,
      );
      expect(key, isNotNull);
      expect(key!.uri, 'https://c.com/play/key.bin'); // 相对地址基于列表解析
      expect(key.ivHex, '1F2E3D4C5B6A7988');
    });

    test('IV 大写 0X 前缀同样剥离', () {
      final key = M3u8PlaylistResolver.parseAes128Key(
        '#EXTM3U\n'
        '#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0XABCD\n',
        base,
      );
      expect(key!.ivHex, 'ABCD');
    });

    test('无 0x 前缀的 IV 原样保留', () {
      final key = M3u8PlaylistResolver.parseAes128Key(
        '#EXTM3U\n'
        '#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0123456789ABCDEF\n',
        base,
      );
      expect(key!.ivHex, '0123456789ABCDEF');
    });

    test('裸值（无引号）URI 可解析', () {
      final key = M3u8PlaylistResolver.parseAes128Key(
        '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=https://k.com/key.bin\n',
        base,
      );
      expect(key!.uri, 'https://k.com/key.bin');
    });
  });

  group('非加密 / 异常输入返回 null', () {
    test('METHOD=NONE 视为未加密', () {
      final key = M3u8PlaylistResolver.parseAes128Key(
        '#EXTM3U\n#EXT-X-KEY:METHOD=NONE,URI="https://k.com/key.bin"\n',
        base,
      );
      expect(key, isNull);
    });

    test('没有 EXT-X-KEY 行返回 null', () {
      final key = M3u8PlaylistResolver.parseAes128Key(
        '#EXTM3U\n#EXTINF:4.0,\nseg0.ts\n',
        base,
      );
      expect(key, isNull);
    });

    test('KEY 行缺 METHOD 被跳过', () {
      final key = M3u8PlaylistResolver.parseAes128Key(
        '#EXTM3U\n#EXT-X-KEY:URI="https://k.com/key.bin"\n',
        base,
      );
      expect(key, isNull);
    });

    test('KEY 行缺 URI 被跳过', () {
      final key = M3u8PlaylistResolver.parseAes128Key(
        '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128\n',
        base,
      );
      expect(key, isNull);
    });

    test('空 IV 视为未提供（ivHex 为 null）', () {
      final key = M3u8PlaylistResolver.parseAes128Key(
        '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=\n',
        base,
      );
      expect(key!.ivHex, isNull);
    });

    test('空内容返回 null', () {
      expect(M3u8PlaylistResolver.parseAes128Key('', base), isNull);
    });
  });

  group('多 KEY 行', () {
    test('取第一个 AES-128 KEY，跳过 METHOD=NONE', () {
      final key = M3u8PlaylistResolver.parseAes128Key(
        '#EXTM3U\n'
        '#EXT-X-KEY:METHOD=NONE\n'
        '#EXT-X-KEY:METHOD=AES-128,URI="https://k.com/k1.bin"\n'
        '#EXT-X-KEY:METHOD=AES-128,URI="https://k.com/k2.bin"\n',
        base,
      );
      expect(key!.uri, 'https://k.com/k1.bin');
    });
  });
}
