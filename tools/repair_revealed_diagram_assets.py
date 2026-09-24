#!/usr/bin/env python3
"""Rebuild sailing-diagram crops (``cvc_crop_<id>_full`` / ``_quiz``) from source.

Every crop listed in ``CROPS`` is regenerated from an ORIGINAL source -- a page of
the CVC manual PDF rendered at a fixed resolution, or, when the PDF is not
available, the matching full plate asset -- never from a previously generated
crop, so running the script twice produces the same files (an earlier,
non-idempotent repair re-cropped its own output and shipped all-black images).

Coordinates
    All boxes are in *plate pixels*: the 1190x1683 space of the
    ``cvc_plate_*`` assets, i.e. 2 px per PDF point. Page ``p`` below is the
    0-based PDF page index. Plates: la_barca=3, nodi=5, scuffia=7,
    direzioni=9, rosa_venti=10, andature=11, manovre_cavi=22, panna=24,
    cabinato=35, winch_stopper=36.

Spec fields (see ``Crop``)
    rows    One or more rows of source boxes ``(page, (x0, y0, x1, y1))``.
            A single box is a plain crop; several rows/boxes are stacked into
            a composite (used to bring a heading next to its picture when the
            manual lays them out side by side).
    badges  Labels to hide in the quiz image. ``(x0, y0, x1, y1)`` covers an
            axis-aligned label; ``(cx, cy, length, thickness, angle)`` covers a
            rotated label (angle in degrees, counter-clockwise). Coordinates
            are page coordinates inside one of the source boxes.
    erase   ``(page, (x0, y0, x1, y1), mode, (sx, sy))`` paints over stray
            fragments of neighbouring content with the colour sampled at
            ``(sx, sy)``. ``mode`` is ``"fill"`` (whole rectangle) or ``"ink"``
            (only low-saturation dark pixels, i.e. black text, so coloured
            drawing outlines crossing the rectangle survive).

Display target (see QuizCardView / VisualChoiceGridView / DiagramCard): the
image is shown scaledToFit in a ~330x210pt region on the card front, ~330x330pt
when expanded, and ~160x175pt in the visual-choice grid, so crops aim for an
aspect ratio between ~0.75 (portrait) and ~1.8 (landscape) with the long side
at 700 px.

Usage: ``python3 tools/repair_revealed_diagram_assets.py [id ...]``
"""

from __future__ import annotations

import math
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1] / "Le Parole" / "Assets.xcassets"
TOOLS_DIR = Path(__file__).resolve().parent
PDF_CANDIDATES = [
    Path.home() / "Downloads" / "Iniziazione alla vela allievoCVC ed2010.pdf",
    Path("/Users/xiaote/Downloads/Iniziazione alla vela allievoCVC ed2010.pdf"),
]
MAX_DIMENSION = 700
PLATE_PX_PER_POINT = 2
BADGE_COLOR = "#F27333"
BADGE_FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
# Plate assets are the same PDF pages rendered at 2 px/pt; used when the PDF is missing.
PAGE_PLATES = {
    3: "cvc_plate_la_barca",
    5: "cvc_plate_nodi",
    7: "cvc_plate_scuffia",
    9: "cvc_plate_direzioni",
    10: "cvc_plate_rosa_venti",
    11: "cvc_plate_andature",
    22: "cvc_plate_manovre_cavi",
    24: "cvc_plate_panna",
    35: "cvc_plate_cabinato",
    36: "cvc_plate_winch_stopper",
}

Box = tuple[int, int, int, int]


@dataclass(frozen=True)
class Crop:
    rows: list[list[tuple[int, Box]]]
    badges: list[tuple] = field(default_factory=list)
    erase: list[tuple] = field(default_factory=list)
    note: str = ""


def box(page: int, x0: int, y0: int, x1: int, y1: int, **kwargs) -> Crop:
    return Crop(rows=[[(page, (x0, y0, x1, y1))]], **kwargs)


# Direzioni plate: the "ORZARE ... / PUGGIARE ..." text column straddles the
# white gutter between the two "mure" panels (left panel ends at x=597, right
# panel starts at x=626). The crops stop at the gutter; these rectangles hug
# the text lines only, so no hull, sheet or wind line is painted over. "ink"
# is used where a rectangle touches a boat, so coloured outlines survive.
_MURE_DRITTA_ERASE = [
    (9, (627, 1114, 657, 1136), "fill", (640, 1195)),  # ORZ|ARE
    (9, (627, 1136, 708, 1158), "ink", (640, 1195)),   # ...ora verso la
    (9, (627, 1158, 702, 1181), "fill", (640, 1195)),  # ...a del vento
    (9, (627, 1208, 665, 1231), "fill", (640, 1195)),  # PUGG|IARE
    (9, (627, 1231, 710, 1276), "fill", (640, 1195)),  # ...ora verso la / alla prove-
    (9, (627, 1276, 683, 1294), "ink", (640, 1195)),   # ...el vento (above the hull)
]
_MURE_SINISTRA_ERASE = [
    (9, (566, 1116, 596, 1136), "fill", (560, 1195)),  # ORZ|ARE
    (9, (512, 1137, 596, 1159), "ink", (560, 1195)),   # portare la pr...
    (9, (516, 1159, 596, 1181), "fill", (560, 1195)),  # provenienz...
    (9, (552, 1210, 596, 1231), "fill", (560, 1195)),  # PUGG|IARE
    (9, (508, 1232, 596, 1275), "fill", (560, 1195)),  # portare la pr... / parte oppost...
    (9, (540, 1275, 596, 1294), "ink", (560, 1195)),   # nienza d... (beside the hull)
]
_ROSA = (10, (590, 146, 1096, 496))
_LA_BARCA_HEAD = (3, (170, 108, 640, 488))
# The fiocco's luff label starts just above the bottom edge of that box.
_LA_BARCA_HEAD_ERASE = [(3, (560, 460, 641, 489), "fill", (620, 440))]
_LA_BARCA_MAINSHEET = (3, (232, 1120, 712, 1440))
_LA_BARCA_FOOT = (3, (58, 700, 488, 968))
_DIREZIONI_COMPASS = (9, (82, 238, 804, 1000))
_ANDATURE = (11, (180, 196, 1000, 906))
# Fragment of the "ANDATURE" heading at the top-left corner of that box.
_ANDATURE_ERASE = [(11, (180, 205, 232, 246), "fill", (200, 260))]
_DIREZIONI_WINDWARD = (9, (240, 1396, 690, 1596))
_DIREZIONI_LUFF = (9, (402, 1066, 800, 1345))

CROPS: dict[str, Crop] = {
    # --- La barca (page 3) -------------------------------------------------
    "albero": box(3, 660, 118, 1110, 760, badges=[(780, 470, 72, 30, 90)]),
    "scotta": Crop(rows=[[_LA_BARCA_MAINSHEET]], badges=[(385, 1225, 466, 1265)]),
    "paranco": Crop(rows=[[_LA_BARCA_MAINSHEET]], badges=[(386, 1141, 467, 1184)]),
    "poppa": box(3, 70, 1245, 385, 1560, badges=[(86, 1354, 166, 1382), (94, 1400, 162, 1438)]),
    "grillo": box(3, 935, 480, 1115, 625, badges=[(1046, 536, 1103, 566)]),
    "mura": Crop(rows=[[_LA_BARCA_FOOT]], badges=[(409, 877, 478, 937)]),
    "bugna": Crop(rows=[[_LA_BARCA_FOOT]], badges=[(77, 921, 195, 963)]),
    "penna": Crop(rows=[[_LA_BARCA_HEAD]], badges=[(421, 145, 547, 192), (492, 273, 615, 315)],
                   erase=_LA_BARCA_HEAD_ERASE),
    "stecca": Crop(rows=[[_LA_BARCA_HEAD]], badges=[(179, 213, 317, 238)], erase=_LA_BARCA_HEAD_ERASE),
    "inferitura": box(3, 300, 180, 700, 700, badges=[(448, 372, 226, 26, -86), (610, 570, 236, 28, -67)]),
    "terzaroli": box(3, 60, 577, 470, 860, badges=[(80, 578, 162, 623), (366, 601, 449, 643), (368, 708, 449, 751)],
                      erase=[(3, (292, 577, 358, 593), "fill", (330, 600))]),  # "Ferzo" label remnant
    # --- I nodi (page 5) ---------------------------------------------------
    "gassa_damante": Crop(rows=[[(5, (176, 1278, 359, 1310))], [(5, (540, 1296, 1012, 1621))]],
                          badges=[(176, 1279, 359, 1309)]),
    "nodo_otto": box(5, 88, 232, 516, 588, badges=[(101, 343, 310, 367)]),
    "nodo_parlato": box(5, 88, 996, 520, 1266, badges=[(101, 999, 182, 1026)]),
    "due_mezzi_colli": box(5, 88, 594, 516, 988, badges=[(101, 698, 368, 724)]),
    "bitta": box(5, 648, 996, 1134, 1266, badges=[(806, 1212, 857, 1239)]),
    # --- Manovre con i cavi (page 22) ------------------------------------
    "dare_volta": Crop(rows=[[(22, (62, 1036, 380, 1094))], [(22, (760, 1072, 1094, 1216))]],
                       badges=[(67, 1036, 373, 1066)]),
    # Title plus the first and last photos of the coiling sequence.
    "addugliare": Crop(rows=[[(22, (58, 132, 300, 167))], [(22, (62, 171, 314, 475)), (22, (854, 171, 1106, 475))]],
                       badges=[(60, 135, 290, 165)]),
    # --- Le direzioni (page 9) ---------------------------------------------
    "a_dritta": Crop(rows=[[_DIREZIONI_COMPASS]], badges=[(626, 419, 758, 459)]),
    "a_sinistra": Crop(rows=[[_DIREZIONI_COMPASS]], badges=[(106, 419, 263, 460)]),
    "mascone": Crop(rows=[[_DIREZIONI_COMPASS]], badges=[(353, 525, 122, 44, 32)]),
    "traverso": Crop(rows=[[_DIREZIONI_COMPASS]],
                     badges=[(84, 628, 268, 672), (617, 625, 803, 668), (226, 723, 366, 768), (524, 721, 666, 768)]),
    "sopravvento": Crop(rows=[[_DIREZIONI_WINDWARD]], badges=[(363, 1550, 130, 34, 17)]),
    "sottovento": Crop(rows=[[_DIREZIONI_WINDWARD]], badges=[(624, 1528, 112, 34, 22)]),
    "orzare": Crop(rows=[[_DIREZIONI_LUFF]], badges=[(563, 1114, 654, 1142)]),
    "poggiare": Crop(rows=[[_DIREZIONI_LUFF]], badges=[(556, 1210, 664, 1233)]),
    "mure_dritta": box(9, 627, 1028, 1136, 1383, badges=[(882, 1330, 1126, 1377)], erase=_MURE_DRITTA_ERASE),
    "mure_sinistra": box(9, 86, 1028, 596, 1383, badges=[(96, 1330, 344, 1377)], erase=_MURE_SINISTRA_ERASE),
    # --- Rosa dei venti / brezze (page 10) ---------------------------------
    "rosa_dei_venti": Crop(rows=[[_ROSA]], badges=[(592, 150, 740, 176)]),
    "tramontana": Crop(rows=[[_ROSA]], badges=[(778, 162, 884, 188)]),
    "grecale": Crop(rows=[[_ROSA]], badges=[(932, 211, 1006, 238)]),
    "levante": Crop(rows=[[_ROSA]], badges=[(972, 316, 1050, 342)]),
    "scirocco": Crop(rows=[[_ROSA]], badges=[(936, 417, 1014, 446)]),
    "ostro": Crop(rows=[[_ROSA]], badges=[(810, 471, 864, 494)]),
    "libeccio": Crop(rows=[[_ROSA]], badges=[(649, 422, 725, 447)]),
    "ponente": Crop(rows=[[_ROSA]], badges=[(612, 316, 694, 342)]),
    "maestrale": Crop(rows=[[_ROSA]], badges=[(636, 211, 725, 234)]),
    "brezza_mare": box(10, 56, 574, 572, 876, badges=[(228, 583, 366, 609)]),
    "brezza_terra": box(10, 583, 574, 1099, 876, badges=[(781, 583, 916, 609)]),
    # --- Andature (page 11) -----------------------------------------------
    "andatura": Crop(rows=[[_ANDATURE]], erase=_ANDATURE_ERASE,
                     badges=[(273, 400, 180, 30, 62), (872, 363, 180, 30, -62),
                             (272, 698, 180, 30, -62), (870, 732, 180, 30, 62)]),
    "bolina": Crop(rows=[[_ANDATURE]], erase=_ANDATURE_ERASE,
                   badges=[(273, 400, 180, 30, 62), (872, 363, 180, 30, -62)]),
    "lasco": Crop(rows=[[_ANDATURE]], erase=_ANDATURE_ERASE,
                  badges=[(463, 569, 505, 596), (520, 646, 76, 24, 56),
                          (654, 569, 696, 596), (640, 644, 76, 24, -56)]),
    "mettere_a_segno": box(11, 612, 1004, 872, 1312, badges=[(631, 1208, 851, 1235)]),
    # --- Scuffia (page 7) ---------------------------------------------------
    "scuffia": Crop(rows=[[(7, (628, 300, 1100, 358))], [(7, (88, 303, 607, 568))]],
                    badges=[(706, 302, 821, 329)]),
    "raddrizzare": Crop(rows=[[(7, (628, 598, 810, 626))], [(7, (88, 574, 607, 1102))]],
                        badges=[(630, 598, 808, 626)]),
    # --- Panna (page 24) ----------------------------------------------------
    "in_panna": Crop(rows=[[(24, (56, 66, 748, 110))], [(24, (56, 205, 748, 625))]],
                     badges=[(58, 70, 212, 106)]),
    # --- Cabinato (page 35) -------------------------------------------------
    "amantiglio": box(35, 75, 700, 700, 1195, badges=[(84, 769, 273, 802)]),
    "mostravento": box(35, 560, 110, 1090, 420, badges=[(964, 167, 1075, 195)]),
    "paterazzo": box(35, 75, 740, 580, 1195, badges=[(84, 928, 178, 956), (82, 1088, 224, 1118)]),
    # --- Winch e stopper (page 36) ---------------------------------------
    "winch": box(36, 580, 146, 1090, 560, badges=[(767, 535, 804, 557)]),
    "stopper": box(36, 55, 1080, 395, 1392, badges=[(82, 1102, 145, 1128)]),
    # --- Other manual pages ---------------------------------------------
    "vento_reale_apparente": Crop(rows=[[(20, (56, 66, 712, 110))], [(20, (56, 380, 712, 762))]],
                                  badges=[(60, 72, 496, 104), (478, 383, 692, 442)]),
    "uomo_in_mare": box(23, 86, 186, 656, 508, badges=[(470, 219, 626, 242)]),
    "gavitello": box(25, 622, 170, 1132, 520, badges=[(760, 270, 831, 293)]),
    "ancora": Crop(rows=[[(40, (56, 498, 400, 530))], [(40, (56, 775, 560, 1115))]],
                   badges=[(162, 500, 277, 530)]),
}

# Crops kept from the previous hand-tuned repair, restated as data. Their
# badges were placed in output pixels of a 700 px image; convert them to page
# coordinates so they follow the same pipeline.
_LEGACY = {
    # id: (page, box, [(center_x, center_y, width, height)] in output px of fit(box))
    "bozzello": (3, (440, 1080, 700, 1400), [(250, 265, 84, 42)]),
    "virata": (15, (90, 225, 1110, 1625), [(255, 450, 100, 42)]),
    "strambata": (17, (100, 225, 1100, 1625), [(115, 638, 110, 42)]),
    "scarroccio_bordeggio": (12, (50, 1060, 675, 1610), [(125, 35, 130, 42)]),
    "deriva": (3, (430, 1280, 800, 1650), [(327, 595, 100, 42)]),
}
for _id, (_page, _box, _badges) in _LEGACY.items():
    _scale = MAX_DIMENSION / max(_box[2] - _box[0], _box[3] - _box[1])
    CROPS[_id] = box(_page, *_box, badges=[
        (round(_box[0] + (cx - w / 2) / _scale), round(_box[1] + (cy - h / 2) / _scale),
         round(_box[0] + (cx + w / 2) / _scale), round(_box[1] + (cy + h / 2) / _scale))
        for cx, cy, w, h in _badges
    ])


# --------------------------------------------------------------------------
# Rendering


def get_pdf_path() -> Path | None:
    for candidate in PDF_CANDIDATES:
        if candidate.exists():
            return candidate
    return None


class PageSource:
    """Renders PDF pages (cached per page and scale); falls back to plate assets."""

    def __init__(self) -> None:
        self.pdf = get_pdf_path()
        self.tmp = Path(tempfile.mkdtemp(prefix="diagram-crops-"))
        self.cache: dict[tuple[int, int], Image.Image] = {}
        self.renderer: list[str] | None = None

    def close(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _renderer(self) -> list[str]:
        if self.renderer is None:
            binary = self.tmp / "render_pdf_page"
            compiled = subprocess.run(
                ["swiftc", "-O", "-o", str(binary), str(TOOLS_DIR / "render_pdf_page.swift")],
                capture_output=True,
            )
            self.renderer = [str(binary)] if compiled.returncode == 0 else ["swift", str(TOOLS_DIR / "render_pdf_page.swift")]
        return self.renderer

    def page(self, index: int, px_per_point: int) -> tuple[Image.Image, float]:
        """Returns the page image and its pixels per plate pixel."""
        if self.pdf is None:
            plate = PAGE_PLATES.get(index)
            if plate is None:
                raise FileNotFoundError(f"CVC manual PDF not found and page {index} has no plate asset")
            return Image.open(image_path(plate)).convert("RGB"), 1.0
        key = (index, px_per_point)
        if key not in self.cache:
            out = self.tmp / f"p{index}_{px_per_point}.png"
            subprocess.run([*self._renderer(), str(self.pdf), str(index), str(out), str(px_per_point)],
                           check=True, capture_output=True)
            self.cache[key] = Image.open(out).convert("RGB")
        return self.cache[key], px_per_point / PLATE_PX_PER_POINT


def image_path(asset_name: str) -> Path:
    images = list((ROOT / f"{asset_name}.imageset").glob("*.png"))
    if len(images) != 1:
        raise RuntimeError(f"Expected one PNG for {asset_name}, found {images}")
    return images[0]


def ensure_imageset(asset_name: str) -> Path:
    folder = ROOT / f"{asset_name}.imageset"
    if not folder.exists():
        folder.mkdir()
        (folder / "Contents.json").write_text(
            '{\n  "images" : [\n    {\n      "filename" : "%s.png",\n      "idiom" : "universal",\n'
            '      "scale" : "1x"\n    },\n    {\n      "idiom" : "universal",\n      "scale" : "2x"\n'
            '    },\n    {\n      "idiom" : "universal",\n      "scale" : "3x"\n    }\n  ],\n'
            '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}' % asset_name
        )
    return folder / f"{asset_name}.png"


def fit(image: Image.Image) -> Image.Image:
    scale = MAX_DIMENSION / max(image.size)
    if scale == 1:
        return image.copy()
    return image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )


def save(asset_name: str, image: Image.Image) -> None:
    image.convert("RGB").save(ensure_imageset(asset_name), optimize=True)


def draw_question_badge(
    image: Image.Image,
    center: tuple[int, int],
    size: tuple[int, int] = (84, 42),
    radius: int = 14,
    font_size: int | None = None,
    angle: float = 0,
) -> Image.Image:
    """Orange rounded badge with an upright white "?", optionally rotated."""
    result = image.copy()
    width, height = size
    x, y = center
    if angle % 180 == 0:
        draw = ImageDraw.Draw(result)
        draw.rounded_rectangle((x - width // 2, y - height // 2, x + width // 2, y + height // 2),
                               radius=radius, fill=BADGE_COLOR)
    else:
        layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle((0, 0, width - 1, height - 1), radius=radius, fill=BADGE_COLOR)
        layer = layer.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
        result.paste(layer, (round(x - layer.width / 2), round(y - layer.height / 2)), layer)
    draw = ImageDraw.Draw(result)
    effective_font_size = font_size or min(30, max(14, min(width, height) - 8))
    font = ImageFont.truetype(BADGE_FONT, effective_font_size)
    text_box = draw.textbbox((0, 0), "?", font=font)
    draw.text(
        (x - (text_box[2] - text_box[0]) / 2, y - (text_box[3] - text_box[1]) / 2 - 3),
        "?",
        fill="white",
        font=font,
    )
    return result


def apply_erase(page: Image.Image, scale: float, rect: Box, mode: str, sample: tuple[int, int]) -> None:
    color = page.getpixel((round(sample[0] * scale), round(sample[1] * scale)))
    x0, y0, x1, y1 = (round(v * scale) for v in rect)
    if mode == "fill":
        ImageDraw.Draw(page).rectangle((x0, y0, x1 - 1, y1 - 1), fill=color)
        return
    # "ink": repaint grey/black text pixels (and their anti-aliased halo, via a
    # 1-px dilation) but keep saturated pixels such as hull outlines, hull fill
    # and blue wind lines.
    region = page.crop((x0, y0, x1, y1))
    brightness = sum(color) / 3
    pixels = region.load()
    ink = {
        (xx, yy)
        for yy in range(region.height)
        for xx in range(region.width)
        if (lambda r, g, b: max(r, g, b) - min(r, g, b) < 35 and (r + g + b) / 3 < brightness - 6)(*pixels[xx, yy])
    }
    for xx, yy in ink:
        for nx in (xx - 1, xx, xx + 1):
            for ny in (yy - 1, yy, yy + 1):
                if 0 <= nx < region.width and 0 <= ny < region.height:
                    r, g, b = pixels[nx, ny]
                    if (nx, ny) in ink or max(r, g, b) - min(r, g, b) < 35:
                        pixels[nx, ny] = color
    page.paste(region, (x0, y0))


def px_per_point_for(spec: Crop) -> int:
    width = max(sum(b[2] - b[0] for _, b in row) for row in spec.rows)
    height = sum(max(b[3] - b[1] for _, b in row) for row in spec.rows)
    needed = MAX_DIMENSION * PLATE_PX_PER_POINT / max(width, height)
    return max(4, min(12, math.ceil(needed * 1.5)))


GAP = 10  # plate px between stacked parts


def build(spec: Crop, source: PageSource) -> tuple[Image.Image, Image.Image]:
    ppp = px_per_point_for(spec)
    pages: dict[int, tuple[Image.Image, float]] = {}
    for row in spec.rows:
        for page_index, _ in row:
            if page_index not in pages:
                image, scale = source.page(page_index, ppp)
                pages[page_index] = (image.copy(), scale)
    for page_index, rect, mode, sample in spec.erase:
        image, scale = pages[page_index]
        apply_erase(image, scale, rect, mode, sample)

    # Lay out rows (plate units), centred horizontally on white.
    row_sizes = [(sum(b[2] - b[0] for _, b in row) + GAP * (len(row) - 1), max(b[3] - b[1] for _, b in row))
                 for row in spec.rows]
    canvas_w = max(w for w, _ in row_sizes)
    canvas_h = sum(h for _, h in row_sizes) + GAP * (len(spec.rows) - 1)
    k = next(iter(pages.values()))[1]
    canvas = Image.new("RGB", (round(canvas_w * k), round(canvas_h * k)), "white")
    placements: list[tuple[int, Box, float, float]] = []  # page, box, offset x/y (plate units)
    y = 0
    for row, (row_w, row_h) in zip(spec.rows, row_sizes):
        x = (canvas_w - row_w) / 2
        for page_index, b in row:
            image, scale = pages[page_index]
            part = image.crop(tuple(round(v * scale) for v in b))
            canvas.paste(part, (round(x * k), round(y * k)))
            placements.append((page_index, b, x - b[0], y - b[1]))
            x += b[2] - b[0] + GAP
        y += row_h + GAP

    full = fit(canvas)
    out_scale = full.width / canvas_w
    quiz = full
    for badge in spec.badges:
        if len(badge) == 4:
            bx0, by0, bx1, by1 = badge
            cx, cy, length, thickness, angle = (bx0 + bx1) / 2, (by0 + by1) / 2, bx1 - bx0, by1 - by0, 0
        else:
            cx, cy, length, thickness, angle = badge
        owner = next(((dx, dy) for _, b, dx, dy in placements if b[0] <= cx <= b[2] and b[1] <= cy <= b[3]), None)
        if owner is None:
            raise ValueError(f"badge {badge} is outside every source box")
        dx, dy = owner
        w = max(40, round(length * out_scale))
        h = max(26, round(thickness * out_scale))
        radius = max(6, min(14, min(w, h) // 3))
        quiz = draw_question_badge(quiz, (round((cx + dx) * out_scale), round((cy + dy) * out_scale)),
                                   (w, h), radius=radius, angle=angle)
    return full, quiz


def main(argv: list[str]) -> int:
    selected = argv or list(CROPS)
    unknown = [name for name in selected if name not in CROPS]
    if unknown:
        print("Unknown crop ids:", ", ".join(unknown))
        return 1
    source = PageSource()
    if source.pdf is None:
        print("CVC manual PDF not found; cropping from plate assets (lower resolution).")
    try:
        for name in selected:
            full, quiz = build(CROPS[name], source)
            save(f"cvc_crop_{name}_full", full)
            save(f"cvc_crop_{name}_quiz", quiz)
            print(f"{name}: {full.width}x{full.height}")
    finally:
        source.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
