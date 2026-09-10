// 递增 pubspec.yaml 构建号（+N），并将 patch 同步为 N（安装界面显示 1.0.N）。
//
// 用法（在项目根目录）:
//   dart run tool/bump_version.dart
//   dart run tool/bump_version.dart --patch   # 额外 +1 patch（少见，一般用默认即可）

import 'dart:io';

final _versionLine = RegExp(
  r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
  multiLine: true,
);

void main(List<String> args) {
  final bumpPatch = args.contains('--patch');
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln(
        'bump_version: pubspec.yaml not found (run from project root)');
    exit(1);
  }

  final content = pubspec.readAsStringSync();
  final match = _versionLine.firstMatch(content);
  if (match == null) {
    stderr.writeln(
      'bump_version: expected version like 1.0.0+1 in pubspec.yaml',
    );
    exit(1);
  }

  var major = int.parse(match.group(1)!);
  var minor = int.parse(match.group(2)!);
  var patch = int.parse(match.group(3)!);
  var build = int.parse(match.group(4)!);

  final oldVersion = '${major}.${minor}.${patch}+$build';

  build += 1;
  patch = build;
  if (bumpPatch) {
    patch += 1;
  }

  final newVersion = '${major}.${minor}.${patch}+$build';
  final updated = content.replaceFirst(
    _versionLine,
    'version: $newVersion',
  );
  pubspec.writeAsStringSync(updated);

  stdout.writeln('Version: $oldVersion -> $newVersion');
}
