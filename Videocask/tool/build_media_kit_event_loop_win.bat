@echo off
REM ============================================================================
REM  Build the media_kit "event_loop" native asset for Windows x64 by invoking
REM  cl.exe directly (no vcvars / no registry).
REM
REM  Why this exists
REM  --------------
REM  media_kit's Dart build hook compiles src/native_event_loop.c +
REM  src/native_library.c through native_toolchain_c's CBuilder, which boots
REM  the MSVC environment via "vcvars64.bat". vcvars64.bat -> VsDevCmd.bat ->
REM  vsdevcmd/core/winsdk.bat locates the Windows SDK by querying the registry
REM  ("HKLM\SOFTWARE\Microsoft\Windows Kits\Installed Roots"). This machine's
REM  security center blacklists reg.exe, so the SDK path stays empty and the
REM  compile dies with C1083 (cannot open include file: 'stdlib.h').
REM
REM  winsdk.bat unconditionally does "set WindowsSdkDir=" before re-deriving it,
REM  so pre-setting WindowsSdkDir in the environment does NOT help either.
REM
REM  Solution: compile the two tiny C files ourselves with cl.exe using
REM  explicit /I and /LIBPATH, bypassing vcvars entirely, and let the hook
REM  register the resulting prebuilt DLL as a native asset.
REM
REM  IMPORTANT: all paths must be free of spaces. cmd.exe strips the outer
REM  quotes of the executable path, then MSVC re-splits the command line on
REM  spaces -> "D:\VS" ends up parsed as a source file. tool\setup_mk_build_env.bat
REM  creates space-free junctions (D:\mk_build\vctool, \sdk, \dartsdk) for that.
REM
REM  Output: <media_kit package>\hook\prebuilt\windows\media_kit_event_loop.dll
REM  (the hook picks it up when skip-windows-event-loop is enabled)
REM
REM  Usage:  tool\build_media_kit_event_loop_win.bat
REM ============================================================================
setlocal enabledelayedexpansion

set "WORK=D:\mk_build"
set "VCTOOL=%WORK%\vctool"
set "SDK=%WORK%\sdk"
set "DARTSDK=%WORK%\dartsdk"
set "WINSDK_VER=10.0.22621.0"

if "%MK_SRC%"=="" set "MK_SRC=C:\Users\Wang\AppData\Local\Pub\Cache\git\media-kit-83b7ca63772856e1ea0158916177e136f7b7b0be\media_kit"
if "%MK_OUT%"=="" set "MK_OUT=%MK_SRC%\hook\prebuilt\windows"

set "CL_EXE=%VCTOOL%\bin\Hostx64\x64\cl.exe"
set "DUMPBIN_EXE=%VCTOOL%\bin\Hostx64\x64\dumpbin.exe"
set "OUT_DLL=%MK_OUT%\media_kit_event_loop.dll"

if not exist "%CL_EXE%" (
  echo [ERROR] cl.exe not found: %CL_EXE%
  echo         run tool\setup_mk_build_env.bat first
  exit /b 1
)
if not exist "%MK_SRC%\src\native_event_loop.c" (
  echo [ERROR] media_kit sources not found: %MK_SRC%\src
  exit /b 1
)
if not exist "%DARTSDK%\include\dart_native_api.h" (
  echo [ERROR] dart_native_api.h not found: %DARTSDK%\include
  exit /b 1
)
if not exist "%WORK%\src" mkdir "%WORK%\src"
if not exist "%WORK%\out" mkdir "%WORK%\out"
if not exist "%MK_OUT%" mkdir "%MK_OUT%"

copy /y "%MK_SRC%\src\native_event_loop.c" "%WORK%\src\" >nul
copy /y "%MK_SRC%\src\native_library.c" "%WORK%\src\" >nul

echo [1/3] Compiling media_kit_event_loop.dll ...
pushd "%WORK%\src"
set "_CL_="
set "CLCMD=%CL_EXE% /nologo /LD /MT /O2 /W3 /I%DARTSDK%\include /I%VCTOOL%\include /I%SDK%\Include\%WINSDK_VER%\ucrt /I%SDK%\Include\%WINSDK_VER%\um /I%SDK%\Include\%WINSDK_VER%\shared /I%SDK%\Include\%WINSDK_VER%\winrt native_event_loop.c native_library.c /Fe:%WORK%\out\media_kit_event_loop.dll /link /MACHINE:X64 /LIBPATH:%VCTOOL%\lib\x64 /LIBPATH:%SDK%\Lib\%WINSDK_VER%\ucrt\x64 /LIBPATH:%SDK%\Lib\%WINSDK_VER%\um\x64"
echo CMD: %CLCMD%
%CLCMD%
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" (
  echo [ERROR] cl.exe failed with exit code %RC%
  exit /b %RC%
)

echo [2/3] Verifying exports ...
"%DUMPBIN_EXE%" /EXPORTS "%WORK%\out\media_kit_event_loop.dll" > "%WORK%\out\exports.txt"
findstr /C:"media_kit_event_loop_create" /C:"media_kit_event_loop_stop" /C:"media_kit_event_loop_destroy" /C:"media_kit_event_loop_finalize" /C:"media_kit_event_loop_release" /C:"media_kit_library_path" "%WORK%\out\exports.txt" >nul
if errorlevel 1 (
  echo [ERROR] expected exports missing
  type "%WORK%\out\exports.txt"
  exit /b 1
)

echo [3/3] Installing to %OUT_DLL%
copy /y "%WORK%\out\media_kit_event_loop.dll" "%OUT_DLL%" >nul
dir "%OUT_DLL%"
echo [OK] done
exit /b 0
