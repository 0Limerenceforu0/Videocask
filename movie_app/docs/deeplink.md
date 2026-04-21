# DeepLink（深度链接）

## 当前状态

- **已实现（桌面 exe 启动参数）**：`main` 在 `runApp` 前调用 `PendingDeepLink.registerFromArguments(Platform.executableArguments)`，扫描 `movieapp://…`；`MaterialApp.router` 的 `builder` 包一层 `MaterialAppDeepLinkChild`（`lib/widgets/material_app_deep_link_child.dart`），首帧后调用 **`AppRoutes.handleDeepLink`**。`movieapp://detail?id=…` 等会经 **`_normalizeIncomingDeepLink`**（`routes.dart`）将 **host** 映射为 path（如 `host=detail` → `/detail`）。
- **`AppRoutes.handleDeepLink`**（`lib/config/routes.dart`）：`detail` / `search` / `follow` / `home` 等路径仍为此方法的唯一解析实现。
- **已实现（Android / iOS）**：依赖 **`app_links`** 的 [DeepLinkStreamService](../lib/services/deep_link_stream_service.dart) 在应用初始化完成后注册；冷启动 `getInitialLink` 与前台 `uriLinkStream` 均调用 **`AppRoutes.handleDeepLinkForRouter`**（与 `MaterialAppDeepLinkChild` 消费的 argv 方案一致）。`AndroidManifest.xml` 已为 `movieapp://` 配置 `VIEW` intent-filter。
- **仍依赖环境/安装程序**：Windows **从浏览器点链拉起 exe** 须在系统层注册 `movieapp` 协议（安装器或文档约定），否则仍仅有 argv 解析；iOS **Runner 工程**若未纳入仓库，需在 Xcode 配置 URL Types 后 `app_links` 方能在真机生效。
- 桌面端窗口显示逻辑在 `_prepareDesktopWindow()` 中，与 DeepLink 无关。

## 推荐实现路径

1. **移动端（Android / iOS）**  
   使用 [`app_links`](https://pub.dev/packages/app_links) 或 `uni_links`，在收到 URI 后调用 `GoRouter.go` / `push`，与 `lib/config/routes.dart` 中的路径对齐。

2. **Windows**  
   已实现从 **`Platform.executableArguments`** 解析 `movieapp://…`；若需「浏览器点链打开 exe」，仍须 **协议注册**（安装器或文档约定），使系统把 URI 传入 argv。

3. **与路由的对应关系（示例）**  
   - `movieapp://detail?id=123&sourceId=abc` → 详情页  
   - `movieapp://search?query=…` → 搜索  
   - `movieapp://home` → 首页  

4. **测试**  
   解析与跳转建议单独写单元测试或集成测试，避免仅在 `main` 中堆逻辑。
