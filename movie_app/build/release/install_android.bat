@echo off
REM ============================================================
REM movie_app 一键安装 — Android 端
REM ============================================================
REM 用法 1（无设备）：仅生成 APK，不安装
REM   build_release\install_android.bat
REM 用法 2（有 adb 设备）：自动 adb install -r
REM ============================================================
setlocal

set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%.."
set "APK=%PROJECT_DIR%\build\app\outputs\flutter-apk\app-release.apk"

if not exist "%APK%" (
    echo [错误] 找不到 APK：%APK%
    echo.
    echo 请先在项目根目录运行：  flutter build apk --release
    echo 或者直接：              powershell -File tool\build_apk.ps1
    echo.
    pause
    exit /b 1
)

echo [movie_app] APK 已就绪：%APK%

REM 检查 adb 是否可用
where adb >nul 2>nul
if errorlevel 1 (
    echo [提示] 未检测到 adb，跳过自动安装。
    echo        请用 USB 把手机接到电脑，再装该 APK 到设备。
    echo.
    pause
    exit /b 0
)

REM 检查 adb devices
adb devices | findstr /R "device$" >nul
if errorlevel 1 (
    echo [提示] adb 没有连上设备，跳过安装。
    echo        请在手机上打开「开发者选项 ^& USB 调试」并同意授权。
    echo.
    pause
    exit /b 0
)

echo [movie_app] 检测到 adb 设备，正在安装 ...
adb install -r "%APK%"
echo.
echo [movie_app] 安装完成。可以从手机桌面点 movie_app 图标启动。
echo.

endlocal
