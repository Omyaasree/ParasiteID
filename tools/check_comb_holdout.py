#!/usr/bin/env python3
"""Check that no `nits on comb images/` frame leaked into the training folders.

The comb set is the only out-of-distribution evidence the project has, so "were those frames
in training?" decides whether 96/96 means anything. This answers it two ways:

  * exact duplicates, by SHA-256 of the file bytes;
  * near-duplicates, by perceptual difference hash, using the same 8x8 dhash and the same
    Hamming radius (<= 8) the training notebook uses to reject near-duplicate negatives.

    python3 tools/check_comb_holdout.py .

Exit status is 0 when the comb set is clean.
"""
import hashlib
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Mirrors CLASS_DIRS in training_resized.ipynb.
CLASS_DIRS = {
    "nits": ["nits", "nits/Hair nits", "nits/Hair nits train"],
    "other": ["Dandruff", "Dandruff/Dandruff train",
              "Healthy Scalp", "Healthy Scalp/Healthy Scalp train", "lice"],
}
HELD_OUT = "nits on comb images"
NEAR_DUP_MAX_DIST = 8
EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"}


def images(root):
    root = Path(root)
    if not root.is_dir():
        return []
    return [p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in EXTS]


def sha256(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(chunk), b""):
            h.update(block)
    return h.hexdigest()


def dhash(path, size=8):
    with Image.open(path) as im:
        grey = np.asarray(im.convert("L").resize((size + 1, size)), dtype=np.int16)
    return np.packbits(grey[:, 1:] > grey[:, :-1]).tobytes()


def bits(paths):
    packed = b"".join(dhash(p) for p in paths)
    return np.unpackbits(np.frombuffer(packed, dtype=np.uint8)).reshape(len(paths), 64)


def main(root):
    root = Path(root)

    seen, train = set(), []
    for folders in CLASS_DIRS.values():
        for folder in folders:
            for p in images(root / folder):
                if p not in seen:
                    seen.add(p)
                    train.append(p)

    comb = sorted(images(root / HELD_OUT))
    if not comb or not train:
        sys.exit(f"nothing to compare (train={len(train)}, comb={len(comb)}) - wrong root?")

    print(f"training-eligible images: {len(train)}")
    print(f"held-out comb frames    : {len(comb)}")

    train_hashes = {sha256(p) for p in train}
    exact = [p.name for p in comb if sha256(p) in train_hashes]
    print(f"\nexact SHA-256 overlap: {len(exact)}")
    for name in exact[:10]:
        print("   ", name)

    distance = (bits(comb)[:, None, :] != bits(train)[None, :, :]).sum(2)
    nearest = distance.min(1)
    within = int((nearest <= NEAR_DUP_MAX_DIST).sum())
    closest = int(nearest.argmin())

    print("\nperceptual (dhash) Hamming distance to the nearest training image:")
    print(f"  min={nearest.min()}  median={int(np.median(nearest))}  max={nearest.max()}")
    print(f"  frames within the near-duplicate radius (<= {NEAR_DUP_MAX_DIST}): {within} / {len(comb)}")
    print(f"  closest pair: {comb[closest].name} <-> "
          f"{train[int(distance[closest].argmin())].relative_to(root)} "
          f"(distance {int(nearest.min())})")

    clean = not exact and within == 0
    print("\nRESULT:", "the comb set is held out - no leakage"
          if clean else "LEAKAGE - comb frames overlap the training folders")
    return 0 if clean else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
