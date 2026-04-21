# 用户视角 QA 审查与修复记录

本文档对应一次「用户场景 + 健壮性」审查：**已修复项**见下文「修复说明」；**未改代码但需知悉的风险**见「残留风险」。

若与当前主分支行为不一致，**以代码与测试为准**；本文档不替代 `flutter test` / 代码审查。

---

## 1. 问题清单（原代码 / 设计上的问题）

### 1.1 已修复（本次提交）

| 编号 | 类型 | 描述 |
|------|------|------|
| R-01 | 逻辑 / 边界 | DeepLink / `toSearch` 用字符串拼接 query，`id` 或 `query` 含 `&`、`=`、`/` 等会破坏 URL 或丢参数。 |
| R-02 | 崩溃风险 | `await context.push` 后未判断 `context.mounted`，极端情况下后续若扩展代码可能用到已卸载的 `context`。 |
| R-03 | 崩溃风险 | `DetailCache.displayCachePanel` 使用 `Overlay.of(context)`，无 `Overlay` 时直接抛异常（测试/嵌套错误场景）。 |
| R-04 | 健壮性 | `TorrentSearchService.activeConfigs()` 解析 JSON 失败时 **空 catch**，用户侧表现为静默回退，排障困难。 |
| R-05 | 崩溃风险 | 字幕 SRT 时间轴用 `int.parse`，异常格式会 **FormatException** 导致整文件解析失败或向上冒泡。 |
| R-06 | 可维护性 | `TorrentPlayerService.dispose` 中对 `cancel()` **空 catch**，掩盖订阅清理失败。 |
| R-07 | 崩溃风险 | `ErrorHandler.showErrorDialog` 未判断 `context.mounted`，在页面已销毁时调用可能异常。 |

### 1.2 残留风险（建议后续迭代，本次未改行为）

| 编号 | 类型 | 描述 |
|------|------|------|
| P-01 | 安全 | WebDAV 密码参与本地加密与配置序列化；需确认落盘是否额外保护（系统钥匙串/Keystore 等）。当前为应用级风险，需产品决策。 |
| P-02 | 安全 | `AuthService` 中微信/QQ 为 **模拟 OpenID**；上线前必须替换真实 OAuth，否则账号体系不可信。 |
| P-03 | 安全 | `debugPrint` 日志勿输出 token/密码；当前以业务打印为主，新增日志时需代码审查。 |
| P-04 | 性能 | 首页/列表大页面若存在整页 `setState`，可能卡顿；需结合 DevTools 对热点路径做 `Selector`/`Consumer` 收窄。 |
| P-05 | 功能 | `DetailCache` 中加载/增删缓存多为占位逻辑，用户可见「成功」提示但与真实缓存列表可能不一致，需产品补齐。 |
| P-06 | 全局错误 | `PlatformDispatcher.instance.onError` 返回 `true` 会吞掉未捕获异步错误，避免崩溃但可能掩盖缺陷；建议保留日志/上报通道。 |

---

## 2. 修复说明（改了什么、为什么）

| 文件 | 改动摘要 | 原因 |
|------|-----------|------|
| `lib/config/routes.dart` | `handleDeepLink` / `toSearch` 使用 `Uri(path:, queryParameters:)` 构建路径；`push` 后 `if (!context.mounted) return` | 正确编码 query，避免特殊字符破坏路由；符合异步导航后 `BuildContext` 使用规范。 |
| `lib/pages/detail/detail_cache.dart` | `Overlay.maybeOf` + 空则 `debugPrint` 并取消插入 | 避免无 Overlay 时崩溃，失败可观测。 |
| `lib/services/torrent_search_service.dart` | 解析磁力源配置失败时 `debugPrint` + `assert` 打印 stack（仅 debug） | 保留回退内置源行为，同时可诊断坏数据。 |
| `lib/services/subtitle_service.dart` | SRT 时间字段改用 `int.tryParse`，非法块跳过 | 损坏字幕不再拖垮整段解析。 |
| `lib/services/torrent_player_service_io.dart` | `cancel` 的 catch 中 `debugPrint` | 清理失败可追踪，不改变释放主流程。 |
| `lib/services/error_handler.dart` | `showErrorDialog` 入口 `if (!context.mounted) return` | 避免在无效 context 上弹窗。 |
| `test/deeplink_uri_test.dart` | 新增 URI 编码单元测试 | 防止回归为字符串拼接 query。 |

**功能保持**：路由目标、搜索空关键词、磁力源解析失败时仍回退内置默认、字幕仍跳过坏块仅影响对应条目，整体行为与产品预期一致。

---

## 3. 用户角度测试用例（3 条）

### 用例 A：搜索关键词含特殊字符（DeepLink / 跳转搜索）

1. 在可触发 `AppRoutes.toSearch` 的入口（或将来接好 DeepLink 后）使用关键词：`三体 & 合集` 或含 `&`、`=` 的字符串。  
2. **期望**：进入搜索页且关键词完整，不出现截断或空白结果 solely 因 URL 被截断。  
3. **关联修复**：R-01（`Uri` queryParameters）。

### 用例 B：详情页打开缓存面板（Overlay 缺失场景）

1. 在正常详情页（带 `Overlay`）打开缓存相关 UI，应仍能显示面板。  
2. 若将来在测试环境或无 `MaterialApp`/`Overlay` 的子树错误调用 `displayCachePanel`，**期望**：不崩溃，控制台有明确日志。  
3. **关联修复**：R-03。

### 用例 C：损坏的 SRT 字幕文件

1. 准备一份时间轴某行被改坏的 `.srt`（非数字或格式错乱）。  
2. 加载该字幕。  
3. **期望**：应用不崩溃；合法时间轴条目仍可显示，坏行被跳过。  
4. **关联修复**：R-05。

---

## 4. 建议的回归命令

```bash
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test tool
```

（与 `docs/code_standards.md` / CI 一致。）
