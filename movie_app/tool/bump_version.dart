// 递增版本号并同步 `lib/config/constants.dart`。
//
// 用法（在 Flutter 项目根目录）:
//   dart run tool/bump_version.dart           # patch +1、构建号 +1（默认）
//   dart run tool/bump_version.dart --minor   # minor +1、patch 归零
//   dart run tool/bump_version.dart --major   # major +1、其余归零
//
// 版本规则（用户 2026-10-22 定）：
//   只有「Android + Windows + Web 三端一次性打包交付」时才升版本号；
//   代码改动 / analyze / 单测 / 单端构建都不升。
//
// 注意：本脚本只处理「机器能改的两处」——pubspec 与 constants。
// `lib/config/changelog.dart`、`CHANGELOG.md`、README 的人工说明仍需发版时补齐，
// `tool/publish_release.py` 会在发布前校验 pubspec 与 constants 是否一致。

import 'dart:io';

final _versionLine = RegExp(
  r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
  multiLine: true,
);

final _constVersionLine = RegExp(
  r"""(appVersion\s*=\s*')([^']+)(')""",
);

void main(List<String> args) {
  final bumpMinor = args.contains('--minor');
  final bumpMajor = args.contains('--major');

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
      'bump_version: expected version like 1.1.7+67 in pubspec.yaml',
    );
    exit(1);
  }

  var major = int.parse(match.group(1)!);
  var minor = int.parse(match.group(2)!);
  var patch = int.parse(match.group(3)!);
  final oldBuild = int.parse(match.group(4)!);
  final build = oldBuild + 1;

  final oldVersion = '$major.$minor.$patch+$oldBuild';

  // 只动该动的位，不要把 patch 直接写成构建号
  // （旧实现 `patch = build` 会把 1.1.7+67 变成 1.1.68+68）。
  if (bumpMajor) {
    major += 1;
    minor = 0;
    patch = 0;
  } else if (bumpMinor) {
    minor += 1;
    patch = 0;
  } else {
    patch += 1;
  }

  final newVersion = '$major.$minor.$patch+$build';
  pubspec.writeAsStringSync(
    content.replaceFirst(_versionLine, 'version: $newVersion'),
  );

  // 同步应用内版本常量（更新检查读取的就是它）。
  final constants = File('lib/config/constants.dart');
  if (!constants.existsSync()) {
    stderr.writeln('bump_version: 找不到 lib/config/constants.dart');
    exit(1);
  }
  final constContent = constants.readAsStringSync();
  if (!_constVersionLine.hasMatch(constContent)) {
    stderr.writeln('bump_version: constants.dart 里找不到 appVersion');
    exit(1);
  }
  constants.writeAsStringSync(
    constContent.replaceFirstMapped(
      _constVersionLine,
      (m) => '${m.group(1)}$major.$minor.$patch${m.group(3)}',
    ),
  );

  stdout.writeln('Version: $oldVersion -> $newVersion');
  stdout.writeln(
    '已同步 lib/config/constants.dart (appVersion = $major.$minor.$patch)',
  );
  stdout.writeln(
    '还需手工补：lib/config/changelog.dart、CHANGELOG.md、README（若涉及）',
  );
}
