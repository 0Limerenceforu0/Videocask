# 罐子 版本变更记录

> 版本号规则（2026-10-22 用户定，**当日再次纠正**）：
> **只有「Android + Windows + Web 三端一次性全部打包交付给用户」时才升版本号。**
> 代码改动、跑 analyze / 单测、单端构建都**不升**；代码可以先落地，版本号随交付动作推进。
> 升时同步四处：pubspec `version` + `constants.appVersion` + 应用内更新日志
> （`lib/config/changelog.dart`）+ 本文件。默认升「第二位数」（如 1.0.50 → 1.0.51）；
> 升「第一位数」（如 1.0 → 1.1）需用户特别指示。
> ⚠️ 早期本文件写的「打包一次升一次」是错的，指的是「全部打包给我」的交付动作，
> 不是任意一次打包。

## 1.1.10 (2026-11-12)

> 本次为 Android + Windows + Web 三端一次性交付，版本 `1.1.10+70`。
> 1.1.9 已发布过一轮（Windows 端已单独替换过资产），本次是把进度条交互与
> Windows 磁力原生修复带到三端，并整体重打。

### 全端进度条交互

- 进度条统一支持「悬停 / 按住预览」：鼠标悬停即刻显示所指位置的时间气泡；
  按住（触摸为长按）只移动气泡、不触发跳转；按住滑动时气泡时间随指针/手指实时更新；
  松手才真正 seek；指针滑出进度条或手势被系统取消时放弃本次跳转并清理气泡，
  不会误跳到别的位置。
- 拖动过程中的快速 seek 只走节流回调做预览，真正的 `commitSeek` 只发生在松手，
  避免拖动途中反复 seek 造成的卡顿与进度回弹。

### Windows 磁力播放

- 重新编译 Windows 原生播放桥（`libtorrent_flutter.dll`），去掉上游默认的
  `stop_when_ready` 行为：此前元数据/预取窗口满后 torrent 会进入 `finished` 状态并
  `announce stopped`，随后被移除，表现为「播着播着不再下载、拖进度条不动、换集失效」。
  重建后供数在播放全程持续，`readHead` 与 `done` 正常推进。
- 修复 Windows 启动时 `LibtorrentFlutter.init()` 因预编译 DLL 缺少 `lt_set_log_path`
  导出而直接失败（磁力引擎永远起不来、界面无限重试）。新增
  `tool/patch_libtorrent_optional_logpath.py`，在构建前幂等地把该符号降级为可选。
- 桌面端深链修复：`main()` 改为接收命令行参数（`main([List<String> args])`），
  Windows 下 `罐子.exe "magnet:?xt=..."` 可一键起播；此前误读
  `Platform.executableArguments`（只有 VM 参数），深链从未生效。
- 磁力起播交接判据修正：改为 `buffer / downloadSpeed / nativeDownloadRate /
  downloadedBytes` 全为 0 才判定「零数据」，避免把健康下载（1MB/s）误杀后删种重启。

### 应用内更新

- 下载改为系统通知式后台下载（单例 `UpdateDownloadManager`）：更新弹窗可关闭而下载继续，
  通知栏显示进度，点通知直接回到安装页。
- 安装前增加版本校验（原生 `verifyUpdateInstall` + Dart `downgradeBlocked`）：
  已装版本高于新包时明确提示「请先卸载旧版本（含测试包）」，不再含糊报「已存在更高版本」。

### 更新提醒与下载位置（2026-11-13 同版本重发）

> 本次不升版本号，仍为 `1.1.10`，重新打包并覆盖同版本 Release 资产。
> 影视（磁力）下载功能保持原有行为，未做改动。

- 新版本发布提醒改为「同一版本只提醒一次」：弹窗展示前就记录该版本，之后无论点
  「稍后」、关闭按钮、右上角 ×、按 Esc 还是直接杀进程，下次启动都不会被同一版本
  反复打扰；下一个新版本发布时仍会提醒一次。强制更新不受此限制。
- 更新弹窗下载中的按钮语义收敛：Android 只保留「关闭」（下载在后台继续），
  「取消下载」移到系统通知栏；桌面端没有下载通知，仍保留「取消下载 + 关闭」两个按钮。
- 设置页新增「下载位置」：Windows / 桌面可自行选择目录，Android 固定保存到公共
  `Download/罐子`，Web 由浏览器决定。
- 更新安装包下载完成后会另存一份到公共 `Download/罐子`，文件管理器可直接找到并点开安装，
  **卸载应用后安装包依然保留**。

## 1.1.9 (2026-11-11)

> 本次为 Android + Windows + Web 三端一次性交付，版本 `1.1.9+69`。
> 相对 1.1.8 的全部改动如下。

### 字幕观感

- 软字幕（在线匹配 SRT、外挂 SRT、内封文本轨、本地离线生成）默认改为「片源同款」：
  白字、细黑边、无阴影、字高与烧录进帧的硬字幕一致（`sub-scale` 由 1.4 回到 mpv 出厂 1.0），
  消除「外挂字幕一眼假」的观感；另提供「放大易读」可选档（字更大、描边更粗、带阴影）。
- AI 字幕面板按平台真实能力显示：移动端缺 ffmpeg 抽音（ffmpeg-kit 未接入）、
  Web 缺 transformers.js 桥接时明确提示不可用，不再承诺「下载模型后自动生成」。

### UI 与播放稳定性

- 底部弹窗统一收口（`app_bottom_sheet.dart`）：`isScrollControlled` + 最大高度约束 +
  `SingleChildScrollView` + `SafeArea`，修复内容被屏幕底边裁掉、最后一项点不到的问题
  （字幕面板的「字幕延时」整行此前根本没渲染出来）。
- 磁力拖进度条后的加载提示改为「按出画证据」收尾（`magnet_seek_visual_policy.dart`）：
  只看位置真的越过目标、或 mpv 结束 seek 且附近有可立即播放的缓存；不再把「进度权威落位」
  误当「画面就绪」提前撤掉提示。卡 45 秒仍不出画时保留浮层并把文案升级为「仍在尝试」，
  而非静默撤掉（修复用户反馈的「加载没了、画面还没出来」）。
- 磁力弱 swarm 止损（`magnet_weak_swarm_policy.dart`）：在连 peer < 2 且下行 < 120KB/s
  持续 18 秒即判定 swarm 没货，提前中止本次起流；同一资源连续 2 次弱 swarm 彻底放弃，
  明确提示「资源做种太少」，不再把 900MB 的期待耗在 1 个 peer 上（旧逻辑空等约 8 分钟）。

### 磁力详情与数据

- 磁力详情中文信息补全；豆瓣查询改用英文名更准确（`douban_lookup_service.dart`），
  避免年份/片名错配，新增对应单测。
- 死代码清理与若干播放/字幕/播放列表细节修正。

### 应用内更新改进

- 后台下载升级为「系统通知式」：点「下载并更新」后即可关闭弹窗，下载在后台继续，
  并在系统通知栏显示带进度条的实时进度；切到别的 App 也能看到，点通知可回到安装页。
- 安装前新增「降级拦截」：若设备上已装版本的 versionCode 高于新包
  （常见于残留了更高版本号的测试包），会明确提示「请先卸载旧版本」，
  而非抛出含糊的「已存在更高版本」系统错误。

### Windows 磁力播放修复

- 修复 Windows 端磁力资源完全无法播放的问题：点击磁力后界面停在
  「正在自动重试第 N 次 · 启动 P2P 引擎」并无限重试。
  根因是 `libtorrent_flutter` 1.9.9 随包发布的 Windows 预编译 DLL
  （`prebuilt/windows/x64/libtorrent_flutter.dll`）比其 Dart 绑定落后一个提交，
  **未导出 `lt_set_log_path`**；而 Dart 侧在 `TorrentBridgeBindings` 构造函数里
  急切 lookup 该符号，导致 `LibtorrentFlutter.init()` 直接抛
  `Failed to lookup symbol 'lt_set_log_path'`，引擎永远初始化不起来。
- 修法（纯 Dart、不动原生库）：用 `tool/patch_libtorrent_optional_logpath.py`
  把该符号降级为「可选」——找不到时返回 null，`setNativeLogPath` 变为 no-op。
  Android 的 `.so` 由源码重建、含该符号，行为不变。日志已验证
  「P2P 引擎初始化成功」并可正常拉取 tracker。
- 恢复 Windows 可执行文件名称为「罐子.exe」：此前修复构建改走了
  `tool/build_windows_clean.py`，该链路缺少文件级改名步骤，产物退回了内部
  工程名 `movie_app.exe`。现已在构建成功后自动改名；应用内更新也兼容
  「旧包 `movie_app.exe` → 新包 `罐子.exe`」的迁移（覆盖成功后清理旧 exe），
  老用户无需手动重装。

### Windows 磁力播放稳定性（2026-11-12 补充修复，版本号不变）

- 桌面启动参数深链失效：`main.dart` 原来从 `Platform.executableArguments` 读启动参数，
  但 Flutter 桌面该值只含 Dart VM 参数，导致 `罐子.exe "magnet:?xt=…"` 从未生效
  （`DeepLinkStreamService` 又只在 Android/iOS 启用）。现改为 `main([List<String> args])`
  接收入口参数，桌面可用命令行/快捷方式一键打开磁力并自动起播，同时让全流程自动化回归成为可能。
- 修复「起流后零数据」误判：`StreamInfo.bufferPct` 是原生预缓冲比例，Windows 上可能恒为
  0%，而此时 `totalDone` 已有数 MB、差分速度 1MB/s。旧判据只看 `bufferPct <= 0`
  就删种子冷重启，把健康的下载白扔一轮（本机 exe A/B 实测 Big Buck Bunny 第 1 轮因此重来，
  第 2 轮才出画）。现要求 buffer / 差分速度 / 原生速率 / 已下载字节**全部为零**才判失败。
- 修复种子数据目录清理：Windows 上 `deleteSync(recursive: true)` 常因流文件句柄未释放报
  `errno=145 目录不是空的`，旧实现直接忽略导致残缺 piece 残留、下一轮 recheck 污染。
  现改为重试 4 次 + 逐文件删除兜底 + 等待句柄释放。

### 全端进度条交互（2026-11-12 补充，版本号不变）

- 进度条（Android / Windows / Web 共用同一份 `_buildProgressBar()`）新增鼠标/指针交互：
  - **悬停预览**：鼠标移到进度条上即显示「所指位置的时间」气泡，不移动播放头、绝不 seek。
  - **按下 / 长按只预览不跳转**：按下后只更新气泡与时间，画面保持原位置；便于「按住后滑动确认位置再跳转」。
  - **长按滑动实时预览**：按住并拖动时气泡实时显示「滑到的时间」。
  - **松手才跳转**：手指/指针松开时才提交 seek（取松开瞬间的位置，可能已滑动到别处）；
    手势被系统取消（来电 / 多指 / 滑出）则撤销预览、不跳转。
  - 实现要点：`Listener` 的 `onPointerHover/Down/Move/Up/Cancel` 分别驱动
    `hoverPreview / beginScrub / scrubPreview / endScrub / cancelScrub`；
    拖动期间只走 `_scrubFastSeekThrottled`（仅存目标、节流回调不调用 seek），
    真正 seek 仅在 `endScrub → commitSeek` 发生。气泡用 `ValueListenableBuilder`
    局部重建，避免每 hover 整页 `setState`。

### Windows 磁力播放 DLL 重建（2026-11-12 补充，版本号不变）

- 重编 `libtorrent_flutter.dll`（MSVC + libtorrent 2.0.11 + boost 1.85，ABI v2 /
  `TORRENT_NO_DEPRECATE`），移植此前仅 Android 端具备的两处原生补丁：
  修复「播放中供数停滞 → 种子预取窗口下满被 `remove_torrent` → `torrent_handle`
  失效 → 画面定格」的根因。本机 exe 200s 实测 `done` 持续供数至 101.5MB 不再冻结，
  磁力起播后画面稳定出图。

## 1.1.8 (2026-11-10)

> 本次为 Android + Windows + Web 三端一次性交付，版本 `1.1.8+68`。
> 相对 1.1.7 的全部改动如下。磁力缓冲「部分 piece 供数」实验经真机双向压力配对确认
> 无可复现收益，**默认保持关闭**，本版播放行为与 1.1.7 一致，不含该项优化。

### 字幕与资源标注

- 搜索结果、详情页、下载按钮旁的字幕标注改为分层探测结论：快速层看元数据文件清单，
  用户主动点徽标才读 MKV 内封轨 / 外挂字幕正文；取不到信息时明确写「字幕未知」，
  不再把「未知」误标成「没有字幕」，也不让探测抢播放的 peer。
- 磁力资源新增音轨 / 配音语言与字幕语言徽标，进详情页之前即可判断资源语言。
- 修复双字幕重影与字幕黑底：统一由 mpv / libass 单一渲染源出图，
  移除 Flutter 字幕浮层的重复绘制；外挂 SRT 与内封轨不再互相打架。
- 修复在线简中字幕匹配闭环；内封 `[简体内封]` 多为 PGS 图形轨、Android mpv 无法选中，
  此时自动降级到在线 SRT，并按正文汉字数校验，最多换 6 条。

### 播放稳定性与画面

- 修复磁力播放「永久定格」：同一 info-hash 复用 `torrent_handle` 时两个 id 指向同一种子，
  字幕层或任一方 `remove_torrent()` 会删掉正在播放的文件；现改为复用 id、
  活跃流绑定拒删、删除前解绑并唤醒等待线程。
- 修复全屏播放右侧黑边（前置挖孔 cutout 安全区），进入全屏用 `ALWAYS`、退出恢复 `DEFAULT`。
- 修复失败态无人清理导致压住在播画面：位置连续推进才撤销失败态，接策略层纯函数与单测。
- 修复调试日志并发写入丢行：改用 `RandomAccessFile` + 同步写 + 完整性横幅，
  日志可按「起始行号区间 + 本次启动横幅」双重切段。

### 构建与 Web

- 修复 Web 端构建失败：新增的字幕探测服务无条件引入 `dart:io` 与 `libtorrent_flutter`，
  经所有端共用的 `magnet_action_widgets.dart` 把 `dart:ffi` 拖进 dart2js 编译单元，
  报 `Only JS interop members may be 'external'`。现按平台条件加载，
  Web 端使用不依赖 FFI 的占位实现，结论显示「字幕未知」。
- 应用内更新检测沿用 GitHub `releases/latest`；本版 tag `v1.1.8`，
  客户端按语义版本比较后能正确识别 1.1.7 → 1.1.8 的升级。

## 1.1.7 (2026-11-06)

> 本次为 Android + Windows + Web 三端一次性交付，版本 `1.1.7+67`。
> 相对 1.1.6 的全部改动如下；字幕 / 刷新率 / 插帧方案仍在评估，**本版未包含**。

### 播放稳定性

- **后台播放**：`Video(pauseUponEnteringBackgroundMode: false)` + Android 前台服务
  （`FOREGROUND_SERVICE_MEDIA_PLAYBACK` / `PARTIAL_WAKE_LOCK` / 低优先级通知），
  返回桌面或切到其他 App 仍继续播放；只有真正暂停才释放前台服务。
- **自动缓冲挡位**：按物理内存定天花板（≤3.5G→128MB / ≤4.5G→192 / ≤6.5G→256 /
  ≤8.5G→384 / 其余 512MB），安装即识别并显示「自动（xxx MB）」与当前可用内存；播放中
  每 10 分钟按可用内存重新评估，升档 ×1.25 / 降档 ×0.8 防抖，探测失败保持原值。
  也可手动选挡位。**字节与秒数同步降低**（`secsForBytes`：128→300s / 192→600 /
  256→900 / 384→1200 / 512→1800），删掉旧 2700s 策略 —— 只降 `demuxer-max-bytes`
  而保持 `readahead-secs: 1800` 会让低码率流无限往后读，白耗流量/带宽/电量。
- **片尾卡死**：源站 EXTINF 虚标导致 mpv 提前 EOF；新增 `completion_policy.dart`
  （可播末端直接结束、否则最多恢复一次）+ 12 秒兜底 + 心跳看门狗
  （`isPlaying` 但位置 90s 不动即重载，最多 2 次）。
- **停滞检测盲区**：`isBufferExhaustedStall` 去掉 `if (isPlaying) return false`，
  引入 `advancing` 参数，播放中但位置不动也算停滞。
- **换集竞态**：`cancelPendingRecovery()` 清在途恢复定时器，
  `openGeneration` 防止旧集的 await 返回后污染新集状态。
- **播放进度权威**：前跳不再 >800ms 无条件接受，改按墙钟经过时间与速率预期判定，
  避免「切后台挂起后回前台补报 +5 分钟」被误判成跳变并 seek 回去倒带重播。
- **跳剧情诊断**：`[Jump]` 日志加 `expected = wall × rate` / `deviation = delta - expected`，
  `|deviation| ≥ 2000ms` 才落盘；`appSeek` 3 秒窗口排除 App 主动 seek；
  紧随的 mpv 快照比对 `time-pos` / `playback-time` 区分分片 pts 错乱与真 seek。
- **codec 打开失败**：非致命 codec / seek 错误只记日志，不再卡死播放生命周期。

### 「我的」与设置

- 删除「默认播放速度」设置项（字段 / setter / UI / 备份字段全链路）；播放器内临时倍速菜单保留。
- **观影统计改真实数据**：`WatchHistory.watchedMs` 按位置增量累计，单次增量 >30s
  视为拖动进度条不计，按归一化片名去重；删掉 `watchCount × 1.5` 的编造时长，
  老记录没有累计数据时显示占位而不是猜一个数字。
- **默认清晰度真正生效**：从「按线路名模糊加分」改为解析 HLS master playlist 的
  `RESOLUTION` / `BANDWIDTH` 变体（`hls_variant_selector.dart` 纯函数），
  自动档保持选最高码率，缺分辨率时按码率估算。
- **缓存不设上限**：`maxCacheSize = 0`，`ensureSpaceForDownload()` 直接放行，
  不再 LRU 删除用户已下载剧集；缓存页显示「已用 x，不设上限」。
- 硬件解码总开关合并进档位，旧 `hardwareDecode=false` 幂等迁移到 `disabled`。
- 播放偏好三档删除，保留「拖动精度」；「预加载下一集」与「播放预缓冲」合并为一个开关。
- 磁力内置死源（YTS / 1337x / BT4G / Nyaa 等）从 UI 收敛并默认关闭，给一次自动关闭提示。
- 数据导出 / 导入改走文件（系统下载目录 + `file_picker`）；WebDAV 抽公共弹窗，
  「我的」页可直达、设置页支持 anchor 定位。
  - 补修跨平台回归：`videocask/logExport` 通道只有 Android 实现，旧版 `DataExport`
    与 `LogExport` 无条件调用 → Windows / Linux 点导出必抛
    `MissingPluginException`（导出数据降级剪贴板、导出日志直接失败）。新增
    `download_export.dart` 按平台分流：Android→MediaStore 通道，桌面→直接写
    `getDownloadsDirectory()`（取不到退应用文档目录），Web→剪贴板；路由抽成
    纯函数、写文件抽成可直测 helper，7 条单测覆盖真实落盘、二进制 zip、
    同名覆盖与 `write()` 端到端。Windows AOT 里 `videocask/logExport` 被
    tree-shake 掉，编译期即确认桌面不会走 Android 通道。
- 「我的」页重排：头像压一行、统计卡只留「继续观看」、删快捷任务组、
  「数据同步」改「云备份」、关于与播放源去重；账号体系按用户要求保留。
- 历史集名归一化（`第01集` → `第1集`），首页与关注页统一。
- **修复英文系统下界面中英文混排**：根因不是词条漏翻，而是 `MaterialApp` 跟随系统
  `locale` 在 en-US 设备加载了英文分支，而界面另有大量中文硬编码，于是设置页出现
  `Downloads / Storage` 与「已用 0 B · 不设上限」同屏。新增
  `config/app_locale_policy.dart`（固定 `Locale('zh')` + 纯函数 `resolveAppLocale`），
  两个 `MaterialApp` 与初始化页都显式指定 locale，英文 arb 保留但不启用，
  待完整英文化 + 应用内语言开关再开放。新增 4 条单测（含「摘修复即红」断言）。

### 验证与交付状态

- `flutter analyze` 0 error（129 条 warning/info）；**97 个测试文件分 9 批全量实跑，
  793 通过 / 2 skipped / 0 失败**（含新增 7 条导出用例，声明总数 795 与实跑对齐）；
  Android release 三 ABI 构建成功（arm64 34.5MB，`libmpv.so` /
  `libtorrent_flutter.so` / `libapp.so` 抽检齐全）。
- 分批脚本 `D:\workbuddy_tmp\run_full_tests_1106.py`：清代理 + `TEMP/TMP/TMPDIR` 指
  `D:\flutter_test_tmp` + `--concurrency=2` + 每批 12 文件串行，日志落 D 盘。
  ⚠️ 跑完会吃掉 C 盘约 8G（`sessions/*/modify_backup/*.dill`）与 D 盘约 10G，
  收尾要清 C 盘这些 `.dill` 并清空 C/D 回收站，详见用户级 MEMORY.md。
- 导出修复追加验证：`download_export_test.dart` **7 条全过**（含真实落盘、
  二进制 zip、同名覆盖、`write()` 端到端）；`test/services/` **484 条全过**；
  对导出相关 5 个文件 `dart analyze` 为 `No issues found`。
- **真机实机验证通过**（HONOR 70 / FNE-AN00 / Android 14 / arm64）：装 arm64 release 包后
  首页 / 设置 / 缓存 / 我的 / 观影统计全中文、无溢出；A1 后台播放
  `PlaybackForegroundService isForeground=true foregroundId=1001 types=00000002`、
  通知「正在后台播放」、`ForegroundServiceStartNotAllowedException` 0 条；
  A2 自动缓冲按真机 7.3GB 内存识别为「自动（384 MB）」（1.9GB 模拟器为 128 MB）；
  回前台续播 1:38/47:29、3.42 MB/s 画面正常；导出数据 3282B、诊断日志 24389B 落
  `/sdcard/Download/`；全程 FATAL / ANR = 0。此前 adb 认不到真机的根因是 Windows
  重新枚举后 ADB Interface 的 `DeviceInterfaceGUID` 变成荣耀私有值，改成标准
  `{F72FE0D4-…}` 即恢复（脚本 `D:\workbuddy_tmp\fix_adb_guid.bat`，带备份）。
- 语言策略追加验证：`flutter analyze` 全项目 0 error（131 条 info/warning，与基线一致），
  新增 4 条单测 + 相关 42 条回归全过；en-US 模拟器与 en-US 真机各装机实测均为全中文。
- 本版三端 release 全量重建（Android 三 ABI / Windows / Web），并用
  `tool/package_deliverables.py --strict` 做产物新鲜度校验，避免新 Android + 旧
  Windows/Web 混装。Windows 新鲜度代表产物取 `data/app.so` 而非 C++ runner
  `movie_app.exe`（后者不随 Dart 代码重编，时间戳会停在几个月前）。
- ⚠️ **Web 构建必须非沙箱执行**：沙箱会拦 `build/web/main.dart.js` 的读写，表现为
  `Target web_release_bundle failed: Flutter failed to create file at ...`，
  Dart 编译其实已成功，与代码无关。打包脚本的 Web 解压目录同步同样会被安全中心拦，
  并留下「新 html + 旧 js」混合态 —— **Web 只交 zip**。
- 仍未验：真实声音（投屏 `--no-audio`）、默认清晰度真实 HLS 变体切换、A2「字节与秒数
  一起降低」的运行时参数（release 包 debugPrint 不进 logcat，目前只有单测与体感）；
  Web 端诊断日志入口缺 `kIsWeb` 守卫、C 长按 2x 复位、D4 首页续播点按约定未改。
- 跳剧情实机复测待用户执行，操作卡见 `D:\workbuddy_tmp\jump_selftest_kit.html`。

## 1.1.6 (2026-11-04)

- **磁力搜索重做：能快就快，慢也稳定出结果**
  - 多源并行 + 先到先上屏：每个源独立超时，谁先回来就先显示，不再被最慢的源拖住整页加载。
  - 新增 Knaben 聚合源：支持中文原名直查（实测《我不是药神》直接出结果），与 Torrentio 形成独立生态冗余。
  - 结果缓存（10 分钟，stale-while-revalidate）：重复搜索立即返回旧结果并后台刷新；空结果不缓存，避免「抖动一次就缓存空」。
  - 单源超时退避重试一次：个别源抖动不再导致整次搜索失败、需要再点一次。
  - 中文查询跳过 Torrentio（只认 IMDb id，中文文本必空还拖 14s），Knaben 请求体积 100→40；中文首包从 ~16s 降到 2s 级。
  - 修复 Knaben 标题显示成 `Uploader: xxx`：按 `<br>` 切行跳过上传者行，兜底 `title` / magnet `dn`。

## 1.1.5 (2026-11-03)

- **搜索「加载中」改为首屏出来即结束**
  - 现象：聚合搜索首屏结果早已落地，整页和影视资源标题行却仍长时间转圈，要等所有源把最多 10 页补齐页全部跑完才消失。
  - 根因：「加载中」的结束条件跟搜索流关闭绑定，而流关闭要求所有源阶段1 + 全部后台补齐页完成（`finished >= total && backgroundPending == 0`）。
  - 修复：`search_page` 在首次镜像到非空结果时立即翻转本地加载标志；后台补齐页仍由 provider 流式投递、静默追加，不再维持任何阻塞式 loading。

## 1.1.4 (2026-11-03)

- **修复换集后进度条比例画错**
  - 现象：切换到新一集后，进度条仍按上一集的时长比例定位，停留时间 / 进度看起来没变或比例不对。
  - 根因：普通换集分支只把播放位置归零，没清 `duration` / `buffered`，首帧到来时新位置配旧时长，按比例画错。
  - 修复：`_playEpisodeAsync` 在 `prepareOpen` 之后补零 `position` / `duration` / `bufferedPosition`（换集且不带续播点时生效），点选集、下一集、播完自动下一集统一覆盖。

- **修复磁力加载进度条「假推进」**
  - 现象：磁力解析卡在"第 5/6 步"附近，进度条定格在某个百分比不动，像卡死。
  - 根因：旧逻辑把"第 N/6 步"线性映射到固定百分比，等首帧这种长时间阶段无真实进度可显示却硬给一个值。
  - 修复：新增 `MagnetPrepProgressPolicy`，长时间等待（同阶段停留 ≥12s、等首帧等）切换为不确定态（进度条来回扫动）；只有拿到真实 `bufferPct` 时才用真实数据，避免误导。

- **修复总时长未知时时间显示错乱**
  - 现象：磁力刚起播、时长尚未取到时，时间显示 `0:01 / 0:00`（时长倒挂）。
  - 修复：`formatPlaybackClock` 在 `duration<=0` 时右侧显示 `--:--`。

- **性能与稳定性优化（#231 / #232 / #233）**
  - 详情页拆分、接口层（`api_service`）拆分与性能优化，首页与详情加载更顺、内存占用更稳。

- **深色主题与安全区审计（#239）**
  - 统一深色主题下次要文字颜色规范（不再写死 black54/black45）；修正若干 `SafeArea` 被遮挡的布局问题。

## 1.1.3 (2026-10-29)

- **修复看片时详情页信息「变脸」**
  - 现象：视频画面一直是对的，但过一会儿详情页的片名、简介、选集整块变成
    **另一部片**（实例：看《虹猫蓝兔七侠传》时变成《隔世追魂》1999）。
  - 根因（三处叠加）：
    1. 自动起播有 `currentPlayUrl != null` 守卫，视频一旦在播就绝不因
       `currentMovie` 变化重起 → 所以**画面不变**；
    2. 详情页多个区块**直接读全局 `currentMovie`**，绕过了本来的 `_displayMovie`
       守卫 → 所以**元数据会变**；
    3. `getMovieDetail(allowFallback:true)` 的 `_requestWithFallback` 是
       **按 id 跨源回退**，而各 CMS 的 `vod_id` 只在自己站内唯一 →
       同一个编号在别的站查到的是**另一部片**。
  - 修复：
    - 跨源兜底改为 `autoFallbackByTitle`：用 `DetailSourceMatcher` 按
      **片名 + 年份**打分匹配（低于阈值不要），并用**目标源自己的 id**
      二次加载，绝不复用旧 id。
    - 新增 `detailSession` **加载会话认领**：`MovieProvider` 记录本次加载的
      session，详情页只在 `detailSession == _expectedDetailSession` 时才认领
      结果，旧请求回来直接丢弃（同时允许自动换源后身份变化，不会误挡）。
    - 详情页所有直读 `currentMovie` 的点（`playback` / `data` / `page` /
      `episode` 四个 part）统一改走 `_displayMovie(...)` 守卫。
  - 实机验证（FNE-AN00 / debug 2072）：连续播放 40 秒以上元数据稳定为
    《虹猫蓝兔七侠传》；换集正常；换源结果只有 BD资源(2006·81集) 与
    红牛资源(2006·108集) 两条且均带「同名同年」，无错片混入。

- **「换源」结果只保留同名同年**
  - 之前跨源搜索容易混入同名不同片的结果，现在只有片名与年份都对得上的候选
    才会展示，并带「同名同年」标记。

- **「相关推荐」不再出现无关影片**
  - 之前用类型词去检索，会搜出诸如《剧情攻略手册》这类弱相关条目；
    现在改为按片名 / 去季片名 / 别名 / 导演等强相关线索检索，
    并对低分结果做过滤。

## 1.1.2 (2026-10-25)

- **磁力详情页补上中文影视介绍**
  - 现象：点开磁力详情页只有「资源标题 / 来源 / 大小」三行，**没有剧情简介**，
    也没有导演、主演、地区、类型这些基本信息。
  - 根因：`MagnetDetailEnrichmentService.enrich` 的中文简介**只有一条来源路径**——
    填了 TMDB API Key 才拿得到 `overview`；没填 Key 时会退到 IMDb，
    而 IMDb 兜底路径压根不返回剧情简介（`_composeDescription('', ...)`），
    于是简介区整块是空的。
  - 修复：新增**采集站（CMS）中文兜底**——用 App 自带的 CMS 采集站按片名检索
    （`ac=detail` 的结果自带 `vod_content` 中文简介 / 导演 / 主演 / 地区 / 类型），
    作为豆瓣与 IMDb 都拿不到时的第三级兜底。CMS 是 App 的主数据源，必定可达。
  - 附带修掉 IMDb 兜底的一个字段错误：IMDb 只给「主演」行没有导演，
    旧代码**拿第一个演员当导演**显示（肖申克的救赎显示导演是「蒂姆·罗宾斯」），
    现在导演一律只在真正拿到导演信息时才填。
  - 附带：磁力信息面板补上「类型」行。

- **磁力资源新增「下载」按钮**
  - 现象：磁力资源卡片只有「播放 / 磁力详情」两个按钮，没有下载入口。
  - 修复：每条磁力资源卡片新增「下载」按钮，点击后把该资源的磁力链接复制到剪贴板，
    并提示「已复制磁力链接，可粘贴到下载工具」。
  - 说明：当前播放器走的是 libtorrent 流式播放，没有暴露「整片落盘」的接口，
    所以按钮做的是「复制磁力链接」——这是这个版本能真实交付的下载动作。

## 1.1.1 (2026-10-24)

- **修复搜索页「磁力资源」模块整块消失**
  - 现象：搜索中文片名（如「教父」）时，磁力资源模块**整个消失**，既没有结果也没有任何提示。
  - 根因一（可见性）：搜索页判定「要不要显示磁力模块」时只看「有结果 / 还在搜」。
    磁力搜索一旦**返回空列表或超时**（回调里把结果清空、关掉加载态），
    模块连同它内部的「没有找到磁力资源 / 磁力搜索超时」提示**一起被隐藏**，
    提示被关在区块内部，永远没有出口 → 用户只看到"模块没了"。
  - 根因二（判定）：相关性判定在「中文标题 + 英文发布名」时必然判不相关
    （既不互相包含，分词也永远命中不了：matchCount 恒为 0），
    于是把**每一个**结果都滤掉 → 搜索返回空 → 回到根因一。
  - 修复：模块可见性改为「有结果 / 正在搜 / **本轮报过错**」三者取一，
    判定逻辑抽成纯函数 `shouldShowMagnetSection` / `isTorrentResultRelevant` 并加单测。
  - 附带：中文标题配英文发布名时不再做无依据的相关性过滤（源站本身已按标题检索过）。

- **修复多源聚合：除第一个源外，其余源出结果太慢**
  - 现象：影视资源聚合里第一个主源很快出来（首屏有东西了），
    但其余源迟迟不出现，用户以为搜不动。
  - 根因：每个采集源的搜索分两段——第 1 页先交付（首屏秒回），
    第 2..10 页在「补齐页」后台补齐。**补齐页此前跑在并发槽位内**，
    槽位要等补齐页全部结束才释放 → 一个慢源就占死 4 个槽位中的一个，
    排队的第 5~N 个源**连启动都被推迟**。
  - 修复：阶段 1 交付后**立刻释放槽位**，补齐页改为脱离槽位的后台任务；
    流的关闭条件相应改为「所有源的阶段 1 都结束 **且** 所有后台补页都结束」。
  - 回归：`api_service_multi_source_stream_test.dart` 新增
    「补齐页不占并发槽位」用例（摘掉修复即红，已验证）。

- **修复中文片名搜不到磁力资源**
  - 豆瓣 / TMDB / IMDb 三条片名解析路在部分网络环境下会**全不通** →
    解析返回 null → 回退查询是中文字幕 → 磁力源（英文索引）搜不到 → 结果为空。
  - 修复：新增**采集站兜底**——三者都失败时用 CMS 自己的搜索结果取英文别名
    （`Movie.alias`），CMS 是 App 自己的数据源，必定可达。

- **Windows 版：修复开机即崩溃 + 优化磁力首次加载**
  - 开机即崩溃：安装包缺少播放器的 libmpv 原生库（自切换 media_kit 分支后
    构建钩子的「跳过 event_loop 编译」连带把 libmpv 也跳过了），进程在
    初始化播放器时直接退出。现已修复，Windows 端可正常启动并出画。
  - 磁力首次加载：tracker 列表从 46 条精简为 9 条精选（关掉插件隐式追加、
    把实测能返回节点的 tracker 排到最前），**首个节点从 40 秒级降到几秒级**
    （实测多条 tracker 同时返回节点，元数据 3.6 秒就绪）。

## 1.1.0 (2026-10-23)

- **详情页「换源 / 换路线」位置对调**
  - 「换源」从标题区 chip 移到「选集 / 播放线路」Tab 行（桌面端同步移到右栏 TabBar 行）。
  - 「换路线」移到标题区原换源位置（桌面端同步移到头部）。
  - 顺带修复：单线路影片此前会**隐藏**换路线入口，现在单线路也显示（点开提示"该影片仅有 1 条播放线路"），
    多线路时直接切换——解决"路线永远只有一个、看不到换路线"的困惑（根因是采集站通常只返回 1 条线路，App 原样展示，无法凭空生成）。

- **设置页视频输出后端：重排 + 改写说明（基于实测纠偏）**
  - 顺序改为「新版渲染 → 旧版渲染 → 硬解直出」，与之前"把硬解直出夹在中间"不一致。
  - **关键纠正**：旧说明写"旧版渲染会泄漏崩溃、新版止漏"——这是错的。实测定论是
    **漏不漏只取决于送显桥接**（SurfaceProducer 漏 / SurfaceTexture 不漏），与 `--vo` 无关；
    现在 `player_service` 已锁死 `enableAndroidSurfaceProducer: false`（SurfaceTexture），
    三种后端都不漏。该设置现在只影响画面兼容性与功能（字幕/滤镜/截图/OSD），不再决定生死。
  - 删除"诊断日志目录"展示项，仅保留导出与清空（清空用途：删掉 Android/data 私有目录下平时取不出也删不掉的崩溃文件 / 历史日志）。

- **播放器底层注释与诊断口径修正**
  - 明确"句柄泄漏只取决于桥接方式、与渲染后端无关"，纠正此前"vo 决定泄漏"的错误认知。
  - 纠正"Vulkan 不支持老桥"的旧结论：新机 Adreno 830 在 Impeller-Vulkan 引擎下，
    SurfaceTexture 老桥实测出画且不泄漏（推翻"官方文档说 SurfaceTexture 仅 Skia 有效"的保守结论，以真机为准）。

## 1.0.51 (2026-10-22)

- **修复搜索结果页反复横跳、且出结果变慢**
  - 之前：一次搜索会同时发起「聚合（影视）源」与「磁力源」两条链，两条链各自
    往同一份状态里写，且**没有请求代次校验**。于是旧查询的回调晚到时会把新查询
    的结果清空或覆盖，页面在「聚合资源 → 加载中 → 只有磁力资源 → 没有结果 →
    又有聚合又有磁力」之间反复横跳。
  - 现在：搜索加了**请求代次**（旧一轮的回调一律丢弃）；清空结果与进入加载态
    改成**同一帧**完成，不再闪「没有找到相关内容」；搜索与搜索建议的防抖定时器
    拆成两个（原先共用一个，打字会把已排好的搜索静默取消，导致用户重复点搜索）。
  - 变慢的根因一并修掉：原先每个源必须把最多 10 页**全部**拉完才出结果，首屏
    被放大约 10 倍。现在改为**两段式**——第 1 页先到先显示（首屏秒回），补齐页
    在后台补上，兼顾「同名多作品」仍能拿到更多结果。
  - 搜索历史写入改到搜索开始之后异步进行，不再拖慢首屏。

- **播放器换用带 fd 泄漏修复补丁的 libmpv（Predidit 分支）**
  - 改用 media-kit 的 Predidit 分支（bundled libmpv v1.3.1）。fork 作者在
    media-kit #1391 中提供了 gpu-next OpenGL 路径的 fence 泄漏补丁；
    默认渲染后端为 `gpu-next`。
  - ⚠️ **是否修好尚未确认**：10-22 04:39 真机会话播放 25 分钟，fd 仍以 +22/s
    线性增长（99.4% 为 `anon_inode:sync_file`），05:04:07 SIGSEGV，崩溃时刻
    与 fd 耗尽时刻吻合在 1 秒内。两种解释无法区分：用户设置里仍选 `gpu` 旧路径 /
    命中 #1391 荣耀机型专属泄漏（作者无补丁）。需新诊断日志判定。

- **诊断系统增强（用于判定泄漏是否修好）**
  - 心跳新增 fd **增量差分**：`新增[分类...] 消失=N 全量[分类...]`，直接可见
    每个采样周期新增了哪类句柄；`anon_inode:sync_file`（无方括号形态）与
    `/dmabuf`（单列）都能正确分类（旧正则会把它们算错类）。
  - 新增 `probeVideoOutput()`：记录**实际生效**的 `current-vo` / `gpu-api` /
    `hwdec-current`，设置档位与实际不符时告警，并落盘 last_vo.txt。
  - 崩溃文件附带 fd 快照（fd_state.txt）；启动日志带设备指纹
    （manufacturer / SoC / Android 版本）。

- **移除全部「自动降档 / 自动兜底」机制，改为用户手动选择**
  - 删除：句柄兜底回收重建、渲染后端自动切换、硬解自动降档、崩溃黑名单、
    「首帧超时自动回退」守卫。相关代码与测试一并移除。
  - 原因：这些机制会自己成为问题源（兜底回收曾导致「十几秒卡一次」）。
    现在硬解档位与渲染后端都由用户在设置页手动选，应用不做任何自动干预；
    设置页与本文件的描述已同步更正。

## 1.0.50 (2026-10-22)

- 新增视频输出后端三档（设置页可手动选）：`gpu-next`（默认）/ `mediacodec_embed` / `gpu`。
- `VideoController` 显式传入 `VideoControllerConfiguration(vo, hwdec)`，修复「硬解/后端档位
  被 media_kit 默认值静默覆盖、设置不生效」的程序 bug。
- FD 泄漏哨兵 + 崩溃黑名单 + 设备指纹日志；回收阈值改为锚 `RLIMIT_NOFILE`，不再硬编码 700。
- 真机确认 `gpu` 后端 `anon:sync_file` 以 ~24 fd/s 线性泄漏（media-kit #1391）。

## 1.0.47 ~ 1.0.49 (2026-10-21)

- FD 兜底回收逻辑收敛：阈值锚 `RLIMIT_NOFILE`、连续低效（释放<15%）停用重建、最小回收
  间隔与临界 fd 保护，避免「回收自身制造十几秒卡顿」。
- 诊断日志分类统计 fd（anon / file / socket / pipe / dmabuf），修正 `anon_inode:sync_file`
  正则与 `/dmabuf` 归类，定位泄漏源为送显环节。
