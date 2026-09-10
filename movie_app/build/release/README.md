# movie_app 一键打包脚本（三个 release 入口全收口在这里）

> **跨端单客户端**——Android / Windows / Web 全部从同一份 `lib/` 编译产出。
> 已统一了所有依赖启动路径，无需手动装额外服务。

## 速查表

| 产物                  | 启动脚本                       | 产物大小           |
| --------------------- | ------------------------------ | ------------------ |
| Windows 桌面          | `run_windows.bat`              | ~150 MB            |
| Windows 首次打包+启动 | `build_and_run_windows.bat`    | (含 5-15min 编译)  |
| Android APK           | `install_android.bat`          | ~59 MB             |
| Web 静态              | `serve_web.bat`                | ~39 MB             |

## 命令行用法（推荐 cmd / PowerShell）

```bat
:: 三端依次打包（推荐首次执行）
flutter build windows --release
flutter build apk   --release
flutter build web   --release

:: 启动 / 安装
build\release\run_windows.bat       :: 启动 Windows 客户端
build\release\install_android.bat   :: 生成 / 安装 APK
build\release\serve_web.bat         :: 启 127.0.0.1:8787 HTTP 服务器
```

## Web 端特殊说明

Web 必须用本地 HTTP 服务器跑（不能 `file://` 直接打开 `build/web/index.html`，CanvasKit 会被 CORS 拦）。

`serve_web.bat` 默认用项目自带的 **Python 3.13**（WorkBuddy `.workbuddy/binaries/python/`）。如果你装了别的 Python，把它放到 PATH 即可。

**重要**：磁力 / HLS / 去广告 等本地代理都在 `tool/web_dev_server.py` 的 8787 端口上。如果要体验完整功能（磁力播放、HLS 去广告），用这个：

```bat
python tool\web_dev_server.py --port 8787
```

而不是简单的 `python -m http.server`，后者会 404 代理请求。

## Windows 沙箱限制提示

如果在你机器上跑 `flutter build windows` 报「`PathNotFoundException: Cannot create link`」或「沙箱拦截 reg.exe/wmic.exe」，绕道命令是：

```bat
call python tool\ninja_build.py build
```

这条命令直接调 `cmake + ninja + cl.exe`，不经过 flutter 工具链，能绕过医生诊断。

## Android 沙箱特殊说明

`flutter build apk --release` 在沙箱里需要先下 libtorrent 的 Android NDK 预编译包（~100MB）。**首次跑会卡在 "libtorrent_flutter: downloading prebuilt arm64-v8a from https://github.com/..."** 等几分钟。下次跑就快了。

## git 回滚

清理前的状态（70 个未提交文件 + 9 个 stub）保留在 `commit a81d38a`：

```sh
git log --oneline      # 看基线
git reset --hard a81d38a   # 一键回到清理前
```
