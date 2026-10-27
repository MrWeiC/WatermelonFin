#!/usr/bin/env python3
from pathlib import Path
import argparse
import base64
from collections import deque
import io
import math
import re
import shutil

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ModuleNotFoundError as error:
    raise SystemExit(
        "GenerateWatermelonFinAssets.py requires Pillow. "
        "Install it with `python3 -m pip install Pillow` or run this script with a Python environment that already includes Pillow."
    ) from error


ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "WatermelonFin tvOS/Resources/Assets.xcassets"
IOS_ASSETS = ROOT / "WatermelonFin iOS/Resources/Assets.xcassets"
BRAND = ASSETS / "App Icon & Top Shelf Image.brandassets"
PREVIEW = ROOT / "docs/watermelonfin-logo-assets-preview.png"
DEFAULT_SOURCE = ROOT / "Scripts/Branding/Sources/watermelonfin-original.png"

COLORS = {
    "obsidian": "#050907",
    "night": "#10120B",
    "deep_teal": "#082B15",
    "badge": "#141006",
    "cyan": "#F53C5F",
    "aqua": "#36A423",
    "blue": "#F4E9B8",
    "white": "#FFFFFF",
}

LOGO_TARGETS = [
    ("watermelonfin-logo.png", (520, 120)),
    ("watermelonfin-logo@2x.png", (1040, 240)),
    ("watermelonfin-logo@3x.png", (1560, 360)),
]

ICON_TARGETS = [
    ("App Icon.imagestack/Back.imagestacklayer/Content.imageset/400x240-back.png", (400, 240), "RGB"),
    ("App Icon.imagestack/Back.imagestacklayer/Content.imageset/800x480-back.png", (800, 480), "RGB"),
    ("App Icon.imagestack/Front.imagestacklayer/Content.imageset/400x240-front.png", (400, 240), "RGBA"),
    ("App Icon.imagestack/Front.imagestacklayer/Content.imageset/800x480-front.png", (800, 480), "RGBA"),
    ("App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/1280x768-back.png", (1280, 768), "RGB"),
    ("App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/1280x768-front.png", (1280, 768), "RGBA"),
]

TOP_SHELF_TARGETS = [
    ("Top Shelf Image.imageset/top-shelf-1920x720.png", (1920, 720)),
    ("Top Shelf Image.imageset/top-shelf-3840x1440.png", (3840, 1440)),
    ("Top Shelf Image Wide.imageset/top-shelf-wide-2320x720.png", (2320, 720)),
    ("Top Shelf Image Wide.imageset/top-shelf-wide-4640x1440.png", (4640, 1440)),
]


def rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def mix(a, b, amount):
    return tuple(round(a[index] + (b[index] - a[index]) * amount) for index in range(3))


def font(size, bold=False):
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def load_source_image(source):
    if not source.exists():
        raise SystemExit(f"Source artwork does not exist: {source}")

    if source.suffix.lower() == ".svg":
        text = source.read_text(errors="ignore")
        match = re.search(r'data:image/(?:png|jpeg|jpg);base64,([^"]+)', text)
        if not match:
            raise SystemExit(f"Could not find an embedded raster image in SVG: {source}")
        data = base64.b64decode(match.group(1))
        return Image.open(io.BytesIO(data)).convert("RGBA")

    return Image.open(source).convert("RGBA")


def is_light_background(pixel):
    red, green, blue, alpha = pixel
    return alpha == 0 or (red > 230 and green > 230 and blue > 230)


def remove_edge_background(image):
    image = image.convert("RGBA")
    width, height = image.size
    pixels = image.load()
    background = Image.new("L", image.size, 0)
    background_pixels = background.load()
    queue = deque()

    for x in range(width):
        for y in (0, height - 1):
            if is_light_background(pixels[x, y]):
                background_pixels[x, y] = 255
                queue.append((x, y))

    for y in range(height):
        for x in (0, width - 1):
            if is_light_background(pixels[x, y]) and background_pixels[x, y] == 0:
                background_pixels[x, y] = 255
                queue.append((x, y))

    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < width and 0 <= ny < height and background_pixels[nx, ny] == 0:
                if is_light_background(pixels[nx, ny]):
                    background_pixels[nx, ny] = 255
                    queue.append((nx, ny))

    foreground = background.point(lambda value: 0 if value else 255).filter(ImageFilter.GaussianBlur(0.6))
    result = image.copy()
    result.putalpha(foreground)
    return result


def trim(image, padding=0):
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        return image

    left = max(0, bbox[0] - padding)
    top = max(0, bbox[1] - padding)
    right = min(image.width, bbox[2] + padding)
    bottom = min(image.height, bbox[3] + padding)
    return image.crop((left, top, right, bottom))


def remove_white_matte(image):
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                continue

            distance_from_white = max(255 - red, 255 - green, 255 - blue)
            if distance_from_white <= 10:
                pixels[x, y] = (red, green, blue, 0)
                continue

            # The source wordmark was rasterized on white. Convert the white
            # matte into alpha so anti-aliased edges do not leave a light halo.
            normalized = min(1, (distance_from_white - 10) / 80)
            new_alpha = round(255 * normalized)
            if new_alpha >= 250:
                pixels[x, y] = (red, green, blue, 255)
                continue

            matte = 255 * (1 - new_alpha / 255)
            unpremultiplied = []
            for channel in (red, green, blue):
                value = (channel - matte) / max(new_alpha / 255, 0.001)
                unpremultiplied.append(round(max(0, min(255, value))))
            pixels[x, y] = (*unpremultiplied, new_alpha)
    return image


def solid_brand_wordmark(image):
    image = remove_white_matte(image)
    pixels = image.load()
    red_fill = rgb("#F53357")
    green_fill = rgb("#2D8F1E")

    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                continue

            saturation = max(red, green, blue) - min(red, green, blue)
            brightness = (red + green + blue) / 3
            if alpha < 8 or (brightness > 90 and saturation < 38):
                pixels[x, y] = (red, green, blue, 0)
                continue

            fill = green_fill if green > red + 8 else red_fill
            pixels[x, y] = (*fill, alpha)

    return image


def remove_translucent_edge_matte(image):
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0 or alpha >= 250:
                continue

            saturation = max(red, green, blue) - min(red, green, blue)
            brightness = (red + green + blue) / 3
            if alpha < 8 or (brightness > 210 and saturation < 42):
                pixels[x, y] = (red, green, blue, 0)
                continue

            opacity = alpha / 255
            unpremultiplied = []
            for channel in (red, green, blue):
                value = (channel - 255 * (1 - opacity)) / max(opacity, 0.001)
                unpremultiplied.append(round(max(0, min(255, value))))
            pixels[x, y] = (*unpremultiplied, alpha)
    return image


def source_pieces(source):
    art = remove_edge_background(load_source_image(source))
    width, height = art.size
    mark = remove_translucent_edge_matte(trim(art.crop((0, 0, width, round(height * 0.76))), padding=10))
    wordmark = solid_brand_wordmark(trim(art.crop((0, round(height * 0.76), width, height)), padding=10))
    return mark, wordmark


def fit(image, max_size):
    max_width, max_height = max_size
    scale = min(max_width / image.width, max_height / image.height)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(size, Image.Resampling.LANCZOS)


def paste_center(base, image, center):
    x = round(center[0] - image.width / 2)
    y = round(center[1] - image.height / 2)
    base.alpha_composite(image, (x, y))


def paste_shadow(base, image, center, blur, offset, opacity):
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shadow.putalpha(image.getchannel("A").point(lambda value: round(value * opacity)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    paste_center(base, shadow, (center[0] + offset[0], center[1] + offset[1]))


def paste_fitted(base, image, box, shadow=False):
    x, y, width, height = box
    fitted = fit(image, (width, height))
    center = (x + width / 2, y + height / 2)
    if shadow:
        paste_shadow(
            base,
            fitted,
            center,
            blur=max(2, round(min(base.size) * 0.025)),
            offset=(0, round(base.height * 0.025)),
            opacity=0.42,
        )
    paste_center(base, fitted, center)


def linear_background(size):
    width, height = size
    image = Image.new("RGBA", size)
    pixels = image.load()
    start = rgb(COLORS["obsidian"])
    middle = rgb(COLORS["night"])
    end = rgb(COLORS["deep_teal"])

    for y in range(height):
        for x in range(width):
            amount = (x / max(1, width - 1) * 0.58) + (y / max(1, height - 1) * 0.42)
            if amount < 0.62:
                color = mix(start, middle, amount / 0.62)
            else:
                color = mix(middle, end, (amount - 0.62) / 0.38)
            pixels[x, y] = (*color, 255)

    return image


def radial_glow(base, center, radius, color, alpha):
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    pixels = overlay.load()
    cr, cg, cb = rgb(color)
    cx, cy = center
    left = max(0, round(cx - radius))
    right = min(base.width, round(cx + radius))
    top = max(0, round(cy - radius))
    bottom = min(base.height, round(cy + radius))

    for y in range(top, bottom):
        for x in range(left, right):
            distance = math.hypot(x - cx, y - cy) / radius
            if distance <= 1:
                pixels[x, y] = (cr, cg, cb, round(alpha * (1 - distance) ** 1.9))

    return Image.alpha_composite(base.convert("RGBA"), overlay)


def draw_mist(base):
    width, height = base.size
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    bands = [
        (-0.08, 0.34, 0.54, 0.13, (195, 232, 240, 24)),
        (0.22, 0.50, 0.58, 0.12, (105, 196, 215, 22)),
        (0.56, 0.28, 0.44, 0.15, (225, 244, 246, 18)),
        (0.12, 0.76, 0.48, 0.14, (70, 166, 190, 20)),
    ]

    for x, y, band_width, band_height, fill in bands:
        draw.ellipse(
            (
                round(width * x),
                round(height * y),
                round(width * (x + band_width)),
                round(height * (y + band_height)),
            ),
            fill=fill,
        )

    return Image.alpha_composite(base, overlay.filter(ImageFilter.GaussianBlur(max(12, width // 34))))


def draw_forest_silhouette(base):
    width, height = base.size
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    tree_count = max(8, width // 190)
    base_y = round(height * 0.96)

    for index in range(tree_count):
        progress = index / max(1, tree_count - 1)
        x = round(width * (-0.03 + progress * 1.08))
        tree_height = round(height * (0.22 + 0.12 * ((index * 7) % 5) / 4))
        trunk_top = base_y - tree_height
        color = (3, 31, 39, 62 if index % 2 else 48)
        trunk_width = max(1, width // 820)
        draw.line((x, trunk_top, x, base_y), fill=color, width=trunk_width)

        levels = 5
        for level in range(levels):
            level_y = trunk_top + round(tree_height * (0.20 + level * 0.15))
            spread = round(tree_height * (0.16 + level * 0.055))
            draw.polygon(
                [
                    (x, level_y - round(tree_height * 0.16)),
                    (x - spread, level_y + round(tree_height * 0.15)),
                    (x + spread, level_y + round(tree_height * 0.15)),
                ],
                fill=color,
            )

    overlay = overlay.filter(ImageFilter.GaussianBlur(max(0.4, width / 1200)))
    return Image.alpha_composite(base, overlay)


def brand_background(size):
    width, height = size
    image = linear_background(size)
    image = radial_glow(image, (width * 0.72, height * 0.18), min(size) * 0.66, COLORS["aqua"], 44)
    image = radial_glow(image, (width * 0.16, height * 0.74), min(size) * 0.74, COLORS["cyan"], 42)
    image = draw_mist(image)
    image = draw_forest_silhouette(image)
    return image


def gradient_fill(base, mask, bounds):
    x, y, width, height = bounds
    fill = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    pixels = fill.load()
    aqua = rgb(COLORS["aqua"])
    cyan = rgb(COLORS["cyan"])
    blue = rgb(COLORS["blue"])

    for yy in range(height):
        for xx in range(width):
            amount = (xx / max(1, width - 1) + yy / max(1, height - 1)) / 2
            if amount < 0.55:
                color = mix(aqua, cyan, amount / 0.55)
            else:
                color = mix(cyan, blue, (amount - 0.55) / 0.45)
            pixels[xx, yy] = (*color, 255)

    base.paste(fill, (x, y), mask.crop((x, y, x + width, y + height)))


def bezier(points, steps=42):
    if len(points) == 3:
        p0, p1, p2 = points
        return [
            (
                (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t**2 * p2[0],
                (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t**2 * p2[1],
            )
            for t in (index / steps for index in range(steps + 1))
        ]

    p0, p1, p2, p3 = points
    return [
        (
            (1 - t) ** 3 * p0[0] + 3 * (1 - t) ** 2 * t * p1[0] + 3 * (1 - t) * t**2 * p2[0] + t**3 * p3[0],
            (1 - t) ** 3 * p0[1] + 3 * (1 - t) ** 2 * t * p1[1] + 3 * (1 - t) * t**2 * p2[1] + t**3 * p3[1],
        )
        for t in (index / steps for index in range(steps + 1))
    ]


def draw_round_curve(draw, points, fill, width):
    rounded = [(round(x), round(y)) for x, y in points]
    draw.line(rounded, fill=fill, width=width, joint="curve")
    radius = width / 2
    for x, y in (rounded[0], rounded[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)


def draw_mark(base, box):
    draw = ImageDraw.Draw(base)
    x, y, width, height = box
    cx = x + width * 0.50
    cy = y + height * 0.50
    mark = min(width, height) * 0.68
    left = round(cx - mark / 2)
    top = round(cy - mark / 2)
    right = round(cx + mark / 2)
    bottom = round(cy + mark / 2)
    stroke = max(4, round(mark * 0.065))
    radius = round(mark * 0.25)

    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (left + stroke, top + stroke * 2, right + stroke, bottom + stroke * 2),
        radius=radius,
        fill=(0, 0, 0, 80),
    )
    base.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(max(2, round(mark * 0.08)))))

    draw.rounded_rectangle(
        (left + stroke, top + stroke, right - stroke, bottom - stroke),
        radius=round(radius * 0.78),
        fill=rgb(COLORS["badge"]) + (246,),
    )

    mask = Image.new("L", base.size, 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle((left, top, right, bottom), radius=radius, outline=255, width=stroke)
    gradient_fill(
        base,
        mask,
        (
            max(0, left - stroke),
            max(0, top - stroke),
            min(base.width, round(mark + stroke * 2)),
            min(base.height, round(mark + stroke * 2)),
        ),
    )

    stream = bezier(
        [
            (left + mark * 0.17, top + mark * 0.70),
            (left + mark * 0.35, top + mark * 0.38),
            (left + mark * 0.62, top + mark * 0.42),
            (left + mark * 0.84, top + mark * 0.47),
        ]
    )
    for extra, alpha in ((round(mark * 0.13), 32), (round(mark * 0.075), 52)):
        draw_round_curve(draw, stream, rgb(COLORS["cyan"]) + (alpha,), round(mark * 0.085) + extra)
    draw_round_curve(draw, stream, rgb(COLORS["cyan"]) + (245,), max(5, round(mark * 0.085)))

    highlight = bezier(
        [
            (left + mark * 0.20, top + mark * 0.48),
            (left + mark * 0.42, top + mark * 0.34),
            (left + mark * 0.66, top + mark * 0.36),
            (left + mark * 0.84, top + mark * 0.43),
        ]
    )
    draw_round_curve(draw, highlight, (235, 250, 255, 224), max(4, round(mark * 0.052)))

    forward = bezier(
        [
            (left + mark * 0.67, top + mark * 0.32),
            (left + mark * 0.82, top + mark * 0.36),
            (left + mark * 0.92, top + mark * 0.44),
            (left + mark * 0.70, top + mark * 0.57),
        ]
    )
    draw_round_curve(draw, forward, rgb(COLORS["aqua"]) + (248,), max(4, round(mark * 0.058)))

    jellyfin_memory = bezier(
        [
            (left + mark * 0.24, top + mark * 0.18),
            (left + mark * 0.43, top + mark * 0.10),
            (left + mark * 0.58, top + mark * 0.10),
            (left + mark * 0.76, top + mark * 0.18),
        ]
    )
    draw_round_curve(draw, jellyfin_memory, (235, 250, 255, 50), max(2, round(mark * 0.030)))

    return base


def render_mark(size, scale=3):
    large_size = (size[0] * scale, size[1] * scale)
    large = Image.new("RGBA", large_size, (0, 0, 0, 0))
    draw_mark(large, (0, 0, large.width, large.height))
    return large.resize(size, Image.Resampling.LANCZOS)


def draw_wordmark(base, box):
    draw = ImageDraw.Draw(base)
    x, y, width, height = box
    padding = max(2, round(height * 0.05))
    mark_size = round(height * 0.56)
    mark = render_mark((mark_size, mark_size), scale=4)
    mark_x = round(x + padding)
    mark_y = round(y + (height - mark_size) / 2)
    base.alpha_composite(mark, (mark_x, mark_y))

    text = "WatermelonFin"
    text_x = mark_x + mark_size + round(height * 0.10)
    available_width = max(8, round(x + width - padding - text_x))
    font_size = max(7, round(height * 0.30))
    text_font = font(font_size, bold=True)
    while font_size > 7 and draw.textbbox((0, 0), text, font=text_font)[2] > available_width:
        font_size -= 1
        text_font = font(font_size, bold=True)
    text_y = y + height * 0.50
    draw.text((text_x, text_y), text, anchor="lm", font=text_font, fill=(255, 255, 255, 255))
    return base


def save_logo_assets(mark, wordmark):
    logo_dir = ASSETS / "watermelonfin-logo.imageset"
    for filename, size in LOGO_TARGETS:
        image = Image.new("RGBA", size, (0, 0, 0, 0))
        paste_fitted(
            image,
            mark,
            (
                round(size[0] * 0.02),
                round(size[1] * 0.03),
                round(size[0] * 0.19),
                round(size[1] * 0.94),
            ),
            shadow=True,
        )
        paste_fitted(
            image,
            wordmark,
            (
                round(size[0] * 0.24),
                round(size[1] * 0.22),
                round(size[0] * 0.72),
                round(size[1] * 0.56),
            ),
            shadow=True,
        )
        image.save(logo_dir / filename)


def save_ios_assets(mark):
    # Use the same approved source mark as tvOS, with an opaque square icon.
    icon = brand_background((1024, 1024))
    paste_fitted(icon, mark, (104, 104, 816, 816), shadow=True)
    icon_dir = IOS_ASSETS / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    icon.convert("RGB").save(icon_dir / "AppIcon.png")
    logo_dir = IOS_ASSETS / "watermelonfin-logo.imageset"
    logo_dir.mkdir(parents=True, exist_ok=True)
    for filename, _ in LOGO_TARGETS:
        shutil.copy2(ASSETS / "watermelonfin-logo.imageset" / filename, logo_dir / filename)


def save_icon_assets(mark):
    for relative, size, mode in ICON_TARGETS:
        target = BRAND / relative
        if "back" in target.name:
            image = brand_background(size).convert("RGB")
        else:
            image = Image.new("RGBA", size, (0, 0, 0, 0))
            paste_fitted(
                image,
                mark,
                (
                    round(size[0] * 0.24),
                    round(size[1] * 0.09),
                    round(size[0] * 0.52),
                    round(size[1] * 0.82),
                ),
                shadow=True,
            )
        image.convert(mode).save(target)


def save_top_shelf_assets(mark, wordmark):
    for relative, size in TOP_SHELF_TARGETS:
        image = brand_background(size)
        paste_fitted(
            image,
            mark,
            (
                round(size[0] * 0.15),
                round(size[1] * 0.17),
                round(size[0] * 0.20),
                round(size[1] * 0.66),
            ),
            shadow=True,
        )
        paste_fitted(
            image,
            wordmark,
            (
                round(size[0] * 0.40),
                round(size[1] * 0.37),
                round(size[0] * 0.38),
                round(size[1] * 0.18),
            ),
            shadow=True,
        )
        image.convert("RGB").save(BRAND / relative)


def save_preview(source):
    preview = brand_background((1800, 1100)).convert("RGB")
    draw = ImageDraw.Draw(preview)
    title_font = font(50, bold=True)
    label_font = font(28, bold=True)

    draw.text((80, 62), "WatermelonFin tvOS Asset Set", font=title_font, fill=(255, 255, 255))

    logo = Image.open(ASSETS / "watermelonfin-logo.imageset/watermelonfin-logo@3x.png").convert("RGBA")
    preview.paste(logo, (80, 150), logo)
    draw.text((80, 355), "In-app logo", font=label_font, fill=(222, 234, 244))

    back = Image.open(BRAND / "App Icon.imagestack/Back.imagestacklayer/Content.imageset/800x480-back.png").resize((600, 360))
    front = Image.open(BRAND / "App Icon.imagestack/Front.imagestacklayer/Content.imageset/800x480-front.png").resize((600, 360)).convert("RGBA")
    preview.paste(back, (80, 430))
    preview.paste(front, (80, 430), front)
    draw.text((80, 810), "Layered tvOS icon", font=label_font, fill=(222, 234, 244))

    shelf = Image.open(BRAND / "Top Shelf Image.imageset/top-shelf-1920x720.png").resize((960, 360))
    preview.paste(shelf, (760, 150))
    draw.text((760, 530), "Top shelf", font=label_font, fill=(222, 234, 244))

    wide = Image.open(BRAND / "Top Shelf Image Wide.imageset/top-shelf-wide-2320x720.png").resize((1160, 360))
    preview.paste(wide, (560, 650))
    draw.text((560, 1030), "Wide top shelf", font=label_font, fill=(222, 234, 244))
    preview.save(PREVIEW, quality=95)


def parse_args():
    parser = argparse.ArgumentParser(description="Generate WatermelonFin iOS/tvOS logos, app icons, and Top Shelf assets.")
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_SOURCE,
        help="Path to the source PNG/JPG/SVG artwork. SVG input must contain an embedded raster image.",
    )
    parser.add_argument("--ios-only", action="store_true", help="Regenerate only the iPhone/iPad icon and copy the current tvOS wordmark assets.")
    return parser.parse_args()


def main():
    args = parse_args()
    mark, wordmark = source_pieces(args.source)
    if args.ios_only:
        save_ios_assets(mark)
        print("Generated WatermelonFin iPhone/iPad assets.")
        return
    save_logo_assets(mark, wordmark)
    save_ios_assets(mark)
    save_icon_assets(mark)
    save_top_shelf_assets(mark, wordmark)
    save_preview(args.source)
    print("Generated WatermelonFin logo and tvOS assets.")


if __name__ == "__main__":
    main()
