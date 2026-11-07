import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:movie_app/config/constants.dart';

class _CaseResult {
  final String sourceName;
  final bool listOk;
  final bool searchOk;
  final bool detailOk;
  final String note;

  const _CaseResult({
    required this.sourceName,
    required this.listOk,
    required this.searchOk,
    required this.detailOk,
    required this.note,
  });

  bool get allOk => listOk && searchOk && detailOk;
}

Future<Map<String, dynamic>?> _getJson(Dio dio, String url) async {
  try {
    final resp = await dio.get<String>(url);
    final data = resp.data;
    if (data == null || data.isEmpty) return null;
    final decoded = jsonDecode(data);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  } catch (_) {
    return null;
  }
}

List<dynamic> _pickList(Map<String, dynamic>? map) {
  if (map == null) return const [];
  final raw = map['list'];
  if (raw is List) return raw;
  return const [];
}

String _pickId(dynamic item) {
  if (item is! Map) return '';
  final id = item['vod_id'] ?? item['id'];
  return id?.toString() ?? '';
}

Future<_CaseResult> _checkOneSource(Dio dio, Map<String, String> source) async {
  final name = source['name'] ?? '未知源';
  final base = source['url'] ?? '';
  if (base.isEmpty) {
    return _CaseResult(
      sourceName: name,
      listOk: false,
      searchOk: false,
      detailOk: false,
      note: '源地址为空',
    );
  }

  final listData = await _getJson(dio, '${base}ac=detail&pg=1');
  final list = _pickList(listData);
  final listOk = list.isNotEmpty;

  final searchData = await _getJson(
    dio,
    '${base}ac=detail&wd=${Uri.encodeComponent('三体')}&pg=1',
  );
  final searchList = _pickList(searchData);
  final searchOk = searchList.isNotEmpty;

  var detailOk = false;
  var note = '';
  if (list.isNotEmpty) {
    final id = _pickId(list.first);
    if (id.isNotEmpty) {
      final detailData = await _getJson(dio, '${base}ac=detail&ids=$id');
      final detailList = _pickList(detailData);
      detailOk = detailList.isNotEmpty;
      if (!detailOk) {
        note = '详情链路失败（id=$id）';
      }
    } else {
      note = '列表无可用影片ID';
    }
  } else {
    note = '列表链路失败';
  }

  return _CaseResult(
    sourceName: name,
    listOk: listOk,
    searchOk: searchOk,
    detailOk: detailOk,
    note: note,
  );
}

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
      headers: const {
        'User-Agent': 'movie_app_real_regression/1.0',
      },
    ),
  );

  final results = <_CaseResult>[];
  for (final source in AppConstants.defaultSources) {
    final result = await _checkOneSource(dio, source);
    results.add(result);
  }

  stdout.writeln('==== 真实接口回归结果 ====');
  for (final r in results) {
    stdout.writeln(
      '${r.sourceName} | 列表:${r.listOk ? '通过' : '失败'} '
      '| 搜索:${r.searchOk ? '通过' : '失败'} '
      '| 详情:${r.detailOk ? '通过' : '失败'}'
      '${r.note.isNotEmpty ? ' | 备注:${r.note}' : ''}',
    );
  }

  final passed = results.where((e) => e.allOk).length;
  stdout.writeln('汇总：${results.length} 个源，完整通过 $passed 个。');

  // 非全通过返回非零退出码，方便自动化流水线判断
  if (passed != results.length) {
    throw Exception('存在未完全通过的真实接口链路');
  }
}
