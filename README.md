# Diffusion Studio

A native SwiftUI macOS app for generating and saving images with DreamLite-Mobile and SANA Sprint. Use the model selector above the prompt to switch between them. Your prompt, seed, and DreamLite resolution are retained when switching.

Each generated image is added to the thumbnail strip below the preview. Click a thumbnail or use the previous/next buttons to browse. After clicking the strip, the left/right arrow keys also navigate. **Save PNG…** exports the selected image. Hover over a thumbnail to see its prompt, seed, and resolution.

History is shared across the app's windows and model switches for the current session. Full PNGs are stored in a temporary folder and small thumbnails stay in memory. Quitting clears the session folder. Use **Save PNG…** to keep images permanently. If temporary storage fails, the image is retained in memory so it can still be saved.

DreamLite uses PyTorch/Diffusers on MPS through an automatically managed Python worker and private process pipes. SANA Sprint 0.6B runs inside the app using Apple's Core AI diffusion pipeline. SANA generates 1024 × 1024 images in two steps. The app releases the previous model before loading the selected one.

Requires Apple Silicon, macOS 27 or later, and Xcode 27 to build.

## Download a release

Download the macOS ARM64 ZIP from [GitHub Releases](https://github.com/speccy88/Diffusion-Studio/releases). It contains the compiled app and setup scripts. Follow the included INSTALL.md to prepare DreamLite or SANA Sprint. Model weights are downloaded during setup. Release builds use dependencies beside the app and are ad-hoc signed, without Apple notarization.

The DreamLite pipeline has a 0.39B-parameter UNet; the full system additionally loads a Qwen vision-language text encoder and other components. On an M2 Mac with 16 GB RAM, memory/performance can be a constraint. The upstream iPhone 17 Pro benchmark does not predict macOS PyTorch/MPS performance.

## Build and launch

Clone this repository, then follow the setup instructions below for the model you want to use. You can also install the demo environment to try the app without downloading weights.

Open `DreamLiteDesktop.xcodeproj` in Xcode and run the **DreamLiteDesktop** scheme on **My Mac**, or build from the repository root in Terminal:

```bash
xcodebuild -project DreamLiteDesktop.xcodeproj -scheme DreamLiteDesktop \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build CONFIGURATION_BUILD_DIR="$PWD/build" build
open "build/Diffusion Studio.app"
```

Choose a model and click **Generate image**. The app uses the Python environment in this project's `backend/.venv` for DreamLite and the exported Core AI assets in `models/Sana_Sprint_0.6B_1024px_diffusers` for SANA. If you move the project folder, rebuild the app from its new location.

## Contents

- `DreamLiteDesktop.xcodeproj`: open directly in Xcode.
- `DreamLiteDesktop/`: native SwiftUI frontend.
- `setup-sana.sh`: download and export SANA Sprint using Apple's pinned Core AI conversion tools.
- `backend/server.py`: Python worker with DreamLite-Mobile and demo modes. The command-line launchers can also start it as a standalone HTTP API.
- `backend/setup-demo.sh`: install only Pillow to test the UI quickly.
- `backend/setup-mac.sh`: install the complete Python inference environment on macOS.
- `backend/run-demo.sh`: launch the standalone demo HTTP API.
- `backend/run-dreamlite.sh`: launch the standalone DreamLite-Mobile HTTP API.
- `tests/`: demo tests for the process pipes and HTTP API.

## Quick start: test the GUI without downloading weights

1. Install Python 3.11 if needed, then run `./backend/setup-demo.sh` from the project folder to install Pillow.
2. Set `--demo` as a launch argument in the Xcode scheme. For the Terminal build, quit the app and run `open "build/Diffusion Studio.app" --args --demo`.
3. Select **DreamLite**, enter text, and click **Generate image**. Demo images are watermarked. The demo flag applies to DreamLite.

## Run the actual DreamLite-Mobile model

1. From the `backend` directory, run:

   ```bash
   ./setup-mac.sh
   ```

   The setup installs PyTorch, TorchVision, `transformers==4.57.3`, and `diffusers==0.39.0`. Diffusers 0.39.0 includes DreamLite and shares a compatible Hugging Face Hub version with the Transformers pin. The model card documents visual artifacts with `transformers>=5.0`.
2. Launch the app, select **DreamLite**, and click **Generate image**.
3. The first generation downloads the DreamLite-Mobile `diffusers` revision from Hugging Face if needed and loads it on the Apple GPU. The download can take several minutes.

If you have a separate copy of the **Diffusers branch** weights, quit the app and launch it from the project folder with:

```bash
open "build/Diffusion Studio.app" --args --model-path /absolute/path/to/DreamLite-mobile-diffusers
```

Do **not** point this implementation at model weights downloaded from the repository's `main` branch: the checkpoint configurations differ.

## Prepare SANA Sprint

Install `uv`, then run `./setup-sana.sh` once from the project folder. It downloads SANA Sprint 0.6B and exports Apple's compressed Core AI bundle with INT8 transformer weights and an INT4 text encoder. It uses its own export environment under `.build/coreai-models`.

The app and export script use Apple `coreai-models` revision `e7b356c574b71f994ad0ea8341ac907534b3e337`. Swift package dependencies resolve through Xcode. Once setup finishes, select **SANA Sprint** in the app.

## Troubleshooting

- **Python worker could not start:** run `./backend/setup-mac.sh` from the project folder. If the project moved, rebuild the app.
- **SANA assets missing:** run `./setup-sana.sh` from the project folder.
- **MPS unavailable:** confirm Apple Silicon and an MPS-enabled PyTorch install; run `python3 -c 'import torch; print(torch.backends.mps.is_available())'` in `.venv`.
- **Out of memory:** close other memory-heavy apps, try 512 × 512 first; the 0.39B parameter figure only describes the UNet, not the complete pipeline. Prefer the upstream Core ML/MLX deployment for efficiency.
- **Unsupported operations:** the worker enables `PYTORCH_ENABLE_MPS_FALLBACK=1` so PyTorch can run some operations on the CPU when an MPS kernel is unavailable.
- **Model import errors:** rerun `./setup-mac.sh` to install compatible Diffusers and Transformers releases.
- **Initial generation fails:** check the error in the app. Xcode shows worker diagnostics in its console when you launch the app from there.

## Security and licensing

DreamLite exchanges prompts and images through private pipes. SANA uses native calls inside the app. The optional standalone DreamLite HTTP API listens on `127.0.0.1:8766` for local development.

SwiftUI frontend and local backend glue are newly authored for this demo. The project does not bundle or redistribute upstream DreamLite source files or model weights. Respect the [DreamLite model license](https://github.com/ByteVisionLab/DreamLite/blob/main/WEIGHTS_LICENSE) and [original project](https://github.com/ByteVisionLab/DreamLite).

SANA Sprint's model card lists Apache 2.0. Apple's Core AI pipeline is distributed under BSD-3-Clause through the Swift package dependency. See the [model card](https://huggingface.co/Efficient-Large-Model/Sana_Sprint_0.6B_1024px_diffusers) and [pipeline license](https://github.com/apple/coreai-models/blob/e7b356c574b71f994ad0ea8341ac907534b3e337/LICENSE).

## References

- [DreamLite official repository](https://github.com/ByteVisionLab/DreamLite)
- [DreamLite iOS Core ML/MLX deployment](https://github.com/ByteVisionLab/DreamLite/blob/main/deploy/README.md)
- [DreamLite-Mobile model card](https://huggingface.co/carlofkl/DreamLite-mobile)
- [Apple's SANA Sprint Core AI integration](https://github.com/apple/coreai-models/blob/e7b356c574b71f994ad0ea8341ac907534b3e337/models/sana/README.md)
- [SANA Sprint 0.6B model card](https://huggingface.co/Efficient-Large-Model/Sana_Sprint_0.6B_1024px_diffusers)

## Testing

Run `backend/.venv/bin/python3 -m unittest discover -s tests -v` from the project root to test the demo worker and HTTP API. Leave port 8766 free for the HTTP tests.

Run the session gallery checks from the project root:

```bash
mkdir -p build
xcrun swiftc -parse-as-library DreamLiteDesktop/SessionGallery.swift tests/test_gallery.swift -o build/gallery-tests
build/gallery-tests
```

## Package a release

Run `./package-release.sh` to build the ARM64 app and produce a ZIP and SHA-256 checksum under `build/releases/`. The archive contains setup scripts, installation instructions, and dependency licenses. The packager configures dependency paths relative to the app's folder and applies an ad-hoc signature.
