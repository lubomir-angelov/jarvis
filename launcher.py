#!/usr/bin/env python3

import argparse
import os
from pathlib import Path

from pydantic import SecretStr

from openhands.sdk import Conversation, LLM
from openhands.tools.preset.default import get_default_agent
from openhands.workspace import DockerWorkspace


DEFAULT_MODEL = "openai/qwen3.8-27b"
DEFAULT_BASE_URL = "http://local-llm:8000/v1"
DEFAULT_NETWORK = "local-agent-net"
DEFAULT_SERVER_IMAGE = "ghcr.io/openhands/agent-server:latest-python"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run an OpenHands agent inside an isolated Docker workspace."
    )

    parser.add_argument(
        "--project",
        required=True,
        help="Host path to the project directory.",
    )

    parser.add_argument(
        "--task",
        required=True,
        help="Task to give the agent.",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    project = Path(args.project).expanduser().resolve()

    if not project.exists():
        raise SystemExit(f"Project does not exist: {project}")

    if not project.is_dir():
        raise SystemExit(f"Project is not a directory: {project}")

    model = os.getenv("LLM_MODEL", DEFAULT_MODEL)
    base_url = os.getenv("LLM_BASE_URL", DEFAULT_BASE_URL)
    api_key = os.getenv("LLM_API_KEY", "local")

    docker_network = os.getenv(
        "AGENT_DOCKER_NETWORK",
        DEFAULT_NETWORK,
    )

    server_image = os.getenv(
        "OPENHANDS_SERVER_IMAGE",
        DEFAULT_SERVER_IMAGE,
    )

    print(f"Project : {project}")
    print(f"Model   : {model}")
    print(f"LLM URL : {base_url}")
    print(f"Network : {docker_network}")

    llm = LLM(
        usage_id="agent",
        model=model,
        base_url=base_url,
        api_key=SecretStr(api_key),
    )

    agent = get_default_agent(
        llm=llm,
        cli_mode=True,
    )

    task = f"""
{args.task}

Operating rules:

- Work only inside /workspace.
- Inspect the existing repository before making changes.
- Use terminal and file-editing tools as necessary.
- Keep changes scoped to the requested task.
- Run relevant tests, linters, type checks, or smoke tests before finishing.
- Do not modify files outside /workspace.
- Do not ask for confirmation for ordinary repository-local operations.
- Do not create commits unless the task explicitly asks for one.
- When finished, summarize:
  1. what you changed,
  2. what commands/tests you ran,
  3. any remaining issues or recommendations.
""".strip()

    with DockerWorkspace(
        server_image=server_image,
        network=docker_network,
        volumes=[
            f"{project}:/workspace",
        ],
    ) as workspace:

        conversation = Conversation(
            agent=agent,
            workspace=workspace,
            visualize=True,
        )

        try:
            conversation.send_message(task)
            conversation.run()
        finally:
            conversation.close()


if __name__ == "__main__":
    main()