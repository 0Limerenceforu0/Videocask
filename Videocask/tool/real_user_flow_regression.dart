import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:movie_app/config/constants.dart';

class _FlowResult {
  final String sourceName;
  final bool categoryOk;
  final bool homeOk;
  final bool searchOk;
  final bool detailOk;
  final bool playUrlOk;
  final String note;

  const _FlowResult({
    required this.sourceName,
    required this.categoryOk,
    required this.homeOk,
    required this.searchOk,
    required this.detailOk,
    required this.playUrlOk,
    required this.note,
  });

  bool get allOk => categoryOk && homeOk && searchOk && detailOk && playUrlOk;
}

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
  if (data == null) return const [];
  final raw = data[key];
  if (raw is List) return raw;
  return const [];
}

String _idOf(dynamic item) {
  if (item is! Map) return '';
  return (item['vod_id'] ?? item['id'] ?? '').toString();
}

String _playUrlOf(dynamic item) {
  if (item is! Map) return '';
  return (item['vod_play_url'] ?? '').toString();
}

Future<_FlowResult> _checkFlow(Dio dio, Map<String, String> source) async {
  final name = source['name'] ?? '未知源';
  final base = source['url'] ?? '';
  if (base.isEmpty) {
    return _FlowResult(
      sourceName: name,
      categoryOk: false,
      homeOk: false,
      searchOk: false,
      detailOk: false,
      playUrlOk: false,
      note: '源地址为空',
    );
  }

  final categoryData = await _getJson(dio, '${base}ac=list');
  final classes = _listOf(categoryData, 'class');
  final categoryOk = classes.isNotEmpty;
  var note = '';

  final homeData = await _getJson(dio, '${base}ac=detail&pg=1');
  final homeList = _listOf(homeData, 'list');
  final homeOk = homeList.isNotEmpty;

  final searchData = await _getJson(
    dio,
    '${base}ac=detail&wd=${Uri.encodeComponent('三体')}&pg=1',
  );
  final searchList = _listOf(searchData, 'list');
  final searchOk = searchList.isNotEmpty;

  var detailOk = false;
  var playUrlOk = false;
  if (homeList.isNotEmpty) {
    final candidates = homeList.take(10).toList();
    for (final item in candidates) {
      final id = _idOf(item);
      if (id.isEmpty) continue;
      final detailData = await _getJson(dio, '${base}ac=detail&ids=$id');
      final detailList = _listOf(detailData, 'list');
      if (detailList.isEmpty) {
        continue;
      }
      detailOk = true;
      final play = _playUrlOf(detailList.first);
      if (play.trim().isNotEmpty) {
        playUrlOk = true;
        break;
      }
    }
    if (!detailOk) {
      note = '候选详情链路均失败';
    } else if (!playUrlOk) {
      note = '候选详情均无播放地址';
    }
  } else {
    note = '首页列表为空';
  }

  return _FlowResult(
    sourceName: name,
    categoryOk: categoryOk,
    homeOk: homeOk,
    searchOk: searchOk,
    detailOk: detailOk,
    playUrlOk: playUrlOk,
    note: note,
  );
}

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
      headers: const {'User-Agent': 'movie_app_real_flow/1.0'},
    ),
  );

  final results = <_FlowResult>[];
  for (final source in AppConstants.defaultSources) {
    results.add(await _checkFlow(dio, source));
  }

  stdout.writeln('==== 真实用户流程回归结果 ====');
  for (final r in results) {
    stdout.writeln(
      '${r.sourceName} | 分类:${r.categoryOk ? '通过' : '失败'} '
      '| 首页:${r.homeOk ? '通过' : '失败'} '
      '| 搜索:${r.searchOk ? '通过' : '失败'} '
      '| 详情:${r.detailOk ? '通过' : '失败'} '
      '| 播放地址:${r.playUrlOk ? '通过' : '失败'}'
      '${r.note.isNotEmpty ? ' | 备注:${r.note}' : ''}',
    );
  }

  final passed = results.where((e) => e.allOk).length;
  stdout.writeln('汇总：${results.length} 个源，完整通过 $passed 个。');
  if (passed != results.length) {
    throw Exception('存在未完全通过的真实用户流程链路');
  }
}
