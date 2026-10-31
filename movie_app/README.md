# movie_app

跨端影视播放应用（Android / iOS / Web / 桌面）。

## 开发规范与校验

- 技术说明（全功能技术点 + 变更记录，功能更新后同步）：[docs/技术说明.md](docs/技术说明.md)
- 验证方式与全部用例清单（含 HLS 真实片源样本库）：[docs/验证与用例清单.md](docs/验证与用例清单.md)
- 测试策略与覆盖报告（各轮次的设计取舍与用例演进，**历史记录**）：[docs/测试策略与覆盖报告.md](docs/测试策略与覆盖报告.md)
- 本地一键校验（与 CI 一致）：在仓库根目录执行 `powershell -File tool/verify.ps1`

> 说明：`docs/` 曾在 commit `312c9f0` 的代码瘦身中被整体删除，早期 README 引用的
> `code_standards.md` / `deeplink.md` / `detail_page_spec.md` / `features_by_platform.md` /
> `qa_review.md` / `static-gallery/` 均不再存在（2026-10-01 已清理死链）。

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
