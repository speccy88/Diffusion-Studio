"""Download public model files and report completed files to the app."""

import sys
from pathlib import Path

from huggingface_hub import snapshot_download
from tqdm import tqdm


class FileProgress(tqdm):
    def display(self, msg=None, pos=None):
        if self.total and self.unit != "B":
            print(f"STUDIO_FILES:{self.n} {self.total}", flush=True)


model = sys.argv[1]
if model == "dreamLite":
    snapshot = snapshot_download(
        "carlofkl/DreamLite-mobile", revision="diffusers", tqdm_class=FileProgress,
    )
    marker = Path(sys.argv[2])
    pending = marker.with_suffix(".pending")
    pending.write_text(snapshot + "\n", encoding="utf-8")
    pending.replace(marker)
elif model == "sanaSprint":
    snapshot_download("Efficient-Large-Model/Sana_Sprint_0.6B_1024px_diffusers", tqdm_class=FileProgress)
else:
    raise ValueError(f"Unknown model: {model}")
