/// HLS 广告「样例抽取器」：判定某份 m3u8 里哪些分片是广告，并导出成 JSON。
///
/// 与 [hls_ad_diagnose] 的区别：那个只打印给人看，这个输出机器可读的 JSON，
/// 供 `tool/extract_ad_samples.py` 下载广告分片、转成 mp4 做留样与复盘。
///
/// 用法：
///   dart tool/hls_ad_extract.dart <m3u8文件> <baseUrl> [输出json路径]
///
/// 不写输出路径时打印到 stdout。
///
/// JSON 字段：
///   totalSeconds / originalCount / removedCount / removedSeconds / isVod
///   encrypted / keyUri / keyLine
///   adBlocks[]：每个连续广告块的 startSeconds（在整集中的起始时间）、
///                durationSeconds、position（head/mid/tail）、host、
///                segments[]（分片原始序号与绝对 URL）
library;

import 'dart:convert';
import 'dart:io';

import 'package:movie_app/services/hls_ad_filter.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      '用法: dart tool/hls_ad_extract.dart <m3u8文件> <baseUrl> [输出json路径]',
    );
    exitCode = 64;
    return;
  }
  final path = args[0];
  final base = args[1];
  final outPath = args.length >= 3 ? args[2] : null;

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('文件不存在: $path');
    exitCode = 66;
    return;
  }
  final content = file.readAsStringSync();

  final rules = _loadProductionRules();
  final result = HlsAdFilter.filterContent(content, base, rules: rules);

  // 复算原始分片序列（含被删的），用于定位广告在整集中的时间位置。
  final raw = _parseRaw(content, base);
  final keptSet = result.segments.map((s) => s.sourceIndex).toSet();
  final removed = raw.where((s) => !keptSet.contains(s.sourceIndex)).toList()
    ..sort((a, b) => a.sourceIndex.compareTo(b.sourceIndex));

  final totalSeconds = raw.fold<double>(
    0.0,
    (sum, s) => sum + s.duration,
  );

  final adBlocks = _mergeIntoBlocks(removed, raw, totalSeconds);

  final encrypted = content.contains('#EXT-X-KEY');
  final keyLine = _firstLine(content, '#EXT-X-KEY');

  final payload = <String, dynamic>{
    'sourceFile': path,
    'baseUrl': base,
    'totalSeconds': _r2(totalSeconds),
    'originalCount': raw.length,
    'keptCount': result.segments.length,
    'removedCount': removed.length,
    'removedSeconds': _r2(result.removedSeconds),
    'isVod': result.isVod,
    'encrypted': encrypted,
    'keyUri': encrypted ? _keyUri(keyLine, base) : null,
    'keyLine': keyLine,
    'adBlocks': adBlocks,
  };

  final text = const JsonEncoder.withIndent('  ').convert(payload);
  if (outPath == null) {
    stdout.writeln(text);
  } else {
    File(outPath).writeAsStringSync(text);
    stderr.writeln('已写出: $outPath');
  }
}

double _r2(double v) => (v * 100).round() / 100;

/// 与生产一致的规则：assets/ad_block_rules.json + 内置路径特征。
AdBlockRules _loadProductionRules() {
  try {
    final f = File('assets/ad_block_rules.json');
    if (!f.existsSync()) return AdBlockRules.builtin;
    final json = jsonDecode(f.readAsStringSync());
    if (json is Map<String, dynamic>) {
      return AdBlockRules.fromJson(json);
    }
  } catch (_) {
    // 解析失败退回内置
  }
  return AdBlockRules.builtin;
}

class _RawSeg {
  _RawSeg(this.sourceIndex, this.url, this.duration);
  final int sourceIndex;
  final String url;
  final double duration;
}

List<_RawSeg> _parseRaw(String content, String base) {
  final out = <_RawSeg>[];
  var currentDuration = 10.0;
  final baseUri = Uri.tryParse(base);
  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      if (line.startsWith('#EXTINF:')) {
        final v = line.substring('#EXTINF:'.length).split(',').first.trim();
        currentDuration = double.tryParse(v) ?? 10.0;
      }
      continue;
    }
    var url = line;
    if (baseUri != null && !line.startsWith('http')) {
      url = baseUri.resolve(line).toString();
    }
    out.add(_RawSeg(out.length, url, currentDuration));
  }
  return out;
}

/// 把被删分片按「原始序号连续」归并成块，并算出每块在整集中的起始秒数。
///
/// [all] 是完整分片列表（含保留的），用于累加前缀时长得出真实的起始时间点。
List<Map<String, dynamic>> _mergeIntoBlocks(
  List<_RawSeg> removed,
  List<_RawSeg> all,
  double totalSeconds,
) {
  final blocks = <Map<String, dynamic>>[];
  if (removed.isEmpty) return blocks;

  var group = <_RawSeg>[removed.first];
  for (var i = 1; i < removed.length; i++) {
    final prev = group.last;
    final cur = removed[i];
    if (cur.sourceIndex == prev.sourceIndex + 1) {
      group.add(cur);
    } else {
      blocks.add(_blockPayload(group, all, totalSeconds));
      group = <_RawSeg>[cur];
    }
  }
  blocks.add(_blockPayload(group, all, totalSeconds));
  return blocks;
}

Map<String, dynamic> _blockPayload(
  List<_RawSeg> group,
  List<_RawSeg> all,
  double totalSeconds,
) {
  final duration = group.fold<double>(0.0, (s, e) => s + e.duration);
  final startIndex = group.first.sourceIndex;
  final endIndex = group.last.sourceIndex;

  // 起始秒数 = 该块之前所有分片时长之和（前缀和）。
  var startSeconds = 0.0;
  for (var i = 0; i < startIndex && i < all.length; i++) {
    startSeconds += all[i].duration;
  }

  final hosts = <String>{};
  for (final s in group) {
    final h = Uri.tryParse(s.url)?.host ?? '';
    if (h.isNotEmpty) hosts.add(h);
  }

  return <String, dynamic>{
    'startIndex': startIndex,
    'endIndex': endIndex,
    'segmentCount': group.length,
    'startSeconds': _r2(startSeconds),
    'durationSeconds': _r2(duration),
    'position':
        _positionOf(startSeconds, startSeconds + duration, totalSeconds),
    'hosts': hosts.toList()..sort(),
    'segments': group
        .map(
          (s) => <String, dynamic>{
            'index': s.sourceIndex,
            'url': s.url,
            'duration': _r2(s.duration),
          },
        )
        .toList(),
  };
}

/// 位置标签：片头（整集前 8% 内起）/ 片尾（结束于整集末尾 8% 之后）/ 中插。
String _positionOf(double start, double end, double total) {
  if (total <= 0) return 'mid';
  if (start <= total * 0.08) return 'head';
  if (end >= total * 0.92) return 'tail';
  return 'mid';
}

String? _firstLine(String content, String prefix) {
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.startsWith(prefix)) return line;
  }
  return null;
}

String? _keyUri(String? keyLine, String base) {
  if (keyLine == null) return null;
  final m = RegExp(r'URI="([^"]+)"').firstMatch(keyLine);
  if (m == null) return null;
  final raw = m.group(1)!;
  if (raw.startsWith('http')) return raw;
  final baseUri = Uri.tryParse(base);
  return baseUri?.resolve(raw).toString() ?? raw;
}
