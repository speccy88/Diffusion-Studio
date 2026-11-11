# Diffusion Studio 1.0.0

Requires an Apple Silicon Mac running macOS 27 or later. The ZIP includes the compiled app, setup scripts, and dependency licenses. Model weights and Python dependencies are downloaded during setup.

## Install

1. Extract the ZIP and move the entire **Diffusion Studio** folder to its permanent location before setup. Keep the app and setup scripts together inside that folder.
2. Open Terminal in that folder. Prepare either or both models using the commands below.
3. Open **Diffusion Studio.app** and select the prepared model.

The app is ad-hoc signed and has not been notarized by Apple. macOS may require approval in **System Settings → Privacy & Security → Open Anyway** after the first launch attempt. See [Apple's instructions](https://support.apple.com/en-us/102445).

## DreamLite

Install Python 3.11. With Homebrew, run `brew install python@3.11`. Then run:

```bash
./backend/setup-mac.sh
open "Diffusion Studio.app"
```

The first DreamLite generation downloads its model weights. Setup requires an internet connection, and the downloads can take several minutes.

## SANA Sprint

Install Xcode 27 and select its command-line tools. Install `uv` with `brew install uv`. Then run:

```bash
./setup-sana.sh
open "Diffusion Studio.app"
```

This downloads SANA Sprint 0.6B and exports Apple's Core AI model bundle. Allow several gigabytes of free disk space for the model download, export environment, and roughly 2.3 GB exported bundle.

## Try the interface with demo images

With Python 3.11 installed, run:

```bash
./backend/setup-demo.sh
open "Diffusion Studio.app" --args --demo
```

Select DreamLite to generate watermarked demo images. Quit and reopen normally to use the real model after installing its dependencies.

## Session gallery

Each generated image appears in the bottom thumbnail strip. Click a thumbnail, use the previous/next buttons, or click the strip and use the arrow keys. **Save PNG…** exports the selected image. History is shared across model switches and app windows.

Temporary session images are cleared when you quit. Use **Save PNG…** to keep an image permanently.

## Moving the installation

Keep the entire folder together. If you move it after setting up Python, rerun `./backend/setup-mac.sh` in the new location to refresh the environment. The exported SANA bundle stays under `models/` beside the app.

Source and model references are in README.md. Dependency license texts are in Licenses/.
