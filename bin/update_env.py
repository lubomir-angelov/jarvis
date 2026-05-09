#!/usr/bin/env python3
"""Update or create a key in a simple .env file."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--value", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    env_path = Path(args.file)
    lines: list[str] = []
    if env_path.exists():
        lines = env_path.read_text(encoding="utf-8").splitlines()

    updated = False
    output: list[str] = []
    for line in lines:
        if line.startswith(f"{args.key}="):
            output.append(f"{args.key}={args.value}")
            updated = True
        else:
            output.append(line)

    if not updated:
        output.append(f"{args.key}={args.value}")

    env_path.write_text("\n".join(output).rstrip() + "\n", encoding="utf-8")
    print(f"Set {args.key} in {env_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
