"""Generate native launcher icons from the approved STROYKA square artwork.

Requires Pillow: python3 -m pip install Pillow
Run from the repository root: python3 tool/generate_launcher_icons.py
"""

from pathlib import Path

from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/stroyka_app_icon.png"
IOS = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
ANDROID = ROOT / "android/app/src/main/res"
RESAMPLE = Image.Resampling.LANCZOS

IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}
ANDROID_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def main() -> None:
    source = Image.open(SOURCE)
    if source.width != source.height:
        raise ValueError("Launcher source must be square")
    if source.mode == "RGBA" and source.getchannel("A").getextrema() != (255, 255):
        raise ValueError("Launcher source must be fully opaque")
    artwork = source.convert("RGB")

    for name, size in IOS_SIZES.items():
        artwork.resize((size, size), RESAMPLE).save(IOS / name, format="PNG")

    for density, size in ANDROID_SIZES.items():
        folder = ANDROID / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        artwork.resize((size, size), RESAMPLE).save(
            folder / "ic_launcher.png", format="PNG"
        )

    # Android adaptive icons reveal only the central 66/108 dp circle. Keep the
    # whole composition inside that safe zone so the wordmark stays visible.
    background = Image.new("RGB", (432, 432), (5, 42, 91))
    foreground = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    inset_size = 256
    inset = artwork.resize((inset_size, inset_size), RESAMPLE).convert("RGBA")
    alpha = Image.new("L", (inset_size, inset_size), 0)
    alpha.paste(255, (12, 12, inset_size - 12, inset_size - 12))
    inset.putalpha(alpha.filter(ImageFilter.GaussianBlur(7)))
    foreground.alpha_composite(inset, ((432 - inset_size) // 2,) * 2)

    drawable = ANDROID / "drawable-nodpi"
    drawable.mkdir(parents=True, exist_ok=True)
    background.save(drawable / "ic_launcher_background.png", format="PNG")
    foreground.save(drawable / "ic_launcher_foreground.png", format="PNG")


if __name__ == "__main__":
    main()
