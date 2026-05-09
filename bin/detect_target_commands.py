#!/usr/bin/env python3
"""Detect simple lint/test commands for a mounted target repo."""

from __future__ import annotations

from pathlib import Path
import json
import re

TARGET = Path('/workspace/target')


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding='utf-8')
    except Exception:
        return ''


def has_make_target(name: str) -> bool:
    makefile = TARGET / 'Makefile'
    if not makefile.exists():
        return False
    text = read_text(makefile)
    pattern = rf'(?m)^{re.escape(name)}\s*:'
    return re.search(pattern, text) is not None


def detect_lint_cmd() -> str | None:
    if has_make_target('lint'):
        return 'make lint'
    if (TARGET / 'ruff.toml').exists() or (TARGET / '.ruff.toml').exists():
        return 'python -m ruff check'

    pyproject = read_text(TARGET / 'pyproject.toml')
    if 'tool.ruff' in pyproject or re.search(r'(?m)^\s*ruff\b', pyproject):
        return 'python -m ruff check'
    return None


def detect_test_cmd() -> str | None:
    if has_make_target('test'):
        return 'make test'
    if (TARGET / 'pytest.ini').exists() or (TARGET / 'tests').exists():
        return 'python -m pytest -q'

    pyproject = read_text(TARGET / 'pyproject.toml')
    if 'tool.pytest.ini_options' in pyproject or 'pytest' in pyproject:
        return 'python -m pytest -q'
    return None


def main() -> int:
    payload = {
        'lint_cmd': detect_lint_cmd(),
        'test_cmd': detect_test_cmd(),
    }
    print(json.dumps(payload))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
