# Diffusion Studio

A native SwiftUI macOS app for generating and saving images with DreamLite-Mobile and SANA Sprint. Use the model selector above the prompt to switch between them. Your prompt, seed, and DreamLite resolution are retained when switching.

Each generated image is added to the thumbnail strip below the preview. Click a thumbnail or use the previous/next buttons to browse. After clicking the strip, the left/right arrow keys also navigate. **Save PNG…** exports the selected image. Hover over a thumbnail to see its prompt, seed, and resolution.

History is shared across the app's windows and model switches for the current session. Full PNGs are stored in a temporary folder and small thumbnails stay in memory. Quitting clears the session folder. Use **Save PNG…** to keep images permanently. If temporary storage fails, the image is retained in memory so it can still be saved.

DreamLite uses PyTorch/Diffusers on MPS through an automatically managed Python worker and private process pipes. SANA Sprint 0.6B runs inside the app using Apple's Core AI diffusion pipeline. SANA generates 1024 × 1024 images in two steps. The app releases the previous model before loading the selected one.

Requires Apple Silicon, macOS 27 or later, and Xcode 27 to build.

## Install and download models

Download the macOS ARM64 ZIP from [GitHub Releases](https://github.com/speccy88/Diffusion-Studio/releases), extract it, and open **Diffusion Studio.app**. Select a model and click **Download**. The app installs Python and the model dependencies, downloads the weights, and converts SANA to Core AI format. When setup finishes, enter a prompt and click **Generate image**.

Setup needs an internet connection and several gigabytes of storage. The app keeps its runtime and exported SANA bundle in `~/Library/Application Support/Diffusion Studio` and uses the Hugging Face cache for downloaded weights. It also detects existing model assets from source builds and earlier releases. If setup fails, use **Retry download** or **View setup log** in the model panel. See INSTALL.md in the ZIP for macOS opening instructions.

## Build from source

Open `DreamLiteDesktop.xcodeproj` in Xcode 27 and run the **DreamLiteDesktop** scheme on **My Mac**, or build from the repository root in Terminal:

```bash
xcodebuild -project DreamLiteDesktop.xcodeproj -scheme DreamLiteDesktop \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build CONFIGURATION_BUILD_DIR="$PWD/build" build
open "build/Diffusion Studio.app"
```

The macOS app uses `backend/setup-model.sh` and `backend/download-model.py` for in-app setup. The standalone `backend/setup-mac.sh`, `backend/setup-demo.sh`, and `setup-sana.sh` scripts remain available for local development. `backend/server.py` supports a private process pipe and a standalone loopback HTTP API. Use `backend/run-dreamlite.sh` or `backend/run-demo.sh` to launch that API.

To try the demo from a source build, run `./backend/setup-demo.sh` with Python 3.11 available, then quit and reopen the app with `open "build/Diffusion Studio.app" --args --demo`. Select **DreamLite** to generate watermarked demo images. A separate DreamLite Diffusers-branch checkpoint can be selected with the `--model-path /absolute/path/to/checkpoint` launch argument.

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

Run `./package-release.sh` to build the ARM64 app and produce a ZIP and SHA-256 checksum under `build/releases/`. The archive contains the app with its bundled setup resources, installation instructions, and dependency licenses. The packager applies an ad-hoc signature.
