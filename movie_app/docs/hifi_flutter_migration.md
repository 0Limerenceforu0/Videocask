# 高保真宽屏静态稿 → Flutter UI 迁移清单与分步说明

本文档说明：**如何把 `docs/static-gallery` 中高保真宽屏稿（`hifi-*`）落实为 Flutter 真实界面**，并尽量保证**功能不缺失**。静态 HTML/CSS/JS 是**视觉与信息架构基准**，不是可嵌入的运行时代码；实现必须在 Dart 中重做布局与交互，并接现有 `GoRouter`、`Provider`、`ApiService` 等。

## 0. 先读这些（避免与已有决策冲突）

| 文档 | 用途 |
|------|------|
| [features_by_platform.md](features_by_platform.md) | 各端能力、Web 无底栏、详情宽屏分栏、须保留的入口 |
| [detail_page_spec.md](detail_page_spec.md) | 详情页信息架构与宽屏分栏 |
| [static-gallery/README.md](static-gallery/README.md) | 高保真本地预览方式、静态稿定位 |
| [code_standards.md](code_standards.md) | 文案走 l10n、`context.mounted` 等工程规范 |

本地对照高保真：在 `docs/static-gallery` 执行 `python -m http.server 8765`，打开 [hifi-index.html](static-gallery/hifi-index.html) 中的各宽屏入口。

### 已落实（仓库状态快照）

以下与静态稿第三步、第四步（宽屏首页主体）、第五步及搜索宽屏壳对齐；频道内子类 chip 与 CMS 子类一一对应仍可随产品细化。

| 项 | 说明 |
|----|------|
| Design Token 文件 | `lib/theme/hifi_design_tokens.dart`（强调色 `#00AEEC`、`shellMaxWidth`、Web 顶栏断点 `900`） |
| 频道枚举与路径 | `lib/config/channel_portal_kind.dart` → `/movies`、`/tv`、`/variety`、`/anime`、`/short` |
| 频道页（首版布局） | `CategoryPortalPage` + `category_portal_side_rank.dart` + `widgets/category_portal_module_row.dart`；`lib/config/channel_portal_module_catalog.dart`：**三模块各走一次**请求（首模块 `genre` 随筛选，2/3 模块为频道固定类型）；首屏在**多源已启用**时与首页一致走 `ApiService.aggregateCategoryFirstPage`，否则 `getMoviesByCategory`；首模块触底分页仍用主源 `getMoviesByCategory`；模块标题行 **「更多」** → `AppRoutes.toHomeWithCategory`（与 `ChannelPortalKind.homeBrowseCategoryName` 对齐）或短剧频道仅 `toHome` |
| 路由注册 | `lib/config/routes.dart`：由 `ChannelPortalKind.values` 展开 `GoRoute`；`AppRoutes.toChannelPortal(context, kind)` |
| 宽屏顶栏（Web 或桌面 OS） | `HiFiDesignTokens.useWideTopBarShell`：`HiFiChannelNavRow` + `HiFiDesktopSearchBar` + `HiFiDesktopToolbar.trailingActions`（`includeSearchIcon: false` 时与嵌入式搜索不重复）；首页 `SliverAppBar` 与 `CategoryPortalPage` 的 `AppBar` 共用 |
| 首页 → 频道 | 分类 Tab（电影/剧集/综艺/动漫）筛选区上方 **「宽屏频道页」** 按钮，与对应 `ChannelPortalKind` 对齐；纪录片暂无映射 |
| 宽屏首页主体 | `useWideTopBarShell` 时推荐态为 **轮播限宽 + 继续观看 + `HiFiHomeWidePortalModules`**（各频道 `CategoryPortalModuleRow`：左 5×2 + 右榜 + 子类 chip）；窄屏仍为原分区与分类 Tab |
| 搜索宽屏 | `SearchPage`：`hifi-screen-search-windows.html` 式顶栏 + 限宽内容区；说明文案 `searchWideAggregateHint` |
| 追剧宽屏 | `FollowPage` 主体包 **`HiFiWideConstrainedBody`**（`shellMaxWidth`） |
| 深度链接（移动） | `app_links` + `DeepLinkStreamService`；`AppRoutes.handleDeepLinkForRouter` |
| 文案 | `app_zh.arb` / `app_en.arb`：`navChannel*`、`filterLabel*`、`toolbar*`（含 `toolbarSearchPlaceholderHome`、`toolbarSearchPlaceholderInChannel`）、`categoryPortalModuleTagged`、`categoryPortalModuleEmpty`、`categoryPortalScrollForMore`、`categoryPortalHotRankTitle`、`homeOpenDedicatedChannel*`、`homeEndOfListHint` 等；已执行 `flutter gen-l10n` |

---

## 1. 静态稿 ↔ Flutter 对照清单（按页面）

| 高保真入口（宽屏） | Flutter 现状 / 目标 | 功能与数据注意 |
|-------------------|---------------------|----------------|
| `hifi-screen-home-windows.html` | `MainPage`（Web 无底栏）+ `HomePage` | 轮播、继续观看、分区模块、刷新、骨架屏/错误态、进详情；顶栏须能到搜索/追剧/我的/设置 |
| `hifi-screen-category-*-windows.html`（电影/连续剧/综艺/动漫/短剧） | **`CategoryPortalPage`**：纵向 **多模块**（`CategoryPortalModuleRow`，每块 ≤10 条 + 右榜）+ 全宽筛选；子类标题与静态「最新/动作…」一一对应待产品配置 | 与 `MovieProvider`/API 的筛选、分页对齐；短剧依赖 CMS 是否提供「短剧」类型 |
| `hifi-screen-search-windows.html` | `SearchPage`（`/search`） | 关键词、`AppRoutes`、结果进详情 |
| `hifi-screen-detail-windows.html` | `DetailPage`（`/detail`） | Web 播放占位、桌面/Web 宽屏分栏见 `features_by_platform` |
| `hifi-screen-follow-windows.html` | `FollowPage`（`/follow`） | 收藏/历史/缓存 Tab 与现有逻辑一致 |
| `hifi-screen-profile-windows.html` / `hifi-screen-settings-windows.html` | `ProfilePage`、`SettingsPage` 及子能力 | 登录、统计入口、设置项不删 |
| `hifi-screen-ranking`（若有）或索引中的榜单 | `RankingPage`（`/ranking`） | 数据源与首页侧栏「热播」是否同源需产品约定 |
| 静态 `hifi-common.js`（sessionStorage 等） | **不迁移** | 全部改为 `Provider` + 路由 + 真实 API |

**移动端**：以 `hifi-screen-home-mobile.html` 等为对照，**不要**把宽屏栅格硬套到小屏；`MainPage` 底部三栏（首页/追剧/我的）须保留。

---

## 2. Design Token 清单（从 CSS 抽到 Flutter）

**进展**：已新增 `lib/theme/hifi_design_tokens.dart`，可按需再并入 `ThemeData` / `ThemeExtension`。

建议在 `lib/theme/`（或现有主题文件）集中定义，与高保真变量对齐，例如：

- 强调色 `#00AEEC` → `ColorScheme.primary` 或扩展 `extension` 常量
- 背景/卡片/边框 → `surface`、`surfaceContainerHighest`、分割线透明度（对照 `hifi-common.css` 中 `--card`、`--sub` 等）
- 顶栏高度、圆角（如 12/20px）、模块间距（对照 `hifi-kp-windows.css`）
- 宽屏最大内容宽（如静态稿约 1160px）→ `Center` + `ConstrainedBox(maxWidth: …)`

验收：深色主题下图四顶栏、模块卡片、侧栏榜与浏览器中打开静态稿**肉眼一致**（允许字体因系统略有差异）。

---

## 3. 分步更新（推荐顺序）

按顺序做，**每步结束**都能 `flutter analyze` + 手动点一遍关键路径，再进入下一步。

### 第一步：只加文档与分支策略（本步已完成文档；你可建 Git 分支）

- 从本文档拆出你负责的「阶段」到 issue/看板；建议单独分支 `feature/hifi-desktop-shell`。

### 第二步：Theme / Token（不改布局或仅改颜色）

1. 从 `docs/static-gallery/hifi-common.css`、`hifi-kp-windows.css` 提取颜色与圆角。
2. 在 `ThemeData` / `ColorScheme.fromSeed` 或自定义 `ThemeExtension` 中落地。
3. 跑 `flutter analyze`；在 Chrome + Windows 各看一眼首页/详情是否仍可读。

### 第三步：Web/桌面「顶栏壳」（对齐 `hifi-kp-topbar`）

1. 条件为 [HiFiDesignTokens.useWideTopBarShell]（**Web 或 Windows / Linux / macOS** 且宽度 ≥ `desktopChannelNavMinWidth`）：`HomePage` 顶栏为左（品牌 + 频道导航）、中（嵌入式搜索）、右（`HiFiDesktopToolbar` 图标），链接目标对齐静态稿（`toSearch`、`toFollow`、`toProfile`、`toSettings` 等）。
2. 频道「电影/连续剧…」：`context.push('/movies')` 一类路由（路径在下一步实现）或暂时 `push` 到首页并带 `queryParameters`（过渡方案需在文档注明）。
3. 对照 [features_by_platform.md](features_by_platform.md)：**Web 无底栏时，追剧/我的/搜索/设置必须始终可达**。

验收：不打开详情，仅在首页与顶栏能完成搜索、进追剧、进设置、回首页。

### 第四步：首页主体布局（对齐 `hifi-screen-home-windows.html` 模块）

1. 继续观看、轮播：保留现有数据与刷新逻辑，只改外层 `Column`/`CustomScrollView` 与栅格。
2. 各分区（电影/剧/综艺/动漫/短剧）：**左 5×2 片卡 + 右侧热播榜**；榜数据来自现有 API 或占位与后续接口一致。
3. 「更多」进对应频道路由（见第五步）。

验收：下拉刷新、错误重试、无限加载（若有）仍工作；点击进入 `/detail` 正常。

### 第五步：频道独立页（对齐 `hifi-screen-category-*-windows.html`）

1. 在 [lib/config/routes.dart](../lib/config/routes.dart) 已增加 `/movies`、`/tv`、`/variety`、`/anime`、`/short`（见 `ChannelPortalKind`）；占位页已可导航。
2. 纵向三模块已接 **独立 `genre` 请求**（见 `ChannelPortalModuleCatalog`）；首屏多源聚合已与首页 `loadCategoryMovies` 对齐；模块标题行「更多」已接首页 `?category=` 导航。
3. 顶栏与首页共用同一套壳组件，避免复制粘贴。

验收：从首页顶栏与首页模块「更多」均可进入各频道；返回首页无栈异常。

### 第六步：搜索 / 详情 / 追剧 / 个人与设置

1. 搜索页宽屏排版对齐 `hifi-screen-search-windows.html`；逻辑仍用 `SearchPage`。
2. 详情对齐 `hifi-screen-detail-windows.html` 与 [detail_page_spec.md](detail_page_spec.md)；宽屏分栏条件与现有一致（勿只改 Windows 而破坏 Web）。
3. 追剧、我的、设置：对齐对应 `hifi-screen-*`，以**不删字段、不删路由**为前提做皮肤与排版。

验收：走一遍 `features_by_platform` 中「通用功能」表格里的链接型能力。

### 第七步：移动端与无障碍

1. 小屏仍用底部 `NavigationBar`（`MainPage`）；首页用移动高保真或现有移动布局，不与宽屏强绑。
2. 顶栏图标、`Semantics`、`tooltip` 与读屏文案按仓库规范补齐。

验收：真机或模拟器上三栏切换 + 迷你播放条（若有）无遮挡。

### 第八步：文案国际化与收尾

1. 新增用户可见字符串写入 `app_zh.arb` / `app_en.arb`，执行 `flutter gen-l10n`。
2. `dart format`、`flutter analyze`、`flutter test` 全绿后合并。

---

## 4. 每步通用自检（防功能回归）

- [ ] `flutter analyze` 无问题  
- [ ] `flutter test` 通过（若有首页/路由相关测试则更新）  
- [ ] **路由**：`/`、`/search`、`/detail`、`/follow`、`/profile`、`/settings`、`/ranking`、源管理、缓存、播放列表、统计、登录  
- [ ] **Web**：无播放器降级提示仍可出现；CORS/搜索仍可用  
- [ ] **桌面**：窗口缩放至断点以下时布局不崩  
- [ ] **文案**：无新增硬编码中文（除调试日志规范允许的）  

---

## 5. 修订记录

| 日期 | 说明 |
|------|------|
| 初版 | 高保真 → Flutter 对照表 + 分步顺序 + 回归项 |
| 2026-04-19 | `ChannelPortalKind`、`CategoryPortalPage`（`CategoryPortalModuleRow` + `ChannelPortalModuleCatalog` + `CategoryGenreRegionFilterBand`）、`HiFiChannelNavRow`、`HiFiDesktopToolbar`、Token；首页「宽屏频道页」入口；`filterLabel*`、模块标题与顶栏 `toolbar*` 走 l10n |
| 2026-04-19 | 频道页各模块首屏：`SourceProvider.enabledSources` 多于 1 个时 `aggregateCategoryFirstPage`，与首页分类多源合并一致 |
| 2026-04-19 | Web 宽屏顶栏中间嵌入式 `HiFiDesktopSearchBar`；`toolbarSearchPlaceholder*`；窄屏仍保留搜索图标按钮 |
| 2026-04-19 | `useWideTopBarShell`：Windows/Linux/macOS 宽窗口与 Web 同构顶栏；频道模块「更多」+ `toHomeWithCategory` / 首页消费 `?category=`；`categoryPortalModuleMore*` |
| 2026-04-19 | 详情宽屏分栏推广至 Linux/macOS；桌面 argv `movieapp://` + `MaterialAppDeepLinkChild`；`HiFiUiTokens` `ThemeExtension`；启动屏与首页部分文案 l10n |

后续若频道路径、榜单数据源已定稿，请在本表「对照清单」与「已落实」中更新具体 `GoRoute` 路径与页面类名。
