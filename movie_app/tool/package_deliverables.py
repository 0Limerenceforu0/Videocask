"""把三端构建产物打包进 deliverables/，并同步解压目录。

用法：python tool/package_deliverables.py

产出（版本号从 pubspec.yaml 解析，文件名带版本便于覆盖升级识别）：
  deliverables/罐子_android_arm64_v{ver}.apk       (真机主流，推荐)
  deliverables/罐子_android_armeabi-v7a_v{ver}.apk (老 32 位机型)
  deliverables/罐子_android_x86_64_v{ver}.apk      (模拟器)
  deliverables/罐子_windows_v{ver}.zip + 同名解压目录
  deliverables/罐子_web_v{ver}.zip     + 同名解压目录

要点：
- Windows 只打包 build/windows/x64/runner/Release/（当前 VS 生成器的唯一可运行
  目录；旧 ninja 生成器的 x64_ninja/bundle 已不存在，以 WIN_BUNDLE 常量为准）。
- Web 包 = build/web + web_dev_server.py + serve_web.bat。
  这两个脚本不能少：视频/图片地址会被改写成同源 /proxy /hls，
  裸 http.server 没有这两个端点 → 点播放器一片灰（历史坑）。
- 解压目录按包内容**同步**（多出来的旧文件会被清掉），避免交付目录里
  残留上一次构建的文件（例如已删依赖的插件 DLL）。
"""
import glob
import os
import re
import shutil
import stat
import sys
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, 'tool')
DELIV = os.path.join(ROOT, 'deliverables')

APK_SRC = os.path.join(ROOT, 'build', 'app', 'outputs', 'flutter-apk')
# 2026-10-25：当前 Flutter(3.50 master, VS 生成器) 输出在 x64/runner/Release；
# 旧 ninja 生成器的 x64_ninja/bundle 已不存在。以实际存在的目录为准。
WIN_BUNDLE = os.path.join(ROOT, 'build', 'windows', 'x64', 'runner', 'Release')
WEB_DIR = os.path.join(ROOT, 'build', 'web')


def read_version():
    """从 pubspec.yaml 读 version（形如 1.0.23+23），去掉构建号返回 '1.0.23'。"""
    with open(os.path.join(ROOT, 'pubspec.yaml'), encoding='utf-8') as f:
        m = re.search(r'^version:\s*(\S+)', f.read(), re.M)
    if not m:
        print('  [错误] pubspec.yaml 里找不到 version')
        sys.exit(1)
    return m.group(1).split('+')[0]


VERSION = read_version()


def apk_map():
    return {
        'app-arm64-v8a-release.apk': '罐子_android_arm64_v%s.apk' % VERSION,
        'app-armeabi-v7a-release.apk': '罐子_android_armeabi-v7a_v%s.apk' % VERSION,
        'app-x86_64-release.apk': '罐子_android_x86_64_v%s.apk' % VERSION,
    }


# Web 包需要额外捎上的启动脚本（zip 内文件名, 源路径）
WEB_EXTRA = [
    ('web_dev_server.py', os.path.join(TOOL, 'web_dev_server.py')),
    ('serve_web.bat', os.path.join(TOOL, 'serve_web.bat')),
]

# 历史遗留/旧命名，打包时清掉，避免用户拿到不带版本的旧包
STALE = [
    '罐子_android.apk',
    '罐子_android_arm64.apk',
    '罐子_android_armeabi-v7a.apk',
    '罐子_android_x86_64.apk',
    '罐子_windows.zip',
    '罐子_web.zip',
]


def mb(path):
    return os.path.getsize(path) / 1048576.0


def build_zip(src_dir, dst, extras=()):
    if not os.path.isdir(src_dir):
        print('  [跳过] 目录不存在: %s' % src_dir)
        return None
    if os.path.exists(dst):
        os.chmod(dst, stat.S_IWRITE)
        os.remove(dst)
    count = 0
    with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        added = set()
        for dp, _, names in os.walk(src_dir):
            for name in names:
                full = os.path.join(dp, name)
                arc = os.path.relpath(full, src_dir).replace(os.sep, '/')
                z.write(full, arc)
                added.add(arc)
                count += 1
        for arcname, src in extras:
            # web/ 源目录已带了这两个脚本，构建产物里就有，别重复添加
            if arcname in added:
                continue
            if os.path.exists(src):
                z.write(src, arcname)
                count += 1
            else:
                print('  [警告] 缺少 %s' % src)
    print('  %-34s %7.1f MB  (%d 个文件)' % (os.path.basename(dst), mb(dst), count))
    return dst


def sync_dir(zip_path, dest):
    """把 zip 内容同步到目录：解压覆盖 + 删掉 zip 里没有的旧文件。"""
    if not zip_path or not os.path.exists(zip_path):
        return
    os.makedirs(dest, exist_ok=True)
    with zipfile.ZipFile(zip_path) as z:
        wanted = set()
        for info in z.infolist():
            if info.is_dir():
                continue
            wanted.add(info.filename.replace('/', os.sep))
            target = os.path.join(dest, info.filename.replace('/', os.sep))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            # zip 解出来的文件常带只读属性，先清掉再写，否则覆盖会 PermissionError
            if os.path.exists(target):
                os.chmod(target, stat.S_IWRITE)
            with z.open(info) as src, open(target, 'wb') as out:
                shutil.copyfileobj(src, out)
    removed = 0
    for dp, _, names in os.walk(dest):
        for name in names:
            full = os.path.join(dp, name)
            rel = os.path.relpath(full, dest)
            if rel not in wanted:
                os.chmod(full, stat.S_IWRITE)
                os.remove(full)
                removed += 1
    # 清掉空目录
    for dp, dirs, names in os.walk(dest, topdown=False):
        if not dirs and not names and dp != dest:
            os.rmdir(dp)
    print('  %-34s 已同步（清理 %d 个旧文件）' % (os.path.basename(dest), removed))


def check_artifact_freshness(strict=False):
    """核对三端产物是否是「同一次构建」，防止新旧代码混装进一个交付包。

    历史坑（2026-11-06）：只判断 os.path.exists()，结果是新 Android + 11-04 的
    旧 Windows/Web 一起打包。默认只警告不阻断；--strict 时直接失败。
    """
    win_exes = sorted(glob.glob(os.path.join(WIN_BUNDLE, '*.exe')))
    # Windows 的 movie_app.exe 是 C++ runner，业务代码没动时 flutter build windows
    # 不会重编它（时间戳可以停在几个月前）；随 Dart 代码重建的是 data/app.so。
    # 拿 exe 当代表会把「刚构建完」误判成「旧产物」（2026-11-06 实测）。
    win_aot = os.path.join(WIN_BUNDLE, 'data', 'app.so')
    reps = {
        'Android': os.path.join(APK_SRC, 'app-arm64-v8a-release.apk'),
        'Windows': win_aot,
        'Web': os.path.join(WEB_DIR, 'main.dart.js'),
    }
    stamps = {}
    print('三端产物时间戳：')
    for name, path in reps.items():
        if not os.path.exists(path) or '*' in path:
            print('  %-8s 缺失  %s' % (name, path))
            stamps[name] = None
            continue
        t = os.path.getmtime(path)
        stamps[name] = t
        print('  %-8s %s  %s' % (
            name, time.strftime('%Y-%m-%d %H:%M', time.localtime(t)), path))

    if win_exes:
        print('  Windows runner exe: %s（C++ runner，不随 Dart 代码重建）'
              % os.path.basename(win_exes[0]))
    else:
        print('  Windows runner exe: 缺失，交付目录会跑不起来')

    valid = [t for t in stamps.values() if t is not None]
    if len(valid) < 3 or not win_exes:
        problem = '有端尚未构建或 Windows runner exe 缺失，交付包会缺件'
    elif max(valid) - min(valid) > 6 * 3600:
        problem = '三端产物时间跨度超过 6 小时，极可能是新 Android + 旧 Windows/Web 混装'
    else:
        return True
    if strict:
        print('  [错误] %s；--strict 已终止打包。请先三端串行全量重建。' % problem)
        return False
    print('  [警告] %s' % problem)
    return True


def main():
    strict = '--strict' in sys.argv
    if not check_artifact_freshness(strict=strict):
        return 1
    os.makedirs(DELIV, exist_ok=True)

    print('版本: %s' % VERSION)

    print('复制 APK')
    for src_name, dst_name in apk_map().items():
        src = os.path.join(APK_SRC, src_name)
        if not os.path.exists(src):
            print('  [跳过] 未构建: %s' % src_name)
            continue
        dst = os.path.join(DELIV, dst_name)
        if os.path.exists(dst):
            os.chmod(dst, stat.S_IWRITE)
        shutil.copy2(src, dst)
        print('  %-40s %7.1f MB' % (dst_name, mb(dst)))

    print('清理旧的/不带版本名的包')
    for name in STALE:
        p = os.path.join(DELIV, name)
        if os.path.exists(p):
            os.chmod(p, stat.S_IWRITE)
            os.remove(p)
            print('  已移除 %s' % name)

    print('打包 + 同步 Windows')
    win_zip = build_zip(WIN_BUNDLE, os.path.join(DELIV, '罐子_windows_v%s.zip' % VERSION))
    sync_dir(win_zip, os.path.join(DELIV, '罐子_windows'))

    print('打包 + 同步 Web')
    web_zip = build_zip(WEB_DIR, os.path.join(DELIV, '罐子_web_v%s.zip' % VERSION), WEB_EXTRA)
    sync_dir(web_zip, os.path.join(DELIV, '罐子_web'))

    print()
    print('deliverables/ 目录内容：')
    for name in sorted(os.listdir(DELIV)):
        p = os.path.join(DELIV, name)
        if os.path.isfile(p):
            print('  %7.1f MB  %s' % (mb(p), name))
        else:
            n = sum(len(f) for _, _, f in os.walk(p))
            print('  <dir:%4d>   %s' % (n, name))


if __name__ == '__main__':
    sys.exit(main())
