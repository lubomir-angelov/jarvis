#!/usr/bin/env python3
"""Ensure the target repo is safe for automated work."""

from __future__ import annotations

import subprocess
from pathlib import Path


TARGET = Path("/workspace/target")


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=TARGET,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def main() -> int:
    if not TARGET.exists():
        raise SystemExit("/workspace/target is not mounted")
    if not (TARGET / ".git").exists():
        raise SystemExit("Mounted target is not a git repo")

    branch = git("branch", "--show-current")
    if branch != "feature/agent_work":
        raise SystemExit(f"Refusing to run: target repo is on branch '{branch}', not 'main'")

    status = git("status", "--short")
    if status:
        raise SystemExit("Refusing to run: target repo has uncommitted changes")

    print("Target repo passed preflight.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
