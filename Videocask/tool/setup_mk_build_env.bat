@echo off
REM Create space-free junctions so that cl.exe arguments survive the
REM "cmd strips outer quotes -> MSVC re-splits on spaces" problem.
setlocal
if not exist D:\mk_build mkdir D:\mk_build
if not exist D:\mk_build\vctool mklink /J D:\mk_build\vctool "D:\VS Studio\Community\VC\Tools\MSVC\14.43.34808"
if not exist D:\mk_build\sdk mklink /J D:\mk_build\sdk "D:\Windows Kits\10"
if not exist D:\mk_build\dartsdk mklink /J D:\mk_build\dartsdk "E:\FultterProject\flutter\bin\cache\dart-sdk"
if not exist D:\mk_build\src mkdir D:\mk_build\src
if not exist D:\mk_build\out mkdir D:\mk_build\out
echo [ok] junctions ready
dir D:\mk_build
