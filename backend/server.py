"""Local-only DreamLite-Mobile image-generation backend for Diffusion Studio.

Demo mode is intentionally NOT generative AI, and visibly watermarks images.
Real mode imports DreamLiteMobilePipeline from Diffusers.
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import logging
import os
import struct
import sys
import textwrap
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"  # Do not expose the unauthenticated generation endpoint to the LAN.
PORT = 8766
MODEL_ID = "carlofkl/DreamLite-mobile"


class Engine:
    def __init__(self, demo: bool, model_path: str | None = None):
        self.demo = demo
        self.model_path = model_path or MODEL_ID
        self.pipeline = None
        self.torch = None
        self.lock = threading.Lock()
        self.device = "demo" if demo else "mps"

    def status(self):
        return {
            "mode": "demo" if self.demo else "dreamlite",
            "model_loaded": self.pipeline is not None,
            "device": self.device,
            "model": self.model_path,
        }

    def png(self, prompt: str, resolution: int, seed: int):
        started = time.monotonic()
        output = self.image(prompt, resolution, seed)
        buffer = io.BytesIO()
        output.save(buffer, format="PNG")
        logging.info("Generated %sx%s image in %.1fs", resolution, resolution, time.monotonic() - started)
        return buffer.getvalue()

    def image(self, prompt: str, resolution: int, seed: int):
        with self.lock:
            if self.demo:
                return self._demo_image(prompt, resolution, seed)
            self._load()
            generator = self.torch.Generator(device="cpu").manual_seed(seed)
            # The Mobile checkpoint was distilled for four-step inference.
            result = self.pipeline(
                prompt=prompt,
                width=resolution,
                height=resolution,
                num_inference_steps=4,
                generator=generator,
            )
            return result.images[0]

    def _load(self):
        if self.pipeline is not None:
            return
        import torch
        from diffusers import DreamLiteMobilePipeline

        if not torch.backends.mps.is_available():
            raise RuntimeError(
                "PyTorch MPS is unavailable. Use Apple Silicon with a compatible PyTorch build, "
                "or run --demo to test the GUI."
            )
        self.torch = torch
        logging.info("Loading %s (Diffusers revision) with float16 on MPS", self.model_path)
        kwargs = {"torch_dtype": torch.float16}
        # Local directory supports pre-downloaded model; online ID requires diffusers weights.
        if self.model_path == MODEL_ID:
            kwargs["revision"] = "diffusers"
        pipeline = DreamLiteMobilePipeline.from_pretrained(self.model_path, **kwargs)
        pipeline.to("mps")
        pipeline.set_progress_bar_config(disable=True)
        self.pipeline = pipeline
        logging.info("Model ready")

    @staticmethod
    def _demo_image(prompt: str, resolution: int, seed: int):
        from PIL import Image, ImageDraw, ImageFont

        img = Image.new("RGB", (resolution, resolution))
        pixels = img.load()
        for y in range(resolution):
            for x in range(resolution):
                pixels[x, y] = (
                    int(34 + 40 * x / resolution),
                    int(67 + 55 * y / resolution),
                    int(111 + 40 * (x + y) / (2 * resolution)),
                )
        draw = ImageDraw.Draw(img)
        inset = resolution // 10
        draw.rounded_rectangle((inset, inset, resolution - inset, resolution - inset),
                               radius=resolution // 20, outline="#eff7ff", width=max(2, resolution // 200))
        draw.ellipse((resolution * 0.3, resolution * 0.2, resolution * 0.7, resolution * 0.6),
                     fill="#facb70")
        draw.polygon([(resolution * 0.15, resolution * 0.76),
                      (resolution * 0.46, resolution * 0.43),
                      (resolution * 0.65, resolution * 0.7),
                      (resolution * 0.86, resolution * 0.53),
                      (resolution * 0.89, resolution * 0.79)], fill="#1e5464")
        font = ImageFont.load_default()
        draw.text((inset + 16, inset + 16), "DEMO MODE — NOT AI OUTPUT", fill="white", font=font)
        for i, line in enumerate(textwrap.wrap(prompt, width=42)[:3]):
            draw.text((inset + 16, resolution - inset - 65 + i * 18), line, fill="white", font=font)
        draw.text((inset + 16, resolution - inset - 17), f"Seed: {seed}", fill="white", font=font)
        return img


def generation_parameters(body):
    if not isinstance(body, dict):
        raise ValueError("Request must be a JSON object")
    prompt = body.get("prompt")
    resolution = body.get("resolution", 512)
    seed = body.get("seed", 42)
    if not isinstance(prompt, str) or not (1 <= len(prompt.strip()) <= 2000):
        raise ValueError("Prompt must be between 1 and 2000 characters")
    if type(resolution) is not int or resolution not in (512, 768, 1024):
        raise ValueError("Resolution must be 512, 768, or 1024")
    if type(seed) is not int or not 0 <= seed <= 2**32 - 1:
        raise ValueError("Seed must be an integer between 0 and 4294967295")
    return prompt.strip(), resolution, seed


def worker_reply(engine, line):
    try:
        request = json.loads(line)
        if not isinstance(request, dict):
            raise ValueError("Request must be a JSON object")
        action = request.get("action")
        if action == "status":
            return {"status": engine.status()}
        if action != "generate":
            raise ValueError("Unknown worker action")
        parameters = generation_parameters(request)
    except ValueError as exc:
        return {"error": str(exc)}

    try:
        png = engine.png(*parameters)
        return {"status": engine.status(), "png": base64.b64encode(png).decode("ascii")}
    except Exception as exc:
        logging.exception("Generation error")
        return {"error": f"{type(exc).__name__}: {exc}"}


def run_worker(engine):
    # Reserve the original stdout pipe for replies. Library diagnostics go to stderr,
    # including output written to stdout by native code.
    sys.stdout.flush()
    try:
        with os.fdopen(os.dup(sys.stdout.fileno()), "wb") as replies:
            os.dup2(sys.stderr.fileno(), sys.stdout.fileno())
            for line in sys.stdin.buffer:
                payload = json.dumps(worker_reply(engine, line)).encode("utf-8")
                replies.write(struct.pack("!I", len(payload)))
                replies.write(payload)
                replies.flush()
    except BrokenPipeError:
        return


class Handler(BaseHTTPRequestHandler):
    engine: Engine

    def _json(self, status: int, body: dict):
        payload = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path != "/health":
            self._json(404, {"error": "Not found"})
            return
        self._json(200, self.engine.status())

    def do_POST(self):
        if self.path != "/generate":
            self._json(404, {"error": "Not found"})
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size <= 0 or size > 64 * 1024:
                self._json(413, {"error": "Request body must be between 1 and 65536 bytes"})
                return
            parameters = generation_parameters(json.loads(self.rfile.read(size)))
        except ValueError as exc:
            self._json(400, {"error": str(exc)})
            return

        try:
            png = self.engine.png(*parameters)
        except Exception as exc:
            logging.exception("Generation error")
            self._json(500, {"error": f"{type(exc).__name__}: {exc}"})
            return
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(png)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(png)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stdio", action="store_true", help="Use private process pipes instead of HTTP")
    parser.add_argument("--demo", action="store_true", help="Return clearly labeled test images instead of running DreamLite")
    parser.add_argument("--model-path", default=None, help="Optional local directory with Diffusers-branch weights")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
    engine = Engine(demo=args.demo, model_path=args.model_path)
    if args.stdio:
        run_worker(engine)
        return

    Handler.engine = engine
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    logging.info("Server running at http://%s:%s | mode=%s", HOST, PORT, "DEMO" if args.demo else "DreamLite-Mobile")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
