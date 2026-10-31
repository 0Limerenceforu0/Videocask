import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/imdb_lookup_service.dart';
import 'package:movie_app/services/video_title_resolve_service.dart';

/// 真网探针：验证中文片名 → IMDb 解析是否还会把「战狼」解析成 Logan。
/// 运行：flutter test test/probe/title_resolve_probe_test.dart --concurrency=1
void main() {
  test('title resolve probe', () async {
    HttpOverrides.global = null;
    for (final item in [
      ('战狼', '2015'),
      ('我不是药神', '2018'),
    ]) {
      final id = await ImdbLookupService.instance.resolveForVideoTitle(
        item.$1,
        year: item.$2,
      );
      // ignore: avoid_print
      print('IMDB ${item.$1}(${item.$2}) -> $id');
      final r = await VideoTitleResolveService.instance.resolve(
        item.$1,
        year: item.$2,
      );
      // ignore: avoid_print
      print(
        'RESOLVE ${item.$1} -> tt=${r?.imdbId} en=${r?.englishTitle} '
        'local=${r?.localTitle} year=${r?.year} src=${r?.source}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
