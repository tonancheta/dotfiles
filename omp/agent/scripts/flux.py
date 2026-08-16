#!/usr/bin/env python3
"""Generate an image with FLUX.1 on NVIDIA Build and save it locally.

This is a standalone script rather than an OMP model/agent because NVIDIA's
FLUX.1 is served through the Visual GenAI (NIM) REST image API, not an
OpenAI-compatible chat endpoint. OMP's models.yml and task-routing agents only
handle chat/completion models, and the built-in generate_image tool has no
NVIDIA provider, so image generation lives here and is invoked via /flux.

Endpoint:  POST https://ai.api.nvidia.com/v1/genai/<model>
Auth:      Authorization: Bearer $NVIDIA_API_KEY
Response:  { "artifacts": [ { "base64": <JPEG>, "finishReason": ..., "seed": ... } ] }

Requires NVIDIA_API_KEY in the environment (or ~/.omp/agent/.env, which OMP
loads into the environment before running commands).
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

INVOKE_BASE = "https://ai.api.nvidia.com/v1/genai"
STATUS_BASE = "https://api.nvcf.nvidia.com/v2/nvcf/pexec/status"
POLL_TIMEOUT_S = 300
HTTP_TIMEOUT_S = 180


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="flux.py",
        description="Generate an image with FLUX.1 (NVIDIA Build).",
    )
    p.add_argument("prompt", nargs="+", help="Text prompt for the image.")
    p.add_argument("--model", default="black-forest-labs/flux.1-dev",
                   help="NVIDIA image model id (default: %(default)s). "
                        "Use black-forest-labs/flux.1-schnell for a faster draft.")
    p.add_argument("--width", type=int, default=1024,
                   help="Supported: 768,832,896,960,1024,1088,1152,1216,1280,1344.")
    p.add_argument("--height", type=int, default=1024,
                   help="Supported: 768,832,896,960,1024,1088,1152,1216,1280,1344.")
    p.add_argument("--steps", type=int, default=50, help="Diffusion steps (5-100).")
    p.add_argument("--cfg-scale", type=float, default=3.5, dest="cfg_scale",
                   help="Prompt adherence, (1.0, 9.0].")
    p.add_argument("--seed", type=int, default=0, help="0 = random (default).")
    p.add_argument("--out", default=None,
                   help="Output path. Default: ./flux-<UTC timestamp>.jpg")
    return p.parse_args(argv)


def api_key() -> str:
    key = os.environ.get("NVIDIA_API_KEY", "").strip()
    if not key:
        sys.exit("Error: NVIDIA_API_KEY is not set. "
                 "Set it in your shell (export NVIDIA_API_KEY=nvapi-...) "
                 "or ~/.omp/agent/.env")
    return key


def request(url: str, key: str, payload: dict | None = None, method: str = "POST"):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    return urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S)


def poll(req_id: str, key: str) -> dict:
    """Some NVCF-fronted deployments return 202 + a request id to poll."""
    url = f"{STATUS_BASE}/{req_id}"
    deadline = time.monotonic() + POLL_TIMEOUT_S
    while True:
        if time.monotonic() > deadline:
            sys.exit(f"Error: timed out after {POLL_TIMEOUT_S}s polling {req_id}.")
        resp = request(url, key, method="GET")
        if resp.status == 202:
            time.sleep(2)
            continue
        return json.loads(resp.read().decode())


def generate(args: argparse.Namespace, key: str) -> dict:
    url = f"{INVOKE_BASE}/{args.model}"
    payload = {
        "prompt": " ".join(args.prompt),
        "mode": "base",
        "width": args.width,
        "height": args.height,
        "steps": args.steps,
        "cfg_scale": args.cfg_scale,
        "seed": args.seed,
        "samples": 1,
    }
    try:
        resp = request(url, key, payload)
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        sys.exit(f"Error: NVIDIA API returned HTTP {e.code}: {body}")
    except urllib.error.URLError as e:
        sys.exit(f"Error: could not reach NVIDIA API: {e.reason}")
    if resp.status == 202:
        req_id = resp.headers.get("NVCF-REQID")
        if not req_id:
            sys.exit("Error: got HTTP 202 without an NVCF-REQID header to poll.")
        return poll(req_id, key)
    return json.loads(resp.read().decode())


def save_artifact(result: dict, out_path: Path) -> int:
    """Extract the first image from an ImageResponse and write it. Returns seed."""
    artifacts = result.get("artifacts") or []
    if not artifacts:
        # Tolerate the OpenAI-compatible response shape as a fallback.
        data = result.get("data") or []
        if data and data[0].get("b64_json"):
            artifacts = [{"base64": data[0]["b64_json"],
                          "finishReason": "SUCCESS",
                          "seed": result.get("seed", 0)}]
    if not artifacts:
        sys.exit(f"Error: no image in response: {json.dumps(result)[:500]}")
    art = artifacts[0]
    reason = art.get("finishReason", "SUCCESS")
    if reason == "CONTENT_FILTERED":
        sys.exit("Error: generation was blocked by the content filter.")
    if reason == "ERROR":
        sys.exit("Error: NVIDIA reported an ERROR finish reason.")
    b64 = art.get("base64") or art.get("b64_json")
    if not b64:
        sys.exit("Error: artifact contained no base64 image data.")
    out_path.write_bytes(base64.b64decode(b64))
    return int(art.get("seed", 0) or 0)


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    key = api_key()
    if args.out:
        out_path = Path(args.out).expanduser().resolve()
    else:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        out_path = Path.cwd() / f"flux-{stamp}.jpg"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    result = generate(args, key)
    seed = save_artifact(result, out_path)
    print(f"Saved image: {out_path}")
    print(f"Seed: {seed}")
    print(f"Model: {args.model}  Size: {args.width}x{args.height}  Steps: {args.steps}")


if __name__ == "__main__":
    main()
