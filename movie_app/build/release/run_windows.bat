@echo off
REM ============================================================
REM movie_app 一键启动 — Windows 桌面端
REM ============================================================
REM 双击运行即可。自动探测常见的构建产物位置。
REM ============================================================
setlocal

set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%..\"

REM 优先级 1：cmake --install 出来的 bundle（含完整运行时）
set "CANDIDATES[1]=%PROJECT_DIR%build\windows\x64_ninja\bundle\movie_app.exe"
REM 优先级 2：ninja 构建的 runner
set "CANDIDATES[2]=%PROJECT_DIR%build\windows\x64_ninja\runner\movie_app.exe"
REM 优先级 3：flutter build windows 默认 release
set "CANDIDATES[3]=%PROJECT_DIR%build\windows\x64\runner\Release\movie_app.exe"

set "EXE="
for /l %%i in (1,1,3) do (
    call set "CAND=%%CANDIDATES[%%i%%]"
    if exist "!CAND!" (
        set "EXE=!CAND!"
        goto :LAUNCH
    )
)

if "%EXE%"=="" (
    echo [错误] 没找到 movie_app.exe，请依次确认：
    echo    1) 已运行过 build_and_run_windows.bat 或 tool\ninja_build.py
    echo    2) 或运行：flutter build windows --release
    echo.
    pause
    exit /b 1
)

:LAUNCH
echo [movie_app] 启动 Windows 客户端 ...
echo [movie_app] 路径：%EXE%
echo.

cd /d "%PROJECT_DIR%"
start "" "%EXE%"

endlocal
