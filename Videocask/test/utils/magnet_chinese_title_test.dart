import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/utils/magnet_chinese_title.dart';

Movie _movie({
  required String name,
  String year = '',
  String desc = '',
}) {
  return Movie(
    id: name,
    name: name,
    year: year,
    description: desc,
  );
}
void main() {
  group('extractYearFromTorrentName', () {
    test('取发布名里的年份', () {
      expect(
        extractYearFromTorrentName('The.Godfather.1972.1080p.BluRay'),
        '1972',
      );
      expect(
        extractYearFromTorrentName('The Shawshank Redemption 1994 2160p'),
        '1994',
      );
    });

    test('画质数字不是年份', () {
      // 1080 / 2160 / 480 都是四位但不是 19xx/20xx。
      expect(extractYearFromTorrentName('Movie.1080p.x264'), isNull);
      expect(extractYearFromTorrentName('Movie.2160p'), isNull);
    });

    test('没有年份时返回 null', () {
      expect(extractYearFromTorrentName('Some.Release.Name'), isNull);
    });
  });

  group('cleanChineseMovieName', () {
    test('剥掉尾部方括号备注', () {
      expect(cleanChineseMovieName('教父[电影解说]'), '教父');
      expect(cleanChineseMovieName('教父2【完整版】'), '教父2');
      expect(cleanChineseMovieName('教父（国语）'), '教父');
    });

    test('没有备注时原样返回', () {
      expect(cleanChineseMovieName('肖申克的救赎'), '肖申克的救赎');
    });
  });

  group('isCanonicalChineseTitle', () {
    test('正片名通过', () {
      expect(isCanonicalChineseTitle('教父'), isTrue);
      expect(isCanonicalChineseTitle('肖申克的救赎'), isTrue);
    });

    test('解说 / 抢先看等衍生条目不通过', () {
      expect(isCanonicalChineseTitle('教父[电影解说]'), isFalse);
      expect(isCanonicalChineseTitle('某片抢先看'), isFalse);
      expect(isCanonicalChineseTitle('某片BD高清'), isFalse);
    });

    test('非中文名不通过', () {
      expect(isCanonicalChineseTitle('The Godfather'), isFalse);
      expect(isCanonicalChineseTitle(''), isFalse);
    });
  });

  group('chineseNameFromQuery', () {
    test('中文搜索词直接给出片名', () {
      expect(chineseNameFromQuery('教父'), '教父');
      expect(chineseNameFromQuery('肖申克的救赎'), '肖申克的救赎');
    });

    test('带画质后缀时剥掉', () {
      expect(chineseNameFromQuery('肖申克的救赎 1080p'), '肖申克的救赎');
    });

    test('英文搜索词没有中文名', () {
      expect(chineseNameFromQuery('The Shawshank Redemption'), isNull);
    });

    test('空搜索词没有中文名', () {
      expect(chineseNameFromQuery(''), isNull);
      expect(chineseNameFromQuery(null), isNull);
    });
  });

  group('baseTitleOf', () {
    test('剥掉画质 / 年份 / 发布组后缀', () {
      expect(
        baseTitleOf('The.Godfather.1972.1080p.BluRay.x264-GROUP'),
        'The Godfather',
      );
      expect(
        baseTitleOf('The Shawshank Redemption 1994 1080p'),
        'The Shawshank Redemption',
      );
    });

    test('剥掉方括号标签', () {
      expect(baseTitleOf('Movie.Title.1080p[国语中字]'), 'Movie Title');
    });

    test('纯画质 / 纯数字标题返回空', () {
      expect(baseTitleOf('1080p'), '');
      expect(baseTitleOf('2020'), '');
    });

    test('空串返回空', () {
      expect(baseTitleOf('  '), '');
    });
  });

  group('resolveChineseTitleForTorrent', () {
    test('资源名已含中文时不再贴标签', () {
      expect(
        resolveChineseTitleForTorrent(
          torrentName: '教父.The.Godfather.1972.1080p',
          searchResults: const [],
          query: '教父',
        ),
        isNull,
      );
    });

    test('用影视结果的年份对齐出中文名', () {
      final results = [
        _movie(name: '教父', year: '1972', desc: 'x' * 60),
        _movie(name: '教父2', year: '1974', desc: 'x' * 60),
      ];
      expect(
        resolveChineseTitleForTorrent(
          torrentName: 'The.Godfather.1972.1080p.BluRay.x264-GROUP',
          searchResults: results,
          query: '教父',
        ),
        '教父',
      );
      expect(
        resolveChineseTitleForTorrent(
          torrentName: 'The.Godfather.Part.II.1974.1080p',
          searchResults: results,
          query: '教父2',
        ),
        '教父2',
      );
    });

    test('年份不冲突时不乱贴别的年份的片名', () {
      final results = [
        _movie(name: '教父', year: '1972', desc: 'x' * 60),
        _movie(name: '教父2', year: '1974', desc: 'x' * 60),
      ];
      // 资源是 1990 年的第三部，但影视结果里只有 1972/1974 → 不贴。
      expect(
        resolveChineseTitleForTorrent(
          torrentName: 'The.Godfather.Part.III.1990.1080p',
          searchResults: results,
          query: '教父',
        ),
        isNull,
      );
    });

    test('影视结果没回来时回退到中文搜索词', () {
      expect(
        resolveChineseTitleForTorrent(
          torrentName: 'The.Godfather.1972.1080p',
          searchResults: const [],
          query: '教父',
        ),
        '教父',
      );
    });

    test('英文搜索词 + 无影视结果 → 没有可信中文名', () {
      expect(
        resolveChineseTitleForTorrent(
          torrentName: 'The.Godfather.1972.1080p',
          searchResults: const [],
          query: 'The Godfather',
        ),
        isNull,
      );
    });

    test('解说类条目不会被当成正片名贴上去', () {
      final results = [
        _movie(name: '教父[电影解说]', year: '1972', desc: 'x' * 60),
      ];
      expect(
        resolveChineseTitleForTorrent(
          torrentName: 'The.Godfather.1972.1080p',
          searchResults: results,
          query: '教父',
        ),
        isNull,
      );
    });

    // 🔴 2026-10-27 真机实测的错配回归。
    //
    // 搜「流浪地球」时，磁力名 `The.Wandering.Earth.2018` 抽出的年份是 2018，
    // 而 CMS 里《环太平洋：雷霆再起》恰好也是 2018 —— 旧实现「年份一致 +100」
    // 直接让它夺标，卡片上显示成「环太平洋：雷霆再起 中文名」。
    // 现在片名不相关一律淘汰。
    test('同年不同片不会被抢走中文名', () {
      final results = [
        _movie(name: '环太平洋：雷霆再起', year: '2018', desc: 'x' * 60),
      ];
      expect(
        resolveChineseTitleForTorrent(
          torrentName: 'The.Wandering.Earth.2018.1080p.BluRay',
          searchResults: results,
          query: '流浪地球',
        ),
        isNull,
      );
    });

    // 同一次真机复测抓到的第二个错配：收紧后仍然只共享「流浪」两个字，
    // 《流浪兄妹：认个爹爹当守护》(2018) 差点又被贴到
    // `The.Wandering.Earth.2018` 上。现在要求片名互相包含。
    test('只共享「流浪」两个字不算同一部片', () {
      final results = [
        _movie(name: '流浪兄妹：认个爹爹当守护', year: '2018', desc: 'x' * 60),
      ];
      expect(
        resolveChineseTitleForTorrent(
          torrentName: 'The.Wandering.Earth.2018.1080p.BluRay.x264-REGERT',
          searchResults: results,
          query: '流浪地球',
        ),
        isNull,
      );
    });

    // 同一次真机实测的另一半：apibay 对中文查询返回的是无关热门榜，
    // 那些资源（同为 2019 年）曾被贴上「流浪地球」。
    test('片名无关的资源不会被贴成搜索词片名', () {
      final results = [
        _movie(name: '流浪地球', year: '2019', desc: 'x' * 60),
        _movie(name: '三毛流浪记', year: '1949', desc: 'x' * 60),
      ];
      expect(
        resolveChineseTitleForTorrent(
          torrentName: 'Adobe.Photoshop.2021.v22.5.1.Multilingual',
          searchResults: results,
          query: '流浪地球',
        ),
        isNull,
      );
    });

    test('片名相关时正常给出中文名（不是一味返回 null）', () {
      final results = [
        _movie(name: '流浪地球', year: '2019', desc: 'x' * 60),
      ];
      expect(
        resolveChineseTitleForTorrent(
          torrentName: 'The.Wandering.Earth.2019.1080p.BluRay',
          searchResults: results,
          query: '流浪地球',
        ),
        '流浪地球',
      );
    });

    test('空资源名返回 null', () {
      expect(
        resolveChineseTitleForTorrent(
          torrentName: '  ',
          searchResults: const [],
          query: '教父',
        ),
        isNull,
      );
    });
  });
}
