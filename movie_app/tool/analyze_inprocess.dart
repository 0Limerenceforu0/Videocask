// 进程内静态分析器（flutter analyze 的应急替代）。
//
// 适用：本机被第三方内核驱动（如 LudashiProtect64.sys）拦截了「只读打开命名管道」，
// 导致 Dart 起不了子进程，flutter analyze / test / build 全部报
//   ProcessException: CreateFile failed 231 (所有的管道范例都在使用中。)
// 本脚本直接用 package:analyzer 在当前进程内做分析，不需要 spawn 任何子进程。
//
// 用法（Windows 路径要写反斜杠或用 / 均可）：
//   dart run tool/analyze_inprocess.dart <要分析的项目根目录>
//   dart run tool/analyze_inprocess.dart lib/pages/detail
// 退出码：有 ERROR 时返回 1，否则 0。
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';

class _Issue {
  final String severity;
  final String file;
  final int line;
  final int col;
  final String code;
  final String message;

  _Issue(
    this.severity,
    this.file,
    this.line,
    this.col,
    this.code,
    this.message,
  );

  Map<String, Object?> toJson() => {
        'severity': severity,
        'file': file,
        'line': line,
        'col': col,
        'code': code,
        'message': message,
      };

  @override
  String toString() => '$severity - $file:$line:$col - $code - $message';
}

Future<void> main(List<String> args) async {
  final target = args.isNotEmpty ? args[0] : Directory.current.path;
  final root = Directory(target).absolute.path.replaceAll('/', r'\');
  final asJson = args.contains('--json');
  final collection = AnalysisContextCollection(includedPaths: [root]);

  final issues = <_Issue>[];
  final seen = <String>{};
  var scanned = 0;

  for (final ctx in collection.contexts) {
    final files = ctx.contextRoot
        .analyzedFiles()
        .where((f) => f.endsWith('.dart'))
        .toList()
      ..sort();
    for (final path in files) {
      if (path.contains('.dart_tool')) continue;
      if (path.contains(
        '${Platform.pathSeparator}build${Platform.pathSeparator}',
      )) {
        continue;
      }
      final result = await ctx.currentSession.getErrors(path);
      if (result is! ErrorsResult) continue;
      scanned++;
      for (final e in result.errors) {
        final file = e.source.fullName;
        final key = '$file:${e.offset}:${e.errorCode.name}';
        if (!seen.add(key)) continue;
        final loc = result.lineInfo.getLocation(e.offset);
        // analyzer 各版本 API 不一致（6.x 无 ErrorCode.severity，12.x 有），
        // 这里统一走动态取值，保证在任何解析到的版本上都能跑。
        final dyn = e as dynamic;
        String typeName = '';
        try {
          typeName = dyn.errorCode.type.name as String;
        } catch (_) {}
        String sevName = 'INFO';
        try {
          sevName = dyn.severity.name as String;
        } catch (_) {
          try {
            sevName = dyn.errorCode.severity.name as String;
          } catch (_) {}
        }
        final sev = (typeName == 'COMPILE_TIME_ERROR' ||
                typeName == 'STATIC_TYPE_ERROR')
            ? 'ERROR'
            : sevName.toUpperCase();
        issues.add(
          _Issue(
            sev,
            file,
            loc.lineNumber,
            loc.columnNumber,
            e.errorCode.name,
            e.message,
          ),
        );
      }
    }
  }

  issues.sort((a, b) {
    final r = b.severity.compareTo(a.severity);
    return r != 0 ? r : a.file.compareTo(b.file);
  });

  if (asJson) {
    const encoder = JsonEncoder.withIndent('  ');
    stdout.writeln(encoder.convert(issues.map((i) => i.toJson()).toList()));
  } else {
    for (final i in issues) {
      stdout.writeln(i);
    }
  }

  final errs = issues.where((i) => i.severity == 'ERROR').length;
  final warns = issues.where((i) => i.severity == 'WARNING').length;
  final infos =
      issues.where((i) => i.severity == 'INFO' || i.severity == 'LINT').length;
  stderr.writeln('SCANNED: $scanned files  TOTAL: ${issues.length}  '
      'ERROR=$errs  WARNING=$warns  INFO/LINT=$infos');
  exit(errs > 0 ? 1 : 0);
}
