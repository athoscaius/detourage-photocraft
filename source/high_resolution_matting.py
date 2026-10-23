#!/usr/bin/env python3
"""Offline BiRefNet matting. Invoked only by the native, dimension-checked engine.

Official model: ZhengPeng7/BiRefNet-matting, MIT, epoch 100, 1024 square.
No remote model code, network, thresholding, min/max contrast stretch or source alpha.
The native engine applies source alpha exactly once after receiving this coverage.
"""
import argparse
from collections import deque
import json
import os
from pathlib import Path
import sys
import time

import numpy as np
from PIL import Image, ImageFilter, ImageOps
import onnxruntime as ort

MODEL_SHA256 = "6065d27c615ea27308f5b88598dd8db116eb07436c7a323ca40d13b2866c309e"


def person_context(alpha, guide):
    """Keep model components anchored to a person, including nearby held items.

    This gate chooses components, never thresholds the returned soft matte. A
    generous margin preserves flyaway hairs and disconnected small accessories.
    It does not expand the subject's alpha or fill holes in the model prediction.
    """
    size = (512, 512)
    coarse = np.asarray(Image.fromarray(alpha).resize(size, Image.Resampling.BILINEAR))
    seed = np.asarray(guide.resize(size, Image.Resampling.BILINEAR)) > 32
    support = coarse > .02
    seen = np.zeros(support.shape, dtype=bool)
    components, anchors = [], []
    for y, x in zip(*np.nonzero(support)):
        if seen[y, x]:
            continue
        todo = deque([(int(y), int(x))])
        seen[y, x] = True
        points = []
        hits = 0
        while todo:
            cy, cx = todo.popleft()
            points.append((cy, cx))
            hits += int(seed[cy, cx])
            for ny, nx in ((cy-1,cx),(cy+1,cx),(cy,cx-1),(cy,cx+1)):
                if 0 <= ny < 512 and 0 <= nx < 512 and support[ny,nx] and not seen[ny,nx]:
                    seen[ny,nx] = True
                    todo.append((ny,nx))
        points = np.asarray(points)
        box = (points[:,1].min(), points[:,0].min(), points[:,1].max(), points[:,0].max())
        anchored = hits >= max(2, len(points) * .001)
        components.append((points, box, anchored))
        if anchored:
            anchors.append(box)
    if not anchors:
        raise ValueError("Le modèle n’a pas retrouvé la personne dans le premier plan.")
    keep = np.zeros((512,512), dtype=np.uint8)
    dropped = False
    for points, box, anchored in components:
        # A separated glove, lock of hair or held object may have a tiny gap.
        nearby = any(max(0, a[0]-box[2], box[0]-a[2]) ** 2 +
                     max(0, a[1]-box[3], box[1]-a[3]) ** 2 <= 16 ** 2 for a in anchors)
        if anchored or nearby:
            keep[points[:,0],points[:,1]] = 255
        else:
            dropped = True
    if not dropped:
        return alpha
    gate = Image.fromarray(keep).filter(ImageFilter.MaxFilter(9))
    # The gate is deliberately larger than every kept component, so the model's
    # soft border values survive unchanged. It only suppresses distant objects.
    return alpha * (np.asarray(gate.resize((alpha.shape[1],alpha.shape[0]), Image.Resampling.NEAREST)) / 255)


def predict(input_path, guide_path, model_path):
    ort.disable_telemetry_events()
    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    options.inter_op_num_threads = 1
    options.enable_cpu_mem_arena = False
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_EXTENDED
    options.log_severity_level = 3
    session = ort.InferenceSession(str(model_path), sess_options=options, providers=["CPUExecutionProvider"])
    with Image.open(input_path) as raw:
        image = ImageOps.exif_transpose(raw).convert("RGB")
    rgb = np.asarray(image.resize((1024,1024), Image.Resampling.BICUBIC), dtype=np.float32) / 255
    rgb -= np.array([.485,.456,.406],dtype=np.float32)
    rgb /= np.array([.229,.224,.225],dtype=np.float32)
    tensor = np.ascontiguousarray(rgb.transpose(2,0,1)[None])
    logits = session.run(None, {session.get_inputs()[0].name: tensor})[-1].squeeze()
    if logits.shape != (1024,1024) or not np.isfinite(logits).all():
        raise ValueError("Sortie du modèle de matting invalide.")
    alpha = 1 / (1 + np.exp(-np.clip(logits,-80,80)))
    if guide_path:
        with Image.open(guide_path) as guide:
            alpha = person_context(alpha,guide.convert("L"))
    del session, tensor, rgb, logits
    # Resize floating coverage before quantization. No gamma and no normalization
    # by image extrema: a translucent subject must remain translucent.
    coverage = Image.fromarray(alpha.astype(np.float32)).resize(image.size, Image.Resampling.LANCZOS)
    values = np.clip(np.asarray(coverage),0,1)
    if not np.any(values > .01):
        raise ValueError("Le masque du sujet est vide.")
    return Image.fromarray(np.rint(values*255).astype(np.uint8))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--mask", required=True, type=Path)
    parser.add_argument("--guide", type=Path)
    args = parser.parse_args()
    start = time.monotonic()
    model = Path(__file__).resolve().parent / "models/BiRefNet-matting-epoch_100.onnx"
    mask = predict(args.input,args.guide,model)
    temporary = args.mask.with_name(args.mask.name + ".partial")
    try:
        mask.save(temporary,format="PNG")
        os.replace(temporary,args.mask)
    finally:
        temporary.unlink(missing_ok=True)
    print(json.dumps({"model":"BiRefNet-matting-epoch_100","inferenceSize":1024,"seconds":time.monotonic()-start}))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("Matting haute définition : " + str(error), file=sys.stderr)
        sys.exit(1)
