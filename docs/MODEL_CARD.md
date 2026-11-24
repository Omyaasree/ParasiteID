# Model card: `ParasiteNits.mlpackage`

The single source of truth for what the shipped model is, what it expects, what it returns,
and what it has actually been shown to do. If a number about the model appears in a PR
description, a slide or a poster, it should be traceable to this file.

Last updated 2026-11-23.

---

## 1. Identity and provenance

| | |
|---|---|
| Architecture | EfficientNetB0 (ImageNet weights) + GlobalAveragePooling2D + Dropout(0.3) + Dense(1, sigmoid) |
| Task | Binary: **nits** vs **other** |
| Parameters | 4,050,852 |
| Trained in | `training_resized.ipynb` (branch `modelPruning`), TensorFlow 2.21.0 / Keras 3.15.1 |
| Source checkpoint | `EfficientNetB0.keras`, 40,837,797 bytes, saved 2026-11-09 |
| Converted by | coremltools 9.0, ML Program, fp16 weights, 2026-11-16 |
| Shipped as | `ios/ParasiteIDApp/ParasiteNits.mlpackage`, 8.0 MB |

```
sha256  59325f6ea18e92990cc7063dca9f178b3308c0dc4b26ab6dcd692df783bca117  EfficientNetB0.keras
sha256  5244aee125c684f30e03ddfc498489d92297f768b5ec68b6a7e41416a3e9c3f2  ParasiteNits.mlpackage/Data/com.apple.CoreML/model.mlmodel
sha256  0eaabca3ee712ab501e4f54651588d9b2a890a84cf70e72b64131e385e4312ae  ParasiteNits.mlpackage/Data/com.apple.CoreML/weights/weight.bin
```

The `.mlpackage` is the **dense** model, not one of the lottery-ticket pruned variants:
`tools/verify_coreml_model.py` reports 0.0012% sparsity across the checkpoint's kernels. A
lottery-ticket export would report 10-80%.

`tools/verify_coreml_model.py` proves the two files are the same trained network by searching
`weight.bin` for the fp16 byte pattern of every tensor in the `.keras` archive. On the pair
above it reports **107 exact matches**, including all 81 convolution kernels and the
classifier head. Batch-norm tensors do not appear because coremltools stores derived
scale/offset constants instead.

---

## 2. Input and output contract

This is what `CoreMLImageDetector.swift` is written against. Changing any of it is a breaking
change to the app.

| | |
|---|---|
| Input name | `image` |
| Input type | Image, 224 × 224, RGB, `kCVPixelFormatType_32BGRA` |
| Input range | **0–255, no normalisation** |
| Output name | `nits_probability` |
| Output type | MultiArray, one element |
| Output meaning | P(nits) — a raw sigmoid score |
| Decision threshold | 0.5 |
| Unsure band | 40% ..< 60% (see §6) |

The outcome is decided from the **rounded whole percent** the screen displays, not from the
underlying double, so the number on screen can never contradict the label beside it. Deciding
on the raw value allowed 0.496 to render as "50%" under "No nits detected".

**Do not pre-divide by 255.** The Keras graph carries its own preprocessing — `Rescaling(1/255)`
→ `Normalization(ImageNet mean/variance)` → `Rescaling(1/std)` — and all three survived the
conversion. Scaling the pixels before handing them over applies the division twice.

`ios/ParasiteIDAppTests/ModelContractTests.swift` asserts every row of this table against the
model in the built app bundle, so a re-export that renames an output or changes the input size
fails CI.

---

## 3. Preprocessing: letterbox, settled

**Decision: letterbox (scale to fit, centre on black). Not squash, not centre-crop.**

Earlier notes described the preprocessing as a squash-resize. That was wrong, and the mistake
is worth recording because it is easy to repeat: the notebook reads from `resized/`, whose
images had *already* been padded to 224 × 224 square by the data-prep step
(`PIL.ImageOps.pad`, black, centred). Its `tf.image.resize` call is therefore a no-op, and the
three-way resize comparison in `production_eval.json` returns **byte-identical metrics to 16
decimal places** for squash, centrecrop and letterbox — because all three ran on images that
were already square. That comparison measures nothing.

What does distinguish them is running each mode on the *raw* photos. Measured on the 96
1080×1920 comb frames and 10 non-square negatives:

| resize | comb detected | mean P(nits) | false positives |
|---|---|---|---|
| squash | 96/96 | 0.868 | **2/10** |
| letterbox | 96/96 | 0.908 | **0/10** |
| centrecrop | 96/96 | 0.923 | 1/10 |

Every photo from an iPhone camera is 4:3 or 16:9, so this path is always taken in the app.
Squashing distorts the nits and pushes dandruff over the line.

The app decodes the photo with its longest edge at most **1024 px** before letterboxing, so a
12-megapixel capture never becomes a ~48 MB bitmap on the way to a 224 x 224 input. Re-measured
on the comb set after adding that step: still 96/96 detected, mean P(nits) 0.9017 against
0.9084 without it, lowest frame 0.842. The decode is lossless as far as the model is
concerned.

---

## 4. Training data

Indexed from `resized/`, deduplicated by SHA-256, shuffled with a fixed seed, split
stratified 70 / 15 / 15.

| class | folders |
|---|---|
| nits | `nits/`, `nits/Hair nits/`, `nits/Hair nits train/` |
| other | `Dandruff/`, `Dandruff/Dandruff train/`, `Healthy Scalp/`, `Healthy Scalp/Healthy Scalp train/`, `lice/` |

2,766 labelled images after dedup; the test split is 401 images (150 nits / 251 other).

`nits on comb images/` is **not** in either list. It is held out entirely.

---

## 5. Evaluation

### 5.1 Held-out test split (401 images)

| metric | value |
|---|---|
| accuracy | 0.960 |
| precision | 0.979 |
| recall | **0.913** |
| F1 | 0.945 |
| ROC AUC | 0.992 |

**0.913 recall on 401 held-out images is the number to quote.** Not the comb result below.

### 5.2 Out-of-distribution check: the comb set

96 frames, 96 detected, 1 false positive among 96 negatives. Mean P(nits) 0.897 in the
notebook; 0.902 measured end to end through the shipped Core ML model with the app's own
decode and letterbox.

**This set is genuinely held out.** `tools/check_comb_holdout.py` re-measures it against all
2,672 training-eligible images on disk and reports:

```
exact SHA-256 overlap: 0
perceptual (dhash) Hamming distance to nearest training image:
  min=13  median=17  max=21
  frames within the notebook's near-duplicate radius (<=8): 0 / 96
  closest pair: ezgif-frame-094.jpg <-> Dandruff/Dandruff train/seborrheic_dermatitis_0186_...jpg  dist 13
```

The nearest training image to any comb frame is a *dandruff* photo at distance 13, well
outside the ≤ 8 radius the notebook uses to reject near-duplicates. There is no leakage.

**But 96/96 is still weaker evidence than it looks.** The 96 frames are consecutive frames
extracted from *one video of one comb*. They are not 96 independent observations; they are one
scene, photographed 96 times. The honest reading is "the model handled this scene", not "the
model has 100% recall on comb photos". A second comb, a second lighting setup and a second
phone would each be a new test.

---

## 6. Thresholds and the unsure band

Scores in **0.40 ..< 0.60** report `.unsure` instead of a class. Two reasons:

1. **Conversion drift.** The fp16 Core ML model and the float32 Keras model disagree by up to
   **0.034** in probability (reported in PR #4, measured over 191 images; not reproducible in
   this repo until the evaluation set is committed — see §8). A photo scoring 0.49 in the
   notebook can score 0.52 on device. A bare threshold at 0.5 turns that drift into a flipped
   class. The ±0.10 band is about three times the observed drift.
2. **A narrow negative class.** "Other" was learned from dandruff, healthy scalp and **five**
   lice photos. The model has no class for a blurry frame, a distant shot, an unrelated object
   or a skin condition it has never seen; the sigmoid still returns a number. Scores near the
   line are where those land most often.

`.unsure` is deliberately **not** presented as a negative. The result screen asks for another
photo and says to treat it as no answer.

The band is a mitigation, not calibration. It does not make the score a probability, and it
does not give a confidence interval — see §7.

---

## 7. Limitations

- **The score is not calibrated.** `confidence` is a raw sigmoid output. It is displayed as
  "chance of nits" because that is the least misleading short phrase, but it has not been
  checked against observed frequencies, and it is **not** a confidence interval. `APP_PLAN.md`
  still lists producing a defensible interval as open work.
- **Out-of-distribution input is unhandled beyond the band.** There is no blur check, no
  "is this even a scalp?" gate, and no rejection class.
- **Lice are not a class.** Five lice photos sit inside "other". A photo of live lice may well
  return "No nits detected".
- **One comb, one video.** See §5.2.
- **No device testing yet.** Every number here comes from the simulator or from Python. The
  model has not been run on a physical iPhone.
- **Not a medical device.** Screening aid only.

---

## 8. Reproducing this model

```bash
# 1. Verify the shipped package came from the checkpoint
python3 tools/verify_coreml_model.py EfficientNetB0.keras ios/ParasiteIDApp/ParasiteNits.mlpackage

# 2. Re-check that the comb set never entered training
python3 tools/check_comb_holdout.py .

# 3. Re-convert from scratch (needs tensorflow + coremltools)
python3 tools/convert_to_coreml.py EfficientNetB0.keras ios/ParasiteIDApp/ParasiteNits.mlpackage
```

`EfficientNetB0.keras` is committed at the repo root so step 3 can actually be run. It is a
40 MB binary in plain git; if the repo gains more checkpoints, move them to Git LFS.

**Still missing.** `resized/results/splits.json` and `resized/models/` are not in the repo, so
the §5.1 metrics cannot be recomputed from a clone — the exact test split is not recorded
anywhere. The 0.034 parity figure in §6 has the same problem. Committing `splits.json` and the
parity evaluation set is the next reproducibility fix.

Note that `EfficientNetB0.keras` was saved by Keras 3.15.1 and does **not** load under Keras
3.13.x (`VarianceScaling.__init__() got an unexpected keyword argument 'input_axes'`). Pin
`keras>=3.15` when re-running the conversion.
