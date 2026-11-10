# 罐子 · Videocask

基于 Flutter 的跨端影视播放器：磁力 / BT 边下边播、媒体库管理、在线字幕、全屏与画面比例调节，支持 **Android / Windows / Web** 三端。

> 当前版本见 [`Videocask/pubspec.yaml`](Videocask/pubspec.yaml) 的 `version` 字段；每个版本的变更见 [`Videocask/CHANGELOG.md`](Videocask/CHANGELOG.md)。
> 版本号只在「三端一次性全部打包交付」时升，单端构建 / 测试不升。

## 仓库结构（这两个目录分别是什么）

仓库根目录下有两类内容，避免误解，这里说明清楚：

| 路径 | 是什么 |
|---|---|
| `Videocask/` | **项目源码本体**。Flutter 工程根目录，包含 `lib/`（Dart 代码）、`android/`（Android 原生工程）、`assets/`（字体 / 图标等资源）、`tool/`（构建与发版脚本）、`docs/`（技术文档）、`deliverables/`（三端打包产物，已 gitignore）、`test/`（单测）。 |
| `movie_app/`（历史遗留） | 旧目录名（`movie_app` → `Videocask`）改名时残留的调试文件，内容已并入 `Videocask/tool/`，**已从仓库删除**。若你仍看到它，说明查看的是旧提交 `e4b5804` 之前的快照。 |

> 后续如果希望「仓库根目录 = Flutter 工程根目录」（去掉 `Videocask/` 这一层嵌套），可以再做一次 flatten，目前保持现有布局。

## 功能概览

- **磁力 / BT 边下边播**：Torrentio / apibay / Knaben 聚合搜索，首帧看门狗、失败自愈、换集不串字幕。
- **媒体库**：收藏、历史、继续观看、分类与筛选。
- **字幕**：优先读取片源内封中文轨（简体优先），无内封时自动匹配在线中文源；支持本地字幕文件、AI 字幕兜底。
- **播放器**：全屏（可铺进挖孔安全区）、画面比例（自动 / 4:3 / 裁剪 / 原始）、倍速、锁屏、后台播放。
- **应用内更新**：读取 GitHub Releases，下载并安装新版本（Android 走系统安装器，Windows 走自替换脚本）。
- **三端一致**：界面语言固定中文（后续再开放语言开关）。

## 构建与发版（`tool/` 下的脚本）

| 脚本 | 作用 |
|---|---|
| `Videocask/tool/package_deliverables.py` | 把三端产物整理进 `deliverables/`：Android 三个 ABI 的 APK、Windows 绿色版 zip、Web zip。 |
| `Videocask/tool/publish_release.py` | 读取 `deliverables/`，在 GitHub 创建 Release 并上传安装包（资产名形如 `Videocask-android-arm64-v1.1.8.apk`）。需要 `GITHUB_TOKEN`（见 `.env.example`）。 |
| `Videocask/tool/bump_version.dart` | 一次性同步 `pubspec.yaml`、`lib/config/constants.dart`、`changelog.dart`、`CHANGELOG.md`、`README.md` 的版本号。 |

### 本地构建

```bash
cd Videocask
flutter pub get
flutter build apk --release --split-per-abi   # Android
flutter build windows --release               # Windows
flutter build web --release                   # Web
python tool/package_deliverables.py           # 汇总到 deliverables/
```

### 发布新版本

```bash
# 1) 升版本（三端一起交付时才做）
dart run tool/bump_version.dart --version 1.1.8

# 2) 打包并上传
python tool/publish_release.py --dry-run   # 预览
python tool/publish_release.py             # 正式发布（需要 GITHUB_TOKEN）
```

## 开发规范

- 技术说明：[`Videocask/docs/技术说明.md`](Videocask/docs/技术说明.md)
- 验证与用例清单：[`Videocask/docs/验证与用例清单.md`](Videocask/docs/验证与用例清单.md)
- 测试策略与覆盖报告：[`Videocask/docs/测试策略与覆盖报告.md`](Videocask/docs/测试策略与覆盖报告.md)
- 应用内更新与发版：[`Videocask/docs/应用内更新与发版.md`](Videocask/docs/应用内更新与发版.md)
