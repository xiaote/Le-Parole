#!/usr/bin/env python3
"""Rebuild revealed diagram references without quiz masks or unrelated crops.

The quiz versions may cover a label with an orange question mark.  The
corresponding ``*_full`` image is shown after an answer is revealed, so it
must remain an unmasked, useful reference.  Keep repairs deterministic so a
future asset refresh cannot accidentally reintroduce a white redaction.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1] / "Le Parole" / "Assets.xcassets"
MAX_DIMENSION = 700


def image_path(asset_name: str) -> Path:
    images = list((ROOT / f"{asset_name}.imageset").glob("*.png"))
    if len(images) != 1:
        raise RuntimeError(f"Expected one PNG for {asset_name}, found {images}")
    return images[0]


def fit(image: Image.Image) -> Image.Image:
    scale = MAX_DIMENSION / max(image.size)
    if scale == 1:
        return image.copy()
    return image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )


def save(asset_name: str, image: Image.Image) -> None:
    image.convert("RGB").save(image_path(asset_name), optimize=True)


def draw_question_badge(image: Image.Image, center: tuple[int, int]) -> Image.Image:
    result = image.copy()
    draw = ImageDraw.Draw(result)
    width, height = 84, 42
    x, y = center
    box = (x - width // 2, y - height // 2, x + width // 2, y + height // 2)
    draw.rounded_rectangle(box, radius=14, fill="#F9732E")
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 30)
    text_box = draw.textbbox((0, 0), "?", font=font)
    draw.text(
        (x - (text_box[2] - text_box[0]) / 2, y - (text_box[3] - text_box[1]) / 2 - 3),
        "?",
        fill="white",
        font=font,
    )
    return result


def crop_from(asset_name: str, box: tuple[int, int, int, int]) -> Image.Image:
    return Image.open(image_path(asset_name)).convert("RGB").crop(box)


def repair_bozzello() -> None:
    # The previous crop mistakenly showed sail corners.  This one centers the
    # mainsheet tackle (the pair of blocks hanging below the boom).
    reference = crop_from("cvc_plate_la_barca", (440, 1080, 700, 1400))
    full = fit(reference)
    save("cvc_crop_bozzello_full", full)
    save("cvc_crop_bozzello_quiz", draw_question_badge(full, (250, 265)))


def repair_gavitello() -> None:
    # Preserve the boat, its approach track, and buoy B while excluding the
    # old white erase rectangle on the left of the generated crop.
    reference = crop_from("cvc_crop_gavitello_full", (270, 80, 646, 650))
    full = fit(reference)
    save("cvc_crop_gavitello_full", full)
    save("cvc_crop_gavitello_quiz", draw_question_badge(full, (95, 145)))


def repair_virata() -> None:
    # The right edge was a white mask rather than diagram content.
    full = fit(crop_from("cvc_crop_virata_full", (0, 0, 490, 700)))
    quiz = fit(crop_from("cvc_crop_virata_quiz", (0, 0, 490, 700)))
    save("cvc_crop_virata_full", full)
    save("cvc_crop_virata_quiz", quiz)


def repair_bolina() -> None:
    # Restore the title strip that was removed from the revealed reference.
    full = fit(crop_from("cvc_plate_andature", (110, 180, 590, 600)))
    save("cvc_crop_bolina_full", full)


def repair_wind_references() -> None:
    # The source crop is 500 px wide before normalization.  Recreate each
    # revealed wind reference from it; only quiz copies may conceal labels.
    source = Image.open(image_path("cvc_crop_rosa_dei_venti_full")).convert("RGB")
    scale = source.width / 500
    crops = {
        "tramontana": (141, 30, 260, 190),
        "ostro": (141, 185, 260, 195),
        "levante": (240, 110, 260, 190),
        "ponente": (40, 110, 260, 190),
        "maestrale": (45, 40, 260, 200),
        "grecale": (235, 40, 260, 200),
        "libeccio": (45, 165, 260, 200),
        "scirocco": (235, 165, 260, 200),
    }
    for name, (x, y, width, height) in crops.items():
        box = tuple(round(value * scale) for value in (x, y, x + width, y + height))
        save(f"cvc_crop_{name}_full", fit(source.crop(box)))


def main() -> None:
    repair_bozzello()
    repair_gavitello()
    repair_virata()
    repair_bolina()
    repair_wind_references()


if __name__ == "__main__":
    main()
