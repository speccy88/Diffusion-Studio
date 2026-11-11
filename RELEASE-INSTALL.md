# Install Diffusion Studio

Requires an Apple Silicon Mac running macOS 27 or later.

1. Extract the ZIP and open **Diffusion Studio.app**. You can move the app to Applications.
2. Select **DreamLite** or **SANA Sprint**, then click **Download** for the selected model. Keep the app open while it prepares the runtime, downloads model files, and converts SANA for Apple Core AI if needed.
3. When the prompt editor appears, enter a prompt and click **Generate image**. You can download the other model from the same panel at any time.

Model setup needs an internet connection and several gigabytes of free disk space. The app stores its runtime and exported SANA model in `~/Library/Application Support/Diffusion Studio` and shares Hugging Face's local model cache. If setup fails, the model panel offers **Retry download** and **View setup log**.

The app is ad-hoc signed. Apple notarization is unavailable for this build, so macOS may require approval after the first launch attempt. [Apple's instructions](https://support.apple.com/en-us/102445)

Generated images appear in the session gallery. Use **Save PNG…** to keep an image after quitting.
