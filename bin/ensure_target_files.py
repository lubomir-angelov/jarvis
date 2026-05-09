#!/usr/bin/env python3
"""Create agent tracking files inside the mounted target repo."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path


TARGET = Path("/workspace/target")
AGENT_DIR = TARGET / ".agent"
WORKLOG = AGENT_DIR / "WORKLOG.md"
TASKS = AGENT_DIR / "TASKS.md"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")


def ensure_file(path: Path, content: str) -> None:
    if not path.exists():
        path.write_text(content, encoding="utf-8")


def main() -> int:
    AGENT_DIR.mkdir(parents=True, exist_ok=True)
    ensure_file(
        WORKLOG,
        "# Agent Work Log\n\n"
        "This file records explicit task notes, assumptions, commands, outcomes, and validation.\n"
        "It is not a dump of private model scratchpad text.\n\n",
    )
    ensure_file(
        TASKS,
        "# Task Queue\n\n"
        f"Initialized: {utc_now()}\n",
    )
    print(str(WORKLOG))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
