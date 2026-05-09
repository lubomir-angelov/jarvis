#!/usr/bin/env bash
set -euo pipefail

cd /workspace/target
python /workspace/control/bin/preflight_target.py
python /workspace/control/bin/ensure_target_files.py >/tmp/worklog_path.txt
WORKLOG_PATH="$(cat /tmp/worklog_path.txt)"

TASK_CONTENT=""
if [[ -n "${TASK_FILE:-}" ]]; then
  TASK_CONTENT="$(cat "${TASK_FILE}")"
elif [[ -n "${TASK:-}" ]]; then
  TASK_CONTENT="${TASK}"
else
  echo "No TASK or TASK_FILE was provided."
  exit 1
fi

TASK_CONTENT="${TASK_CONTENT}" python - <<'PY'
from __future__ import annotations
from datetime import datetime, timezone
from pathlib import Path
import os

worklog = Path("/workspace/target/.agent/WORKLOG.md")
tasks = Path("/workspace/target/.agent/TASKS.md")
timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
task_content = os.environ["TASK_CONTENT"]

tasks.open("a", encoding="utf-8").write(f"\n## {timestamp}\n\n{task_content.strip()}\n")
worklog.open("a", encoding="utf-8").write(
    f"\n## {timestamp} - task received\n\n"
    f"### Requested task\n{task_content.strip()}\n\n"
    "### Initial status\n- preflight: passed\n- branch: main\n- working tree: clean\n"
)
PY

read -r -d '' TASK_PROMPT <<'EOF2' || true
Read `/workspace/control/prompts/OPERATING_CONVENTIONS.md` and follow it strictly.

Task:
{{TASK_CONTENT}}

Requirements:
- operate only inside the mounted target repo
- inspect the repo before making changes
- keep `.agent/WORKLOG.md` updated throughout the task
- make small, reviewable commits on `main`
- run the narrowest useful validation first, then broader validation when justified
- finish by updating `.agent/WORKLOG.md` with a concise summary and residual risks
EOF2

TASK_PROMPT="${TASK_PROMPT//'{{TASK_CONTENT}}'/${TASK_CONTENT}}"
printf '%s\n' "${TASK_PROMPT}" > /tmp/aider_task_prompt.txt

FILE_ARGS=()
if [[ -n "${FILES:-}" ]]; then
  # shellcheck disable=SC2206
  SELECTED_FILES=( ${FILES} )
  for file in "${SELECTED_FILES[@]}"; do
    FILE_ARGS+=("$file")
  done
fi

DETECTED_JSON="$(python /workspace/control/bin/detect_target_commands.py)"
mapfile -t DETECTED_LINES < <(DETECTED_JSON="${DETECTED_JSON}" python - <<'PY'
from __future__ import annotations
import json
import os
payload = json.loads(os.environ["DETECTED_JSON"])
for key in ("lint_cmd", "test_cmd"):
    value = payload.get(key)
    if value:
        print(f"{key}={value}")
PY
)

AIDER_EXTRA_ARGS=()
for line in "${DETECTED_LINES[@]}"; do
  key="${line%%=*}"
  value="${line#*=}"
  if [[ "${key}" == "lint_cmd" ]]; then
    AIDER_EXTRA_ARGS+=(--lint-cmd "python:${value}")
  elif [[ "${key}" == "test_cmd" ]]; then
    AIDER_EXTRA_ARGS+=(--test-cmd "${value}")
  fi
done

exec aider \
  --config /workspace/control/.aider.conf.yml \
  --model "openai/${MODEL_ALIAS}" \
  --openai-api-base "http://llm:${LLM_PORT}/v1" \
  --openai-api-key "${OPENAI_API_KEY}" \
  --no-restore-chat-history \
  --chat-history-file /tmp/.aider.chat.history.md \
  --input-history-file /tmp/.aider.input.history \
  --read /workspace/control/prompts/OPERATING_CONVENTIONS.md \
  --read .agent/WORKLOG.md \
  --message-file /tmp/aider_task_prompt.txt \
  "${AIDER_EXTRA_ARGS[@]}" \
  "${FILE_ARGS[@]}"
