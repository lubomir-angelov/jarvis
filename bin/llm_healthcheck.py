#!/usr/bin/env python3
"""Check the local OpenAI-compatible model endpoint."""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    url = args.base_url.rstrip("/") + "/models"
    import os
    api_key = os.environ.get("OPENAI_API_KEY", "token-local-dev")
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {api_key}"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        print(f"Model endpoint is not ready: {exc}")
        return 1

    models = [item.get("id", "<unknown>") for item in payload.get("data", [])]
    if not models:
        print("Model endpoint responded, but no models were listed.")
        return 1

    print("Model endpoint is healthy.")
    for model in models:
        print(f"- {model}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
