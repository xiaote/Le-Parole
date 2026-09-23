#!/usr/bin/env python3
"""Rebuild revealed diagram references without quiz masks or unrelated crops.

The quiz versions may cover a label with an orange question mark. The
corresponding ``*_full`` image is shown after an answer is revealed, so it
must remain an unmasked, useful reference. Keep repairs deterministic so a
future asset refresh cannot accidentally reintroduce a white redaction.
"""

from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1] / "Le Parole" / "Assets.xcassets"
TOOLS_DIR = Path(__file__).resolve().parent
PDF_CANDIDATES = [
    Path.home() / "Downloads" / "Iniziazione alla vela allievoCVC ed2010.pdf",
    Path("/Users/xiaote/Downloads/Iniziazione alla vela allievoCVC ed2010.pdf"),
]
MAX_DIMENSION = 700


def get_pdf_path() -> Path:
    for candidate in PDF_CANDIDATES:
        if candidate.exists():
            return candidate
    raise FileNotFoundError("CVC manual PDF not found in expected locations")


def render_pdf_page(page_index: int) -> Image.Image:
    pdf_path = get_pdf_path()
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        subprocess.run(
            ["swift", str(TOOLS_DIR / "render_pdf_page.swift"), str(pdf_path), str(page_index), tmp_path],
            check=True,
            capture_output=True,
        )
        return Image.open(tmp_path).convert("RGB")
    finally:
        Path(tmp_path).unlink(missing_ok=True)


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


def draw_question_badge(
    image: Image.Image,
    center: tuple[int, int],
    size: tuple[int, int] = (84, 42),
) -> Image.Image:
    result = image.copy()
    draw = ImageDraw.Draw(result)
    width, height = size
    x, y = center
    box = (x - width // 2, y - height // 2, x + width // 2, y + height // 2)
    draw.rounded_rectangle(box, radius=14, fill="#F27333")
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
    # Centers the mainsheet tackle (blocks below boom).
    reference = crop_from("cvc_plate_la_barca", (440, 1080, 700, 1400))
    full = fit(reference)
    save("cvc_crop_bozzello_full", full)
    save("cvc_crop_bozzello_quiz", draw_question_badge(full, (250, 265)))


def repair_gavitello() -> None:
    # Boat approach track and buoy B.
    reference = crop_from("cvc_crop_gavitello_full", (270, 80, 646, 650))
    full = fit(reference)
    save("cvc_crop_gavitello_full", full)
    save("cvc_crop_gavitello_quiz", draw_question_badge(full, (95, 145)))


def repair_bolina() -> None:
    full = fit(crop_from("cvc_plate_andature", (110, 180, 590, 600)))
    save("cvc_crop_bolina_full", full)


def repair_wind_references() -> None:
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


def repair_deriva() -> None:
    # Crop daggerboard/centerboard from bottom-center of cvc_plate_la_barca
    full = fit(crop_from("cvc_plate_la_barca", (430, 1280, 800, 1650)))
    quiz = draw_question_badge(full, (327, 595), (100, 42))
    save("cvc_crop_deriva_full", full)
    save("cvc_crop_deriva_quiz", quiz)


def repair_gassa_damante() -> None:
    # Crop bowline knot and step-by-step instructions from bottom of cvc_plate_nodi
    full = fit(crop_from("cvc_plate_nodi", (80, 1260, 1120, 1630)))
    quiz = draw_question_badge(full, (135, 23), (120, 42))
    save("cvc_crop_gassa_damante_full", full)
    save("cvc_crop_gassa_damante_quiz", quiz)


def repair_nodo_parlato() -> None:
    # Crop clove hitch section from cvc_plate_nodi sharply without bitta
    full = fit(crop_from("cvc_plate_nodi", (80, 960, 680, 1260)))
    quiz = draw_question_badge(full, (74, 56), (100, 42))
    save("cvc_crop_nodo_parlato_full", full)
    save("cvc_crop_nodo_parlato_quiz", quiz)


def repair_dare_volta() -> None:
    # Crop cleating sequence from cvc_plate_manovre_cavi
    full = fit(crop_from("cvc_plate_manovre_cavi", (60, 1020, 1120, 1300)))
    quiz = draw_question_badge(full, (75, 23), (110, 42))
    save("cvc_crop_dare_volta_full", full)
    save("cvc_crop_dare_volta_quiz", quiz)


def repair_traverso() -> None:
    # Crop beam/traverso (Ore 9 & Ore 3) across the boat from cvc_plate_direzioni
    full = fit(crop_from("cvc_plate_direzioni", (70, 520, 780, 760)))
    quiz = draw_question_badge(full, (640, 120), (100, 42))
    save("cvc_crop_traverso_full", full)
    save("cvc_crop_traverso_quiz", quiz)


def repair_sopravvento() -> None:
    # Crop windward diagram from cvc_plate_direzioni
    full = fit(crop_from("cvc_plate_direzioni", (70, 1400, 680, 1660)))
    quiz = draw_question_badge(full, (345, 155), (110, 42))
    save("cvc_crop_sopravvento_full", full)
    save("cvc_crop_sopravvento_quiz", quiz)


def repair_sottovento() -> None:
    # Crop leeward diagram from cvc_plate_direzioni
    full = fit(crop_from("cvc_plate_direzioni", (500, 1400, 1120, 1660)))
    quiz = draw_question_badge(full, (145, 120), (110, 42))
    save("cvc_crop_sottovento_full", full)
    save("cvc_crop_sottovento_quiz", quiz)


def repair_mure_dritta() -> None:
    # Crop tack illustrations (mure a dritta / mure a sinistra) from cvc_plate_direzioni
    full = fit(crop_from("cvc_plate_direzioni", (70, 1290, 1120, 1440)))
    quiz = draw_question_badge(full, (585, 30), (120, 42))
    save("cvc_crop_mure_dritta_full", full)
    save("cvc_crop_mure_dritta_quiz", quiz)


def repair_scuffia() -> None:
    # Crop capsized dinghy diagram and instructions from cvc_plate_scuffia
    full = fit(crop_from("cvc_plate_scuffia", (80, 280, 1100, 600)))
    quiz = draw_question_badge(full, (490, 30), (140, 42))
    save("cvc_crop_scuffia_full", full)
    save("cvc_crop_scuffia_quiz", quiz)


def repair_raddrizzare() -> None:
    # Crop righting diagram (sailor on daggerboard) from cvc_plate_scuffia
    full = fit(crop_from("cvc_plate_scuffia", (80, 590, 1100, 910)))
    quiz = draw_question_badge(full, (455, 20), (140, 42))
    save("cvc_crop_raddrizzare_full", full)
    save("cvc_crop_raddrizzare_quiz", quiz)


def repair_addugliare() -> None:
    # Reposition quiz badge to correctly cover "COGLIERE LE CIME"
    full = Image.open(image_path("cvc_crop_addugliare_full")).convert("RGB")
    quiz = draw_question_badge(full, (86, 51), (120, 42))
    save("cvc_crop_addugliare_quiz", quiz)


def repair_virata() -> None:
    # Render page 16 of CVC manual (index 15) and crop full tacking sequence
    p16 = render_pdf_page(15)
    full = fit(p16.crop((180, 450, 2220, 3250)))
    quiz = draw_question_badge(full, (255, 450), (100, 42))
    save("cvc_crop_virata_full", full)
    save("cvc_crop_virata_quiz", quiz)


def repair_strambata() -> None:
    # Render page 18 of CVC manual (index 17) and crop jibe/strambata sequence
    p18 = render_pdf_page(17)
    full = fit(p18.crop((200, 450, 2200, 3250)))
    quiz = draw_question_badge(full, (115, 638), (110, 42))
    save("cvc_crop_strambata_full", full)
    save("cvc_crop_strambata_quiz", quiz)


def repair_scarroccio_bordeggio() -> None:
    # Render page 13 of CVC manual (index 12) and crop leeway diagram
    p13 = render_pdf_page(12)
    full = fit(p13.crop((100, 2120, 1350, 3220)))
    quiz = draw_question_badge(full, (125, 35), (130, 42))
    save("cvc_crop_scarroccio_bordeggio_full", full)
    save("cvc_crop_scarroccio_bordeggio_quiz", quiz)


def main() -> None:
    print("Repairing revealed and quiz sailing diagram assets...")
    repair_bozzello()
    repair_gavitello()
    repair_bolina()
    repair_wind_references()
    repair_deriva()
    repair_gassa_damante()
    repair_nodo_parlato()
    repair_dare_volta()
    repair_traverso()
    repair_sopravvento()
    repair_sottovento()
    repair_mure_dritta()
    repair_scuffia()
    repair_raddrizzare()
    repair_addugliare()
    repair_virata()
    repair_strambata()
    repair_scarroccio_bordeggio()
    print("All repairs completed successfully.")


if __name__ == "__main__":
    main()
