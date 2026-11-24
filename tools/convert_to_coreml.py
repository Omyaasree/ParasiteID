#!/usr/bin/env python3
"""Convert the trained EfficientNetB0 checkpoint to the .mlpackage the iOS app ships.

Reproduces `ios/ParasiteIDApp/ParasiteNits.mlpackage`. The contract it produces is recorded
in docs/MODEL_CARD.md and asserted by ios/ParasiteIDAppTests/ModelContractTests.swift:

    input   image              224x224 RGB, 0-255, no normalisation
    output  nits_probability   one float, P(nits)

The model carries its own Rescaling + Normalization layers, so the Core ML image input is
declared with scale 1.0 and zero bias; the pixels are handed over untouched.

    python3 tools/convert_to_coreml.py EfficientNetB0.keras ios/ParasiteIDApp/ParasiteNits.mlpackage

Requires keras >= 3.15 (the checkpoint does not deserialise under 3.13.x), tensorflow 2.21
and coremltools 9.x. Afterwards, confirm the result really came from the checkpoint:

    python3 tools/verify_coreml_model.py EfficientNetB0.keras ios/ParasiteIDApp/ParasiteNits.mlpackage
"""
import shutil
import sys
import tempfile
from pathlib import Path

IMAGE_SIDE = 224
INPUT_NAME = "image"
OUTPUT_NAME = "nits_probability"
DESCRIPTION = (
    f"ParasiteID nits vs other (EfficientNetB0, {IMAGE_SIDE}x{IMAGE_SIDE} RGB 0-255). "
    f"Output {OUTPUT_NAME}: P(nits); decision threshold 0.5."
)


def main(keras_path, out_path):
    keras_path, out_path = Path(keras_path), Path(out_path)
    if not keras_path.exists():
        sys.exit(f"checkpoint not found: {keras_path}")

    try:
        import coremltools as ct
        import keras
        import tensorflow as tf
    except ImportError as exc:
        sys.exit(f"{exc}\n\npip install 'tensorflow==2.21.*' 'keras>=3.15' 'coremltools>=9.0'")

    if tuple(int(n) for n in keras.__version__.split(".")[:2]) < (3, 15):
        sys.exit(
            f"keras {keras.__version__} cannot load this checkpoint "
            "(VarianceScaling gained input_axes/output_axes in 3.15). Upgrade to keras>=3.15."
        )

    print(f"loading {keras_path} (keras {keras.__version__}, tensorflow {tf.__version__})")
    model = keras.models.load_model(keras_path, compile=False)
    print(f"  parameters: {model.count_params():,}")

    # coremltools converts a TensorFlow SavedModel, not a Keras 3 archive directly.
    saved_model = Path(tempfile.mkdtemp(prefix="parasiteid-savedmodel-"))
    try:
        print("exporting a SavedModel")
        model.export(saved_model)

        print(f"converting with coremltools {ct.__version__}")
        mlmodel = ct.convert(
            str(saved_model),
            source="tensorflow",
            convert_to="mlprogram",
            inputs=[
                ct.ImageType(
                    name=INPUT_NAME,
                    shape=(1, IMAGE_SIDE, IMAGE_SIDE, 3),
                    scale=1.0,                      # the graph rescales; do not do it twice
                    bias=[0.0, 0.0, 0.0],
                    color_layout=ct.colorlayout.RGB,
                )
            ],
            outputs=[ct.TensorType(name=OUTPUT_NAME)],
            compute_precision=ct.precision.FLOAT16,
            minimum_deployment_target=ct.target.iOS17,
        )
    finally:
        shutil.rmtree(saved_model, ignore_errors=True)

    mlmodel.short_description = DESCRIPTION
    mlmodel.input_description[INPUT_NAME] = (
        f"A close-up scalp or comb photo, letterboxed to {IMAGE_SIDE}x{IMAGE_SIDE} on black. "
        "RGB 0-255, not normalised."
    )
    mlmodel.output_description[OUTPUT_NAME] = "P(nits), a raw sigmoid score. Not calibrated."

    if out_path.exists():
        shutil.rmtree(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(out_path))

    total = sum(f.stat().st_size for f in out_path.rglob("*") if f.is_file())
    print(f"\nwrote {out_path} ({total / 1e6:.1f} MB)")
    print("now run: python3 tools/verify_coreml_model.py "
          f"{keras_path} {out_path}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
