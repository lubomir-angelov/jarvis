#!/usr/bin/env python3
"""Prepare markdown source documents for Context Engine.

The generated documents are read-only context sources. They are not an edit
allowlist. Edit scope is controlled separately by the Aider file arguments.
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path
from typing import Iterable


SKIP_DIR_PARTS = {
    ".agent",
    ".aider",
    ".git",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".venv",
    "__pycache__",
    "build",
    "dist",
    "htmlcov",
    "node_modules",
    "state",
}

SKIP_SUFFIXES = {
    ".7z",
    ".avif",
    ".bmp",
    ".db",
    ".gif",
    ".gz",
    ".ico",
    ".jpeg",
    ".jpg",
    ".lock",
    ".mp4",
    ".pdf",
    ".png",
    ".pyc",
    ".sqlite",
    ".tar",
    ".webp",
    ".xlsx",
    ".zip",
}

DEFAULT_MAX_BYTES = 256_000


def _language_for_path(path: Path) -> str:
    suffix = path.suffix.lower()
    mapping = {
        ".py": "python",
        ".md": "markdown",
        ".yml": "yaml",
        ".yaml": "yaml",
        ".json": "json",
        ".toml": "toml",
        ".sql": "sql",
        ".sh": "bash",
        ".txt": "text",
        ".js": "javascript",
        ".ts": "typescript",
        ".tsx": "tsx",
        ".jsx": "jsx",
        ".html": "html",
        ".css": "css",
        ".ini": "ini",
        ".cfg": "ini",
    }
    return mapping.get(suffix, "text")


def _git_tracked_files(repo_root: Path) -> list[str]:
    result = subprocess.run(
        ["git", "-C", str(repo_root), "ls-files"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def _should_skip(rel_path: str, src: Path, max_bytes: int) -> bool:
    path = Path(rel_path)

    if any(part in SKIP_DIR_PARTS for part in path.parts):
        return True

    if path.suffix.lower() in SKIP_SUFFIXES:
        return True

    if not src.exists() or not src.is_file():
        return True

    try:
        if src.stat().st_size > max_bytes:
            return True
    except OSError:
        return True

    return False


def _selected_files(repo_root: Path, files: list[str] | None, use_all: bool) -> list[str]:
    if use_all:
        return _git_tracked_files(repo_root)

    if not files:
        raise ValueError("Either --all or --files must be provided.")

    return files


def _write_context_doc(repo_root: Path, output_dir: Path, rel_path: str) -> None:
    src = (repo_root / rel_path).resolve()

    if repo_root != src and repo_root not in src.parents:
        raise ValueError(f"Refusing to index path outside repo: {rel_path}")

    text = src.read_text(encoding="utf-8", errors="replace")
    lang = _language_for_path(src)
    safe_name = rel_path.replace("/", "__")
    out_file = output_dir / f"{safe_name}.md"

    rendered = (
        f"# File: `{rel_path}`\n\n"
        f"## Relative path\n\n"
        f"`{rel_path}`\n\n"
        f"## Contents\n\n"
        f"```{lang}\n{text}\n```\n"
    )
    out_file.write_text(rendered, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--files", nargs="*")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES)
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve()

    output_dir.mkdir(parents=True, exist_ok=True)

    for old_file in output_dir.glob("*.md"):
        old_file.unlink()

    rel_paths = _selected_files(
        repo_root=repo_root,
        files=args.files,
        use_all=args.all,
    )

    indexed_count = 0
    skipped_count = 0

    for rel_path in rel_paths:
        src = (repo_root / rel_path).resolve()

        if _should_skip(rel_path, src, args.max_bytes):
            skipped_count += 1
            continue

        try:
            _write_context_doc(repo_root, output_dir, rel_path)
            indexed_count += 1
        except UnicodeDecodeError:
            skipped_count += 1

    print(f"Indexed files: {indexed_count}")
    print(f"Skipped files: {skipped_count}")
    print(f"Output dir: {output_dir}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())