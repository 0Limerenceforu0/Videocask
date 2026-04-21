# 代码规范（movie_app）

本仓库在合并或发布前应满足以下检查（与 CI / `tool/verify.ps1` 一致）。

## 必做检查

| 步骤 | 命令 |
|------|------|
| 格式化 | `dart format lib test tool`（或 `dart format .`） |
| 格式是否偏离 | `dart format --output=none --set-exit-if-changed lib test tool` |
| 静态分析 | `flutter analyze` |
| 测试 | `flutter test` |

## 行尾与格式化

- 使用 **LF** 行尾；`.gitattributes` 已对常见文本类型声明 `eol=lf`。
- 提交前在本地执行一次 `dart format .`，避免 Windows 下 CRLF 与 `dart format` 反复冲突。

## 国际化（用户可见文案）

- **新增或修改面向用户的字符串**时，在 `lib/l10n/app_zh.arb` 与 `lib/l10n/app_en.arb` 增加同名 key，然后运行：
  ```bash
  flutter gen-l10n
  ```
- 在 Widget 中使用 `AppLocalizations.of(context)!` 取值，避免在业务代码中硬编码中英文句子（少量调试文案除外）。

## 无障碍

- 主导航等交互控件应提供清晰的 **语义标签**（例如 `NavigationDestination` 的 `label` / `tooltip`）。
- 自定义可点击区域若仅有图标，请补充 `Semantics` 或 `tooltip`。

## 异步与 Context

- `async` 间隙后使用 `BuildContext` 前必须判断 `context.mounted`。
- 有意不 `await` 的 `Future` 使用 `unawaited(...)`（`dart:async`），以满足 `unawaited_futures` 规则。

## 分析器配置

- 全局规则见项目根目录 `analysis_options.yaml`（含 `flutter_lints` 与项目自定义项）。
- 生成文件（如 `*.g.dart`）已排除在分析之外；`lib/l10n/app_localizations*.dart` 为生成代码，可随 ARB 重新生成。
- 仓库内若嵌套其他 Flutter 工程（如 `self_fitness/`），已在 `analysis_options.yaml` 中 `exclude`，避免 `flutter analyze` 误扫子项目。
