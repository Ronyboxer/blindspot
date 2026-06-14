"""
Download and convert UFLD TuSimple model to ONNX.

This script downloads the PyTorch weights from the official repository
and converts them to ONNX format compatible with our lane detector.

Usage:
    cd computer_vision
    uv run download_model.py
"""

# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "gdown>=5.0",
#   "torch>=2.0",
#   "onnx>=1.14",
#   "numpy>=1.26",
# ]
# ///

import sys
import shutil
import tempfile
from pathlib import Path

# The official Google Drive ID for tusimple_18.pth from
# https://github.com/cfzd/Ultra-Fast-Lane-Detection
TUSIMPLE_GDRIVE_ID = "1WCYyur5ZaWczH15ecmeDG1vuZMjDQ1XJ"
OUTPUT_PATH = Path("models/tusimple.onnx")


def build_model():
    """Build the UFLD ResNet-18 model architecture."""
    import torch
    import torch.nn as nn
    import torch.nn.functional as F
    from torch import Tensor

    # ResNet BasicBlock
    class BasicBlock(nn.Module):
        expansion = 1

        def __init__(self, inplanes, planes, stride=1, downsample=None):
            super().__init__()
            self.conv1 = nn.Conv2d(inplanes, planes, 3, stride, 1, bias=False)
            self.bn1 = nn.BatchNorm2d(planes)
            self.conv2 = nn.Conv2d(planes, planes, 3, 1, 1, bias=False)
            self.bn2 = nn.BatchNorm2d(planes)
            self.downsample = downsample

        def forward(self, x):
            identity = x
            out = F.relu(self.bn1(self.conv1(x)), inplace=True)
            out = self.bn2(self.conv2(out))
            if self.downsample is not None:
                identity = self.downsample(x)
            out += identity
            return F.relu(out, inplace=True)

    class ResNet(nn.Module):
        def __init__(self, block, layers):
            super().__init__()
            self.inplanes = 64
            self.conv1 = nn.Conv2d(3, 64, 7, 2, 3, bias=False)
            self.bn1 = nn.BatchNorm2d(64)
            self.maxpool = nn.MaxPool2d(3, 2, 1)
            self.layer1 = self._make_layer(block, 64, layers[0])
            self.layer2 = self._make_layer(block, 128, layers[1], stride=2)
            self.layer3 = self._make_layer(block, 256, layers[2], stride=2)
            self.layer4 = self._make_layer(block, 512, layers[3], stride=2)

        def _make_layer(self, block, planes, blocks, stride=1):
            downsample = None
            if stride != 1 or self.inplanes != planes * block.expansion:
                downsample = nn.Sequential(
                    nn.Conv2d(self.inplanes, planes * block.expansion, 1, stride, bias=False),
                    nn.BatchNorm2d(planes * block.expansion),
                )
            layers = [block(self.inplanes, planes, stride, downsample)]
            self.inplanes = planes * block.expansion
            for _ in range(1, blocks):
                layers.append(block(self.inplanes, planes))
            return nn.Sequential(*layers)

        def forward(self, x):
            x = F.relu(self.bn1(self.conv1(x)), inplace=True)
            x = self.maxpool(x)
            x = self.layer1(x)
            x = self.layer2(x)
            x3 = self.layer3(x)
            x4 = self.layer4(x3)
            return x3, x4

    # UFLD classifier head
    class UFLD(nn.Module):
        def __init__(self, griding_num=100, cls_num_per_lane=56, num_lanes=4):
            super().__init__()
            self.griding_num = griding_num
            self.cls_num_per_lane = cls_num_per_lane
            self.num_lanes = num_lanes
            self.total_dim = (griding_num + 1) * cls_num_per_lane * num_lanes

            self.backbone = ResNet(BasicBlock, [2, 2, 2, 2])  # ResNet-18
            self.pool = nn.Conv2d(512, 8, 1)
            self.cls = nn.Sequential(
                nn.Linear(1800, 2048),
                nn.ReLU(inplace=True),
                nn.Linear(2048, self.total_dim),
            )

        def forward(self, x: Tensor) -> Tensor:
            x3, x4 = self.backbone(x)
            fea = self.pool(x4)
            fea = fea.view(fea.size(0), -1)
            out = self.cls(fea)
            # Reshape: (batch, griding_num+1, cls_num_per_lane, num_lanes)
            out = out.view(-1, self.griding_num + 1, self.cls_num_per_lane, self.num_lanes)
            return out

    return UFLD()


def download_weights(gdrive_id: str, dest: Path) -> Path:
    """Download .pth weights from Google Drive using gdown."""
    import gdown

    dest.parent.mkdir(parents=True, exist_ok=True)
    url = f"https://drive.google.com/uc?id={gdrive_id}"
    print(f"[download] Downloading weights from Google Drive ({gdrive_id})...")
    output = str(dest)
    gdown.download(url, output, quiet=False)

    if not dest.exists():
        print("[download] ✗ Download failed!", file=sys.stderr)
        sys.exit(1)

    print(f"[download] ✓ Saved to {dest} ({dest.stat().st_size / 1e6:.1f} MB)")
    return dest


def convert_to_onnx(pth_path: Path, onnx_path: Path):
    """Convert PyTorch weights to ONNX."""
    import torch
    import onnx

    print(f"[convert] Loading PyTorch weights from {pth_path}...")

    model = build_model()

    # Load state dict (handle DataParallel prefix if present)
    state = torch.load(str(pth_path), map_location="cpu", weights_only=False)
    if "model" in state:
        state = state["model"]

    # Remove 'module.' prefix if saved with DataParallel
    cleaned = {}
    for k, v in state.items():
        new_key = k.replace("module.", "")
        cleaned[new_key] = v

    model.load_state_dict(cleaned, strict=False)
    model.eval()
    print("[convert] ✓ Model loaded")

    # Export to ONNX
    dummy = torch.randn(1, 3, 288, 800)
    onnx_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"[convert] Exporting to ONNX at {onnx_path}...")
    torch.onnx.export(
        model,
        dummy,
        str(onnx_path),
        input_names=["input"],
        output_names=["output"],
        opset_version=11,
        dynamic_axes=None,
    )

    # Validate
    onnx_model = onnx.load(str(onnx_path))
    onnx.checker.check_model(onnx_model)
    print(f"[convert] ✓ ONNX model validated ({onnx_path.stat().st_size / 1e6:.1f} MB)")


def main():
    print("=" * 60)
    print("  UFLD TuSimple Model Downloader & Converter")
    print("=" * 60)

    if OUTPUT_PATH.exists():
        print(f"\n[info] Model already exists at {OUTPUT_PATH}")
        print(f"       Size: {OUTPUT_PATH.stat().st_size / 1e6:.1f} MB")
        resp = input("       Overwrite? [y/N] ").strip().lower()
        if resp != "y":
            print("       Skipping.")
            return

    # Step 1: Download PyTorch weights
    with tempfile.TemporaryDirectory() as tmpdir:
        pth_path = Path(tmpdir) / "tusimple_18.pth"
        download_weights(TUSIMPLE_GDRIVE_ID, pth_path)

        # Step 2: Convert to ONNX
        convert_to_onnx(pth_path, OUTPUT_PATH)

    print(f"\n[done] Model ready at: {OUTPUT_PATH}")
    print(f"       Run: uv run main.py --model {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
