#!/usr/bin/env python3
"""Validate and print basic details for a target repo."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    return parser.parse_args()


def main() -> int:
    repo = Path(parse_args().repo).expanduser().resolve()
    if not repo.exists():
        raise SystemExit(f"Target repo does not exist: {repo}")
    if not (repo / ".git").exists():
        raise SystemExit(f"Target path is not a git repo: {repo}")

    branch = git(repo, "branch", "--show-current")
    status = git(repo, "status", "--short")
    print(f"Target repo: {repo}")
    print(f"Current branch: {branch}")
    print("Working tree: clean" if not status else "Working tree: dirty")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
