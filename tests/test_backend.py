import base64
import http.client
import io
import json
import struct
import subprocess
import sys
import time
import unittest
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent / "backend" / "server.py"


class WorkerPipeTests(unittest.TestCase):
    def test_status_and_generation_over_one_process(self):
        requests = [
            {"action": "status"},
            {"action": "generate", "prompt": "A mountain lake\nwith a cabin", "resolution": 768},
            {"action": "generate", "prompt": ""},
            {"action": "generate", "prompt": "A forest", "resolution": 512},
        ]
        result = subprocess.run(
            [sys.executable, "-u", str(BACKEND), "--stdio", "--demo"],
            input="".join(json.dumps(request) + "\n" for request in requests).encode(),
            capture_output=True,
            check=True,
            timeout=15,
        )
        output = io.BytesIO(result.stdout)
        replies = []
        for _ in requests:
            length, = struct.unpack("!I", output.read(4))
            replies.append(json.loads(output.read(length)))
        self.assertEqual(output.read(), b"")
        self.assertEqual(replies[0]["status"]["mode"], "demo")
        self.assertIn("Prompt", replies[2]["error"])
        for reply, size in ((replies[1], 768), (replies[3], 512)):
            png = base64.b64decode(reply["png"], validate=True)
            self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(struct.unpack("!II", png[16:24]), (size, size))


class BackendHTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.process = subprocess.Popen(
            [sys.executable, str(BACKEND), "--demo"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        for _ in range(100):
            try:
                conn = http.client.HTTPConnection("127.0.0.1", 8766, timeout=1)
                conn.request("GET", "/health")
                res = conn.getresponse()
                payload = json.loads(res.read())
                if res.status == 200 and payload["mode"] == "demo":
                    return
            except OSError:
                pass
            time.sleep(0.05)
        raise RuntimeError("Demo backend did not start")

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate()
        cls.process.wait(timeout=3)

    def test_health(self):
        conn = http.client.HTTPConnection("127.0.0.1", 8766)
        conn.request("GET", "/health")
        response = conn.getresponse()
        status = json.loads(response.read())
        self.assertEqual(response.status, 200)
        self.assertEqual(status["mode"], "demo")
        self.assertFalse(status["model_loaded"])

    def test_generates_png_demo(self):
        conn = http.client.HTTPConnection("127.0.0.1", 8766)
        conn.request("POST", "/generate", body=json.dumps({
            "prompt": "A mountain lake", "seed": 42, "resolution": 512
        }), headers={"Content-Type": "application/json"})
        response = conn.getresponse()
        image = response.read()
        self.assertEqual(response.status, 200)
        self.assertEqual(response.getheader("Content-Type"), "image/png")
        self.assertTrue(image.startswith(b"\x89PNG\r\n\x1a\n"))

    def test_validation_rejects_empty_prompt(self):
        conn = http.client.HTTPConnection("127.0.0.1", 8766)
        conn.request("POST", "/generate", body=json.dumps({
            "prompt": "", "seed": 42, "resolution": 512
        }), headers={"Content-Type": "application/json"})
        response = conn.getresponse()
        body = json.loads(response.read())
        self.assertEqual(response.status, 400)
        self.assertIn("Prompt", body["error"])


if __name__ == "__main__":
    unittest.main()
