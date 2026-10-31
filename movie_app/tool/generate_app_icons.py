# 生成全平台应用图标（Android / Windows / Web）
#
# 用法：
#   python tool/generate_app_icons.py [源图片路径]
# 默认源图：branding/app_icon_source.png
#
# 处理要点（2026-10-18 定稿：白色胶片图形 + 纯黑背景）：
# - 源图是深色圆底 + 白色图形，按亮度双峰阈值抠图：暗部（含胶片框内孔）全透明，亮部（图形）不透明；
#   再做一次 alpha 色阶收紧，消掉放大后的灰边光晕；
# - 所有端统一铺**纯黑背景**（Android 自适应背景层 / 传统 5 档 / Windows ICO / Web favicon+PWA）；
#   Android 自适应图标前景仍是透明图形，靠背景层提供黑色；
# - Windows ICO 用 PNG 条目写入（PIL bitmap_format='png'），小尺寸也保留 alpha；
# - 产物按内容 bbox 裁切 + 6% 留白。
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
# 源图与主图放在 branding/（不进 assets/，避免被打进 App 包体）
BRANDING = ROOT / "branding"
SRC_DEFAULT = BRANDING / "app_icon_source.png"

# 图标内容相对画布的留白比例（左右各 6%）
PADDING_RATIO = 0.06
# 抠图亮度阈值：低于 LOW 全透明，高于 HIGH 全不透明，中间线性过渡
ALPHA_LOW = 95
ALPHA_HIGH = 165
# alpha 色阶收紧的下限：低于该值的半透明像素直接归零，避免放大后出现灰边光晕
ALPHA_FLOOR = 46
MASTER_SIZE = 1024
# 图标背景色：纯黑
ICON_BG = (0, 0, 0)


def load_source(path: Path) -> Image.Image:
    img = Image.open(path)
    if img.mode != "RGB":
        img = img.convert("RGB")
    return img


def cutout(img: Image.Image) -> Image.Image:
    """按亮度把深色背景抠成透明，只保留亮色图形（边缘线性过渡 + 轻微模糊）。"""
    a = np.array(img).astype(np.float32)
    lum = a.mean(axis=2)
    alpha = np.clip((lum - ALPHA_LOW) / (ALPHA_HIGH - ALPHA_LOW), 0.0, 1.0) * 255.0
    alpha_img = Image.fromarray(alpha.astype(np.uint8), "L")
    alpha_img = alpha_img.filter(ImageFilter.GaussianBlur(0.6))

    # alpha 色阶收紧：把极淡的边缘像素推到全透明，避免放大后出现灰边光晕
    a2 = np.array(alpha_img).astype(np.float32)
    a2 = np.clip((a2 - ALPHA_FLOOR) * 255.0 / (255.0 - ALPHA_FLOOR), 0.0, 255.0)
    alpha_img = Image.fromarray(a2.astype(np.uint8), "L")

    out = img.convert("RGBA")
    out.putalpha(alpha_img)
    return out


def crop_content(rgba: Image.Image) -> Image.Image:
    """按 alpha 内容 bbox 居中裁成正方形（带留白）。"""
    a = np.array(rgba)[:, :, 3]
    ys, xs = np.where(a > 8)
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1

    side = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    canvas_side = int(round(side * (1 + 2 * PADDING_RATIO)))

    left = int(round(cx - canvas_side / 2))
    top = int(round(cy - canvas_side / 2))
    patch = rgba.crop(
        (
            max(0, left),
            max(0, top),
            min(rgba.width, left + canvas_side),
            min(rgba.height, top + canvas_side),
        )
    )
    canvas = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
    canvas.paste(patch, (max(0, -left), max(0, -top)), patch)
    return canvas


def render(master: Image.Image, size: int, sharpen: bool = False) -> Image.Image:
    out = master.resize((size, size), Image.LANCZOS)
    if sharpen:
        out = out.filter(ImageFilter.UnsharpMask(radius=0.8, percent=45, threshold=2))
    return out


def build_android(fg: Image.Image, tile: Image.Image) -> None:
    res = ROOT / "android" / "app" / "src" / "main" / "res"

    # 传统图标（<API 26）：黑底方块，避免老启动器上透明区变黑/看不见
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for dpi, size in legacy.items():
        d = res / f"mipmap-{dpi}"
        d.mkdir(parents=True, exist_ok=True)
        render(tile, size, sharpen=True).save(d / "ic_launcher.png", "PNG", optimize=True)

    # 自适应图标前景：108dp 画布，内容落在中间约 58dp（72dp 可见圆内）
    adaptive = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for dpi, size in adaptive.items():
        d = res / f"mipmap-{dpi}"
        d.mkdir(parents=True, exist_ok=True)
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        inner = int(size * 0.66)
        art = fg.resize((inner, inner), Image.LANCZOS)
        off = (size - inner) // 2
        canvas.paste(art, (off, off), art)
        canvas.save(d / "ic_launcher_foreground.png", "PNG", optimize=True)

    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )
    # 背景层用纯黑（用户 2026-10-18 要求「背景还是设置黑色」）
    (res / "values" / "colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        '    <color name="ic_launcher_background">#FF000000</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )
    print("Android: 传统图标 5 档(黑底) + 自适应前景 5 档(透明图形) + 背景层 #FF000000")


def build_windows(tile: Image.Image) -> None:
    out = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    sizes = [
        (16, 16), (20, 20), (24, 24), (32, 32), (40, 40),
        (48, 48), (64, 64), (96, 96), (128, 128), (256, 256),
    ]
    # bitmap_format='png'：所有档位都用 PNG 条目，小尺寸也保留 alpha
    tile.resize((256, 256), Image.LANCZOS).save(
        out, format="ICO", sizes=sizes, bitmap_format="png"
    )
    print(f"Windows: {out.relative_to(ROOT)} (多尺寸 ICO，黑底)")


def build_web(tile: Image.Image) -> None:
    # favicon / PWA 图标：黑底 + 白色图形
    render(tile, 64, sharpen=True).save(ROOT / "web" / "favicon.png", "PNG", optimize=True)

    icons = ROOT / "web" / "icons"
    icons.mkdir(parents=True, exist_ok=True)
    for size in (192, 512):
        tile.resize((size, size), Image.LANCZOS).save(icons / f"Icon-{size}.png", "PNG", optimize=True)
        # maskable：内容收进中心 80% 安全区，背景同样为黑
        canvas = Image.new("RGB", (size, size), ICON_BG)
        inner = int(size * 0.8)
        art = tile.resize((inner, inner), Image.LANCZOS)
        off = (size - inner) // 2
        canvas.paste(art, (off, off))
        canvas.save(icons / f"Icon-maskable-{size}.png", "PNG", optimize=True)
    print("Web: favicon.png 64 + Icon-192/512 + maskable 192/512（黑底）")


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else SRC_DEFAULT
    if not src.exists():
        print(f"源图不存在: {src}")
        return 1

    keep = BRANDING / "app_icon_source.png"
    keep.parent.mkdir(parents=True, exist_ok=True)
    if src.resolve() != keep.resolve():
        Image.open(src).convert("RGB").save(keep, "PNG")
        print(f"源图已归档: {keep.relative_to(ROOT)}")

    img = load_source(keep)
    rgba = cutout(img)
    square = crop_content(rgba)
    fg = square.resize((MASTER_SIZE, MASTER_SIZE), Image.LANCZOS)
    fg = fg.filter(ImageFilter.UnsharpMask(radius=1.0, percent=35, threshold=2))
    fg.save(BRANDING / "app_icon_fg.png", "PNG", optimize=True)

    # 带黑底的方块图：给传统图标 / exe / Web 用
    tile = Image.new("RGB", (MASTER_SIZE, MASTER_SIZE), ICON_BG)
    tile.paste(fg, (0, 0), fg)
    tile.save(BRANDING / "app_icon_tile.png", "PNG", optimize=True)

    build_android(fg, tile)
    build_windows(tile)
    build_web(tile)
    print("完成")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
