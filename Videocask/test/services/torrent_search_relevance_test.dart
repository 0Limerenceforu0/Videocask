// 磁力搜索的两条回归契约（2026-10-24）。
//
// 背景（都是用户实测踩出来的真实故障）：
//
// 1. **磁力资源模块直接没了**
//    搜「教父」时，磁力资源模块整个消失。根因有两层：
//    a) 搜索页判定模块可见性时只看「有结果 / 还在搜」，磁力搜索一旦返回
//       空列表或超时（catchError 清空结果、关掉 loading），模块连同它内部
//       的「没有找到磁力资源 / 搜索超时」提示一起被隐藏 —— 用户完全不知道
//       是搜不到还是超时了。
//    b) 相关性判定在「中文标题 + 英文发布名」时必然判不相关
//       （既不互相包含，分词也永远命中不了），把**每一个**结果都滤掉 →
//       搜索返回空 → 回到 (a)。
//
// 2. 这些判定原先是私有方法，没法单测 → 抽成纯函数
//    （`shouldShowMagnetSection` / `isTorrentResultRelevant`）。
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/torrent_player_models.dart';

void main() {
  group('磁力结果相关性判定 isTorrentResultRelevant', () {
    test('中文标题 + 英文发布名 → 放行（旧实现会全滤空）', () {
      // 这就是「教父」搜不到磁力的直接原因。
      expect(
        isTorrentResultRelevant(
          'The.Godfather.1972.1080p.BluRay.x264.YIFY',
          '教父',
        ),
        isTrue,
        reason: '中文标题无法与英文发布名比对，不该把结果全判为不相关',
      );
    });

    test('中文标题 + 中文结果名 → 仍按包含关系判定', () {
      expect(isTorrentResultRelevant('教父 1972 1080p 高清', '教父'), isTrue);
    });

    test('英文标题命中分词 → 相关', () {
      expect(
        isTorrentResultRelevant(
          'The.Godfather.1972.1080p.BluRay.x264.YIFY',
          'The Godfather',
        ),
        isTrue,
      );
    });

    test('英文标题完全无关 → 不相关（过滤仍然有效）', () {
      // 注意：分词匹配是**子串**匹配，所以 "Some.Other.Movie" 里的 "other"
      // 含有 "the" 会被判为相关（旧实现一直如此，本次未改判定语义）。
      // 这里用一个不含任何标题子串的样本。
      expect(
        isTorrentResultRelevant(
          'Ocean.S.Eleven.2016.1080p.WEB-DL',
          'The Godfather',
        ),
        isFalse,
      );
    });

    test('空标题 → 放行（不做无意义的过滤）', () {
      expect(isTorrentResultRelevant('Anything.2020.1080p', ''), isTrue);
    });
  });

  group('搜索页磁力资源模块可见性 shouldShowMagnetSection', () {
    test('磁力搜索失败/超时（无结果、没在搜、有错误）→ 仍要展示模块', () {
      expect(
        shouldShowMagnetSection(
          resultCount: 0,
          isSearching: false,
          hasError: true,
        ),
        isTrue,
        reason: '旧实现这里返回 false → 模块连同提示一起消失',
      );
    });

    test('有结果 → 展示', () {
      expect(
        shouldShowMagnetSection(resultCount: 3, isSearching: false, hasError: false),
        isTrue,
      );
    });

    test('正在搜 → 展示', () {
      expect(
        shouldShowMagnetSection(resultCount: 0, isSearching: true, hasError: false),
        isTrue,
      );
    });

    test('什么都没发生（没结果、没在搜、没错误）→ 不展示', () {
      expect(
        shouldShowMagnetSection(
          resultCount: 0,
          isSearching: false,
          hasError: false,
        ),
        isFalse,
      );
    });
  });
}
