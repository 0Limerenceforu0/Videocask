import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:movie_app/config/constants.dart';

Future<Map<String, dynamic>?> _getJson(Dio dio, String url) async {
  try {
    final resp = await dio.get<String>(url);
    final text = resp.data;
    if (text == null || text.isEmpty) return null;
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  } catch (_) {
    return null;
  }
}

List<dynamic> _listOf(Map<String, dynamic>? data, String key) {
  final raw = data?[key];
  return raw is List ? raw : const [];
}

String _idOf(dynamic item) =>
    item is Map ? (item['vod_id'] ?? item['id'] ?? '').toString() : '';

String _playUrlOf(dynamic item) =>
    item is Map ? (item['vod_play_url'] ?? '').toString() : '';

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
    ),
  );

  var sourcePass = 0;
  var playablePass = 0;

  stdout.writeln('==== 真实用户流程分级报告 ====');
  for (final source in AppConstants.defaultSources) {
    final name = source['name'] ?? '未知源';
    final base = source['url'] ?? '';

    final cls = _listOf(await _getJson(dio, '${base}ac=list'), 'class');
    final home = _listOf(await _getJson(dio, '${base}ac=detail&pg=1'), 'list');
    final search = _listOf(
      await _getJson(
        dio,
        '${base}ac=detail&wd=${Uri.encodeComponent('三体')}&pg=1',
      ),
      'list',
    );

    var detailOk = false;
    var playable = false;
    for (final item in home.take(12)) {
      final id = _idOf(item);
      if (id.isEmpty) continue;
      final detail =
          _listOf(await _getJson(dio, '${base}ac=detail&ids=$id'), 'list');
      if (detail.isEmpty) continue;
      detailOk = true;
      if (_playUrlOf(detail.first).trim().isNotEmpty) {
        playable = true;
        break;
      }
    }

    final sourceLevelOk =
        cls.isNotEmpty && home.isNotEmpty && search.isNotEmpty && detailOk;
    if (sourceLevelOk) sourcePass++;
    if (playable) playablePass++;

    stdout.writeln(
      '$name | 源可用:${sourceLevelOk ? '通过' : '失败'} '
      '| 可播放:${playable ? '通过' : '失败'}',
    );
  }

  stdout.writeln(
    '汇总：源可用通过 $sourcePass/${AppConstants.defaultSources.length}，可播放通过 $playablePass/${AppConstants.defaultSources.length}',
  );
}
