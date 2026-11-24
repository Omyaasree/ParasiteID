#!/usr/bin/env python3
"""Prove that a .mlpackage was converted from a given .keras checkpoint.

Core ML records no link back to the file it was converted from, so "is the model in the app
the model we evaluated?" is otherwise unanswerable. This checks it directly: every weight
tensor in the .keras archive is re-encoded as fp16 and searched for, byte for byte, inside
the package's weight blob.

It reads the .keras as a zip and the weights with h5py, so it does not need to deserialise
the model and is not affected by the Keras version that saved it.

    python3 tools/verify_coreml_model.py EfficientNetB0.keras ios/ParasiteIDApp/ParasiteNits.mlpackage

Exit status is 0 when the head and the convolution kernels all match.
"""
import sys
import zipfile
from pathlib import Path

import h5py
import numpy as np

# Batch-norm tensors are expected to be absent: coremltools folds gamma/beta/mean/variance
# into derived scale and offset constants, so the raw values never appear in the blob.
EXPECT_MISSING = "batch_normalization"
MIN_ELEMENTS = 16  # tiny tensors collide by chance; they prove nothing either way


def layer_tensors(weights_h5):
    """Yield (path, array) for the model's own weights, skipping optimizer state."""
    out = []

    def walk(group, path=""):
        for key in group:
            item = group[key]
            node = f"{path}/{key}"
            if isinstance(item, h5py.Group):
                walk(item, node)
            elif node.startswith("/layers"):
                out.append((node, np.array(item)))

    walk(weights_h5)
    return out


def to_coreml_layout(a):
    """Keras stores conv kernels HWIO and dense kernels IO; MIL stores OIHW and OI."""
    if a.ndim == 4:
        return np.transpose(a, (3, 2, 0, 1))
    if a.ndim == 2:
        return a.T
    return a


def main(keras_path, package_path):
    keras_path, package_path = Path(keras_path), Path(package_path)
    blob = package_path / "Data/com.apple.CoreML/weights/weight.bin"
    if not blob.exists():
        sys.exit(f"no weight blob at {blob}")
    raw = blob.read_bytes()

    with zipfile.ZipFile(keras_path) as z:
        tmp = package_path.parent / ".weights.h5.tmp"
        tmp.write_bytes(z.read("model.weights.h5"))
    try:
        with h5py.File(tmp, "r") as f:
            tensors = layer_tensors(f)
    finally:
        tmp.unlink(missing_ok=True)

    kernels = np.concatenate([t.ravel().astype(np.float32) for _, t in tensors if t.ndim >= 2])
    sparsity = 100.0 * float((kernels == 0).mean())

    matched = missing = 0
    conv_total = conv_matched = 0
    head_matched = False
    unexpected = []

    for path, a in tensors:
        if a.size < MIN_ELEMENTS:
            continue
        found = raw.find(
            np.ascontiguousarray(to_coreml_layout(a), dtype=np.float16).tobytes()
        ) != -1
        if a.ndim == 4:
            conv_total += 1
            conv_matched += found
        if a.ndim == 2 and a.shape[1] == 1:
            head_matched = head_matched or found
        if found:
            matched += 1
        else:
            missing += 1
            if EXPECT_MISSING not in path:
                unexpected.append((path, a.shape))

    print(f"checkpoint : {keras_path}")
    print(f"package    : {package_path}  ({len(raw):,} bytes of weights)")
    print(f"kernel sparsity: {sparsity:.4f}%  "
          f"({'dense model' if sparsity < 1 else 'PRUNED model'})")
    print(f"tensors matched byte-for-byte as fp16: {matched}  (not found: {missing})")
    print(f"  convolution kernels: {conv_matched}/{conv_total}")
    print(f"  classifier head    : {'yes' if head_matched else 'NO'}")
    if unexpected:
        print(f"  unexpected misses  : {len(unexpected)}")
        for path, shape in unexpected[:10]:
            print(f"    {path} {shape}")

    ok = head_matched and conv_total > 0 and conv_matched == conv_total
    print("\nRESULT:", "the package was converted from this checkpoint"
          if ok else "MISMATCH - these are not the same trained model")
    return 0 if ok else 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
