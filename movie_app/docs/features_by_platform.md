# 功能划分（通用 / 各端）与优化建议

本文档描述 **movie_app** 当前能力在 **通用（各端共用）** 与 **各端独立（实现或限制不同）** 上的划分，并给出优化方向。

**产品决策（已落实于代码）**

- **全端不提供「发现」模块**：已移除原 `DiscoverPage`、移动端底栏「发现」入口、首页 AppBar 的「发现」图标；观影统计空态中的「去发现」改为 **「去搜索」**（`AppRoutes.toSearch`）。
- 浏览与筛选以 **首页分区 + 分类/地区筛选 + 搜索** 为主路径。

---

## 一、通用功能

以下能力在 **Android、iOS、Web、桌面** 上均通过同一套路由与主体代码提供（个别能力在 Web 等端会因平台限制表现为占位或降级，但仍属「同一产品功能」）。

### 1.1 导航与壳

| 功能 | 说明 |
|------|------|
| `GoRouter` 路由 | 首页、搜索、详情、源管理、缓存管理、设置、我的、登录、排行榜、观影统计、播放列表/详情、追剧、设计对照页等 |
| `AppRoutes` | 统一 `push`/`go` 与详情 `extra`（如 `Movie`、`initialMagnetUri`） |
| 路由错误页 | 未知路径提示与回首页 |

### 1.2 内容与业务

| 功能 | 说明 |
|------|------|
| 首页 | 轮播、分区、分类/地区筛选、下拉刷新、高分区无限加载、视图密度、回顶、骨架屏/错误态、源切换联动等 |
| 搜索 | 关键词搜索、结果进详情 |
| 详情 | 拉取详情、切源、`MovieProvider`、播放（非 Web）、磁力检索与结果、相关推荐、历史与进度持久化、迷你播放器状态等 |
| 追剧 | 收藏 / 观看历史 / 缓存 Tab |
| 我的 | 登录态、快捷入口、数据统计、账号与设置入口 |
| 排行榜 | 榜单与进详情 |
| 播放列表 | 列表与详情、本地存储 |
| 观影统计 | 总览、类型分布、活跃度、TOP5 |
| 登录 / 游客 | `UserProvider`、`AuthService` |
| 播放源管理 | 多源、当前源、与首页联动 |
| 设置 | 播放参数、OpenSubtitles、数据导出/导入、磁力搜索源配置、WebDAV、主题、关于与开源许可 |

### 1.3 数据、网络与基础设施

| 功能 | 说明 |
|------|------|
| `StorageService`（Hive） | 历史、收藏、设置、源、用户、播放列表等；导出/导入 JSON |
| `ApiService` / `SearchService` | CMS 与搜索 |
| `SyncService` / `WebDavService` | 与设置中 WebDAV 同步项配合 |
| `TorrentSearchService`、磁力详情与播放相关服务 | 聚合检索；IO 与 Web 实现层次不同但产品能力同属「磁力」 |
| `SubtitleService`、DLNA、`VideoParser`、`ImdbLookupService` 等 | 按场景在详情等处调用 |
| `ThemeProvider`、`SettingsProvider`、各业务 `Provider` | 全局状态 |
| `ErrorHandler`、`DioFactory` | 错误与网络 |
| 国际化 | `AppLocalizations` + ARB（中英） |
| 详情设计对照 | `AndroidIntroDesignV3Page` 路由（规格见 `detail_page_spec.md`） |

### 1.4 通用优化建议

1. **平台差异显性化**：同一功能在 Web（如无硬解播放）、桌面（键盘快捷键）上的表现不同，建议在设置或关于中维护 **能力矩阵**，避免用户认为「功能损坏」。
2. **文案与规范**：首页、统计等仍有硬编码中文，建议按页面迁移至 ARB，与仓库规范一致。
3. **去掉死代码与双轨**：如详情内 `_loadRecommendations()` 空实现、独立 `PlayerPage` 与详情播放器并存等，应合并或删除以降低维护成本。
4. **详情 UI 对齐**：以 `docs/detail_page_spec.md` 与静态设计页为基准，统一窄屏与宽屏信息架构（Tab、主操作、折叠简介等）。
5. **导入导出**：JSON 带 **schema 版本号**，便于后续字段演进与迁移。

---

## 二、各端独立功能（或该端显著不同）

### 2.1 Android / iOS（移动）

| 功能 | 说明 |
|------|------|
| 底部导航 | **首页 / 追剧 / 我的** 三栏（已无「发现」） |
| 迷你播放器条 | 叠在底栏上方，与 `PlayerProvider` 联动 |
| `SystemChrome` | 竖屏偏好、状态栏样式等 |
| 系统返回与安全区 | 与 `Scaffold`、`MediaQuery` 典型移动布局配合 |
| 存储与权限 | 下载/缓存等与 `permission_handler`、路径策略相关（随实现演进） |

**优化建议：** 迷你条与底栏、Home Indicator 叠层做 **真机安全区** 测试；权限流程与缓存操作 **先授权再执行**。

### 2.2 Web

| 功能 | 说明 |
|------|------|
| 无主壳底栏 | `MainPage` 直接展示 `HomePage` + 迷你条（逻辑存在时） |
| 无 `MediaKit` 初始化 | `main` 中不调用 `MediaKit.ensureInitialized()` |
| 缓存服务 | 应用初始化中跳过 `CacheService.init()` |
| 详情播放占位 | 不支持原生播放器时的提示 UI |
| 详情宽屏分栏 | 浏览器宽度 ≥ 断点时与 Windows 宽屏同构：右栏顶「选集 / 播放线路」，下「磁力 / 推荐」 |
| `web/index.html` | `corsFetch` 等脚本，辅助跨域请求 |
| 磁力播放等 | `torrent_player_service_stub`，无 FFI |

**优化建议：** Web 能力单独写 **用户可见说明**；CORS 代理建议可配置、可关闭、失败降级；注意隐私与可用性。

### 2.3 Windows（桌面，代码级差异）

| 功能 | 说明 |
|------|------|
| `window_manager` | 启动显示与聚焦 |
| 详情宽屏分栏 | 条件：**桌面三平台**且宽度 ≥ 断点（与 Web 宽屏同构）；左播放器+信息，右栏顶「选集/播放线路」Tab，下「磁力/推荐」 |
| 窗口全屏、键盘快捷键 | 详情播放器内与桌面环境绑定 |

**优化建议：** Linux/macOS 已与 Windows 共用详情分栏断点；桌面 **argv DeepLink** 见 `docs/deeplink.md`（协议注册仍可补）。

### 2.4 Linux / macOS（桌面）

| 功能 | 说明 |
|------|------|
| 与 Windows 共享 | `window_manager`、键盘、全屏等 |
| 详情宽屏分栏 | 与 Windows 相同：宽度 ≥ 断点即分栏（见 2.3 与 `DetailPage`）。 |
| 高保真顶栏壳 | 与 Web 一致：窗口逻辑宽度 ≥ `HiFiDesignTokens.desktopChannelNavMinWidth` 时，首页 / 频道页使用 `useWideTopBarShell`（品牌 + 频道行 + 嵌入式搜索 + 右侧图标），不限于 Web |

**优化建议：** 与 2.3 合并治理 **桌面一致布局策略**（详情分栏已与顶栏壳同为三桌面 + 断点）。

### 2.5 各端独立能力优化建议（汇总）

| 维度 | 建议 |
|------|------|
| 导航 | Web/桌面无底栏时，确保 **追剧、我的、搜索、设置** 等在首页 AppBar 或等价入口 **始终可达**（与移动三栏信息等价）。 |
| 播放 | Web 与 IO 分开验收；IO 端统一播放器入口，减少双实现。 |
| 详情 | 分栏已推广到 **Windows / Linux / macOS** 宽窗口；若行为回退，以 `DetailPage` 断点逻辑为准。 |
| 高保真顶栏 | 首页与 `CategoryPortalPage` 的宽屏顶栏条件为 **Web 或桌面三平台** + 宽度断点（见 `HiFiDesignTokens.useWideTopBarShell`）。 |

---

## 三、全局优化建议（跨通用与各端）

1. 维护 **功能 × 端** 矩阵表，新功能先标注「通用 / 某端限定」，避免再次出现已下线模块的残留入口。  
2. 详情与静态设计 **共用组件与 Design Tokens**，减少视觉漂移。  
3. 关键路径 **测试覆盖**：搜索、详情路由 extra、存储导出导入、Web 降级路径。  
4. **数据与隐私**：WebDAV 凭据、导出文件是否加密、磁力与合规说明按需补充。

---

## 四、修订记录

| 日期 | 说明 |
|------|------|
| 初版 | 通用 / 各端划分 + 优化建议；明确全端下线「发现」并指向当前代码行为。 |
| 静态验收 | 一屏总览线框见 `docs/static-gallery/review-full.html`（本地 HTTP 打开，见该目录 `README.md`）。 |
| 详情宽屏 IA | Web / Windows 宽屏分栏一致；右栏顶「选集/播放线路」Tab，下「磁力/推荐」。 |
| 2026-04-19 | 高保真顶栏壳：Linux/macOS/Windows 在宽度断点下与 Web 同构（`useWideTopBarShell`）；与仅 Windows 详情分栏策略区分。 |
| 2026-04-19 | 详情宽屏分栏与 Web 对齐至 **三桌面**；argv DeepLink 与 `deeplink.md` 更新。 |

