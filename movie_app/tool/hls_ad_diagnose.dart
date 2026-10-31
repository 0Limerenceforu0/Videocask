/// HLS 广告过滤「诊断器」：对真实 m3u8 只打印会删哪些分片，不写任何文件。
///
/// 用途：换片源 / 遇到新广告形态时，先用它确认过滤器判得对不对，再决定要不要
/// 追加规则。启发式是概率手段，没有真实样本验证的改动一律不该进主干。
///
/// 用法：
///   dart tool/hls_ad_diagnose.dart <m3u8文件或URL>...      逐个诊断
///   dart tool/hls_ad_diagnose.dart --fixtures              诊断 test/fixtures/hls 全部
///   dart tool/hls_ad_diagnose.dart --url <m3u8地址>        直接抓线上（需可直连）
///
/// 输出每份列表的：块结构（DISCONTINUITY 切分）、判定为广告的块、被删分片、
/// 以及「已知广告特征残留」检查（命中 /adjump/ /ad/ 等却没被删 = 漏判）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:movie_app/services/hls_ad_filter.dart';

/// 已知广告路径特征（命中却没被删 → 漏判告警）。
const _knownAdMarkers = <String>[
  '/adjump/',
  '/ad/',
  '/ads/',
  '/advert',
  '/preroll/',
  '/postroll/',
  '/midroll/',
  '/adtime/',
  '/gg/',
  '_ad_',
];

class _Block {
  _Block(this.index);
  final int index;
  final List<double> durations = <double>[];
  final List<String> urls = <String>[];
  double get total {
    var t = 0.0;
    for (final d in durations) {
      t += d;
    }
    return t;
  }
}

void main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    return;
  }

  final entries = <_Entry>[];

  if (args.first == '--fixtures') {
    final dir = Directory('test/fixtures/hls');
    if (!dir.existsSync()) {
      stderr.writeln('未找到 ${dir.path}');
      exitCode = 1;
      return;
    }
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.m3u8')) continue;
      entries.add(
        _Entry(f.uri.pathSegments.last, () => f.readAsStringSync(), f.path),
      );
    }
  } else if (args.first == '--url') {
    for (final u in args.skip(1)) {
      try {
        final content = await _fetch(u);
        entries.add(_Entry(u, () => content, u));
      } catch (e) {
        stderr.writeln('抓取失败 $u: $e');
      }
    }
  } else {
    for (final p in args) {
      final f = File(p);
      if (!f.existsSync()) {
        stderr.writeln('文件不存在: $p');
        continue;
      }
      entries.add(
        _Entry(f.uri.pathSegments.last, () => f.readAsStringSync(), p),
      );
    }
  }

  for (final e in entries) {
    String content;
    try {
      content = e.load();
    } catch (err) {
      print('=== ${e.name}\n  读取失败: $err\n');
      continue;
    }
    _diagnose(e.name, content, e.base);
  }
}

class _Entry {
  _Entry(this.name, this.load, String baseOrPath)
      : base = baseOrPath.startsWith('http')
            ? baseOrPath
            : 'https://example.com/v/index.m3u8';
  final String name;
  final String Function() load;
  final String base;
}

/// 直接抓线上 m3u8（带 UA / Referer，绕常见防盗链）。
Future<String> _fetch(String url) async {
  final uri = Uri.parse(url);
  final client = HttpClient()..userAgent = 'Mozilla/5.0';
  try {
    final req = await client.getUrl(uri);
    req.headers.set('Referer', '${uri.scheme}://${uri.host}/');
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw 'HTTP ${resp.statusCode}';
    }
    final body = await resp.transform(utf8.decoder).join();
    return body;
  } finally {
    client.close(force: true);
  }
}

void _printUsage() {
  print('用法:');
  print('  dart tool/hls_ad_diagnose.dart <m3u8文件>...');
  print('  dart tool/hls_ad_diagnose.dart --fixtures');
}

void _diagnose(String name, String content, String base) {
  print('=' * 70);
  print('样本: $name');

  final blocks = _splitBlocks(content, base);
  final nonEmpty = blocks.where((b) => b.urls.isNotEmpty).toList();

  print(
      '总时长 ${_fmt(_total(nonEmpty))}  分片 ${nonEmpty.fold<int>(0, (a, b) => a + b.urls.length)}  非空块 ${nonEmpty.length}');

  // 与生产一致：内置路径特征 + 启发式（生产经 assets/ad_block_rules.json
  // 走 fromJson，同样并入内置特征）。
  final result = HlsAdFilter.filterContent(
    content,
    base,
    rules: AdBlockRules.builtin,
  );
  final kept = result.segments.map((s) => s.url).toSet();

  print('-- 块结构（* = 判定为广告）');
  for (final b in nonEmpty) {
    final removed = b.urls.every((u) => !kept.contains(u));
    final partial = !removed && b.urls.any((u) => !kept.contains(u));
    final mark = removed ? ' [AD]' : (partial ? ' [部分删除]' : '');
    print(
      '  块${b.index.toString().padLeft(2)}: ${b.urls.length.toString().padLeft(3)}片 '
      '${_fmt(b.total).padLeft(8)}  ${_firstUrl(b.urls)}$mark',
    );
  }

  print('-- 过滤结果');
  print('  原始 ${result.originalCount} 片 → 保留 ${result.segments.length} 片，'
      '剔除 ${result.removedSegments} 片 / ${result.removedSeconds.toStringAsFixed(2)}s');

  // 漏判检查：已知广告特征命中却仍在保留列表里。
  final missed = <String>[];
  for (final b in nonEmpty) {
    for (final u in b.urls) {
      if (!kept.contains(u)) continue;
      for (final m in _knownAdMarkers) {
        if (u.toLowerCase().contains(m)) {
          missed.add('$u  (命中 $m)');
          break;
        }
      }
    }
  }
  if (missed.isEmpty) {
    print('  已知广告特征残留: 无 ✅');
  } else {
    print('  已知广告特征残留: ${missed.length} 片 ❌ 漏判');
    for (final m in missed.take(5)) {
      print('      $m');
    }
  }

  // 误删检查：删掉的片里有没有「看起来像正片顺序命名」的。
  final removedUrls = <String>[];
  for (final b in nonEmpty) {
    for (final u in b.urls) {
      if (!kept.contains(u)) removedUrls.add(u);
    }
  }
  final suspicious = removedUrls.where((u) {
    // 命中已知广告路径特征的不算可疑（广告片本身也常用数字命名）。
    if (_knownAdMarkers.any((m) => u.toLowerCase().contains(m))) return false;
    final last = u.split('/').last;
    return RegExp(r'^\d{4,}\.ts$').hasMatch(last);
  }).length;
  if (suspicious > 0) {
    print('  ⚠️ 被删分片中有 $suspicious 片是纯数字顺序命名（疑似正片，请人工核对）');
  }
  print('');
}

double _total(List<_Block> blocks) {
  var t = 0.0;
  for (final b in blocks) {
    t += b.total;
  }
  return t;
}

String _fmt(double d) => '${d.toStringAsFixed(2)}s';

String _firstUrl(List<String> urls) {
  if (urls.isEmpty) return '';
  final u = urls.first;
  if (u.length <= 58) return u;
  return '...${u.substring(u.length - 55)}';
}

/// 按 DISCONTINUITY 切块（与过滤器一致）。
List<_Block> _splitBlocks(String content, String base) {
  final blocks = <_Block>[_Block(0)];
  var dur = 0.0;
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF:')) {
      dur = double.tryParse(line.substring(8).split(',').first.trim()) ?? 0;
      continue;
    }
    if (line.startsWith('#EXT-X-DISCONTINUITY')) {
      blocks.add(_Block(blocks.length));
      continue;
    }
    if (line.startsWith('#')) continue;
    final url = line.startsWith('http')
        ? line
        : Uri.parse(base).resolve(line).toString();
    blocks.last.durations.add(dur);
    blocks.last.urls.add(url);
  }
  return blocks;
}
