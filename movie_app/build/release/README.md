# movie_app 三端打包 / 启动脚本

> **跨端单客户端** —— Android / Windows / Web 全部从同一份 `lib/` 编译产出。
> 已统一所有依赖启动路径，无需手动装额外服务。

## 速查表

| 端        | 启动方式                                    | 产物                                              | 大小    |
| --------- | ------------------------------------------- | ------------------------------------------------- | ------- |
| Windows   | 双击 `run_windows.bat`                      | `build\windows\x64_ninja\bundle\movie_app.exe`    | 48 文件 |
| Windows   | 首次打包+启动：`build_and_run_windows.bat`  | 同上（首次 5-15 min 编译）                        |         |
| Android   | 双击 `install_android.bat`                  | `build\app\outputs\flutter-apk\app-release.apk`   | 59 MB   |
| Web       | 双击 `serve_web.bat`                        | `build\web\`                                      | 39 MB   |

三个产物均已在本机构建验证通过（`flutter build apk --release` /
`tool\ninja_build.py build` / `flutter build web --release`）。

## 命令行用法（cmd / PowerShell）

```bat
:: 三端依次打包
flutter build apk   --release
flutter build web   --release
python tool\ninja_build.py build      :: Windows，见下方说明

:: 启动 / 安装
build\release\run_windows.bat       :: 启动 Windows 客户端
build\release\install_android.bat   :: 生成 / 安装 APK
build\release\serve_web.bat         :: 启 127.0.0.1:8787 HTTP 服务器
```

## Windows：为什么用 ninja 而不是 `flutter build windows`

`flutter build windows` 在部分环境会崩，两种典型症状：

1. `PathNotFoundException: Cannot create link` —— 创建插件 symlink 需要
   **开发者模式**或**管理员权限**；
2. doctor 诊断崩溃 —— 沙箱 / 受限环境拦截了 `reg.exe` / `wmic.exe`。

`tool\ninja_build.py` 直接调 `cmake + ninja + cl.exe`，不经过 flutter 工具链，
两者都能绕开。

### ephemeral 被清空的修复

`flutter clean` 或手工删目录会清掉 `windows\flutter\ephemeral\`，而它里面装着
两样 cmake 必需的东西：**Flutter 引擎产物**（`flutter_windows.dll.lib` 等）和
**插件 symlink**。缺了就报：

```
ninja: error: '.../ephemeral/flutter_windows.dll.lib', missing and no known rule to make it
```

一键修复：

```bat
python tool\windows_ephemeral_repair.py
```

它会：补插件 symlink → 从 Flutter SDK 的 engine artifact 拷引擎产物
（dll/lib/头文件/`icudtl.dat`/`cpp_client_wrapper`）→ 解包 media_kit 的
`mpv-dev` / `ANGLE` 两个 7z 并拍平 `libmpv/include/mpv` → `libmpv/include`。

> mpv / ANGLE 的 7z 由 cmake 从 GitHub 下载。若你的网络到 GitHub 不通，
> 需手动下载放到 `build\windows\x64_ninja\` 后重跑该脚本。

### 注意：只有 `bundle\` 是完整运行集

ninja 会同时产出 `runner\movie_app.exe`（只有 exe）和 `bundle\movie_app.exe`
（含 `flutter_windows.dll`、`libmpv-2.dll`、`data\app.so` 等 48 个文件）。
**要运行请用 `bundle\`**。`run_windows.bat` 会自动跳过不完整的目录。

## Web 端特殊说明

Web 必须用本地 HTTP 服务器跑（不能 `file://` 直接打开 `build/web/index.html`，
CanvasKit 会被 CORS 拦）。

`serve_web.bat` 默认用项目自带的 **Python 3.13**（WorkBuddy
`.workbuddy\binaries\python\`）。如果你装了别的 Python，放到 PATH 即可。

**重要**：磁力 / HLS / 去广告 等本地代理都在 `tool\web_dev_server.py` 的
8787 端口上。要体验完整功能（磁力播放、HLS 去广告）用这个：

```bat
python tool\web_dev_server.py --port 8787
```

而不是简单的 `python -m http.server`，后者会 404 代理请求。

## Android 说明

`flutter build apk --release` 首次需要从 GitHub 拉
libtorrent 的 Android NDK 预编译包和 media_kit 的 mpv-android 二进制
（`build\media_kit_libs_android_video\`），**首次会卡几分钟等下载**，
之后走缓存就快了。

## git 回滚

清理前的状态（70 个未提交文件 + 9 个 stub）保留在 `commit a81d38a`：

```sh
git log --oneline          # 看基线
git reset --hard a81d38a   # 一键回到清理前
```
