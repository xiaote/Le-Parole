#!/usr/bin/env python3
"""Fail fast when the sailing-diagram asset catalog is incomplete or ambiguous."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

from PIL import Image


ASSET_ROOT = Path(__file__).resolve().parents[1] / "Le Parole" / "Assets.xcassets"
ORANGE = (242, 115, 51)
MAX_EDGE = 700


def image_path(imageset: Path) -> Path | None:
    images = sorted(imageset.glob("*.png"))
    return images[0] if len(images) == 1 else None


def contains_badge(path: Path) -> bool:
    with Image.open(path) as source:
        image = source.convert("RGB")
    # The badge is intentionally #F27333.  PNG color management can move that
    # value by a few channels, so allow a small tolerance while still requiring
    # a substantial solid field rather than a single accidental orange pixel.
    return sum(
        all(abs(component - expected) <= 16 for component, expected in zip(pixel, ORANGE))
        for pixel in image.getdata()
    ) >= 100


def main() -> int:
    failures: list[str] = []
    quiz_sets = {path.name.removesuffix("_quiz.imageset"): path for path in ASSET_ROOT.glob("cvc_crop_*_quiz.imageset")}
    full_sets = {path.name.removesuffix("_full.imageset"): path for path in ASSET_ROOT.glob("cvc_crop_*_full.imageset")}

    if len(quiz_sets) != 96 or len(full_sets) != 96:
        failures.append(f"expected 96 quiz and 96 revealed sets; found {len(quiz_sets)} and {len(full_sets)}")

    if quiz_sets.keys() != full_sets.keys():
        failures.append("quiz and revealed asset-set names do not match")

    for identifier in sorted(quiz_sets.keys() & full_sets.keys()):
        quiz = image_path(quiz_sets[identifier])
        full = image_path(full_sets[identifier])
        if quiz is None or full is None:
            failures.append(f"{identifier}: each imageset must contain exactly one PNG")
            continue
        if hashlib.sha256(quiz.read_bytes()).digest() == hashlib.sha256(full.read_bytes()).digest():
            failures.append(f"{identifier}: quiz and revealed images are identical")
        with Image.open(quiz) as image:
            if max(image.size) > MAX_EDGE:
                failures.append(f"{identifier}: quiz image {image.size} exceeds {MAX_EDGE}px")
        with Image.open(full) as image:
            if max(image.size) > MAX_EDGE:
                failures.append(f"{identifier}: revealed image {image.size} exceeds {MAX_EDGE}px")
        if not contains_badge(quiz):
            failures.append(f"{identifier}: quiz image has no #F27333 question badge")

    if failures:
        print("Sailing diagram audit failed:", *failures, sep="\n- ")
        return 1
    print("Sailing diagram audit passed: 96 distinct quiz/revealed pairs, all quiz badges present, max edge <= 700px.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
