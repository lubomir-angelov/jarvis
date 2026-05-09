#!/usr/bin/env python3
"""Print the currently configured target repo."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    return parser.parse_args()


def main() -> int:
    env_path = Path(parse_args().file)
    if not env_path.exists():
        print("No .env file found. Run 'make init' first.")
        return 1

    for line in env_path.read_text(encoding="utf-8").splitlines():
        if line.startswith("TARGET_REPO="):
            print(line.split("=", 1)[1])
            return 0

    print("TARGET_REPO is not set.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
