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

CURRENT_BRANCH="$(git branch --show-current)"
WORKING_TREE_STATE="clean"
if [[ -n "$(git status --porcelain)" ]]; then
  WORKING_TREE_STATE="dirty"
fi

TASK_CONTENT="${TASK_CONTENT}" CURRENT_BRANCH="${CURRENT_BRANCH}" WORKING_TREE_STATE="${WORKING_TREE_STATE}" python - <<'PY'
from __future__ import annotations
from datetime import datetime, timezone
from pathlib import Path
import os

worklog = Path("/workspace/target/.agent/WORKLOG.md")
tasks = Path("/workspace/target/.agent/TASKS.md")
timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
task_content = os.environ["TASK_CONTENT"]
branch = os.environ["CURRENT_BRANCH"]
working_tree_state = os.environ["WORKING_TREE_STATE"]

tasks.open("a", encoding="utf-8").write(f"\n## {timestamp}\n\n{task_content.strip()}\n")
worklog.open("a", encoding="utf-8").write(
    f"\n## {timestamp} - task received\n\n"
    f"### Requested task\n{task_content.strip()}\n\n"
    "### Initial status\n"
    f"- preflight: passed\n"
    f"- branch: {branch}\n"
    f"- working tree: {working_tree_state}\n"
)
PY

FILE_ARGS=()
if [[ -n "${FILES:-}" ]]; then
  # shellcheck disable=SC2206
  SELECTED_FILES=( ${FILES} )
  for file in "${SELECTED_FILES[@]}"; do
    FILE_ARGS+=("$file")
  done
fi


CONTEXT_BLOCK=""
if [[ "${CONTEXT_ENABLE:-1}" == "1" ]]; then
  CONTEXT_SRC_DIR="/workspace/state/context-src/repo"
  CONTEXT_CACHE_DIR="/workspace/state/context-cache/repo"

  mkdir -p /workspace/state/context-src /workspace/state/context-cache

  python /workspace/control/bin/context_prepare_sources.py \
    --repo-root /workspace/target \
    --output-dir "${CONTEXT_SRC_DIR}" \
    --all \
    --max-bytes "${CONTEXT_MAX_FILE_BYTES:-256000}" \
    >/tmp/context_prepare.log

  context build \
    --sources "${CONTEXT_SRC_DIR}" \
    --cache "${CONTEXT_CACHE_DIR}" \
    >/tmp/context_build.log

  context resolve \
    --cache "${CONTEXT_CACHE_DIR}" \
    --query "${TASK_CONTENT}" \
    --budget "${CONTEXT_BUDGET:-2200}" \
    >/tmp/context_resolve.json

  CONTEXT_BLOCK="$(python - <<'PY'
from __future__ import annotations

import json
from pathlib import Path

payload = json.loads(Path("/tmp/context_resolve.json").read_text(encoding="utf-8"))
rendered = json.dumps(payload, ensure_ascii=False, indent=2)

print("Whole-repo Context Engine selection for this task.")
print("This context is read-only guidance. It does not grant edit permission.")
print("```json")
print(rendered)
print("```")
PY
)"
fi

EDIT_SCOPE_BLOCK=""
if [[ "${#FILE_ARGS[@]}" -gt 0 ]]; then
  EDIT_SCOPE_BLOCK="Explicit edit allowlist is active.

The only files that may be edited are:
$(printf -- '- %s\n' "${FILE_ARGS[@]}")
- .agent/WORKLOG.md

You may reason over the whole repository context, but do not edit files outside this allowlist.
If the task requires changes outside the allowlist, record that in .agent/WORKLOG.md and stop or make only the safe partial change."
else
  EDIT_SCOPE_BLOCK="No explicit edit allowlist was provided.

You may use the whole repository context to identify the minimum necessary files to change.
Before editing each non-worklog file, record in .agent/WORKLOG.md why that file is necessary for the task."
fi

read -r -d '' TASK_PROMPT <<'EOF2' || true
Read `/workspace/control/prompts/OPERATING_CONVENTIONS.md` and follow it strictly.

Task:
{{TASK_CONTENT}}

Edit scope:
{{EDIT_SCOPE_BLOCK}}

Repository context:
{{CONTEXT_BLOCK}}

Requirements:
- operate only inside the mounted target repo
- use Context Engine output as read-only repo understanding
- do not treat Context Engine output as edit permission
- if an explicit edit allowlist is provided, edit only those files and `.agent/WORKLOG.md`
- inspect the relevant implementation before making changes
- keep `.agent/WORKLOG.md` updated throughout the task
- make small, reviewable commits on the configured target branch
- run the narrowest useful validation first, then broader validation when justified
- finish by updating `.agent/WORKLOG.md` with a concise summary and residual risks
EOF2

TASK_PROMPT="${TASK_PROMPT//'{{TASK_CONTENT}}'/${TASK_CONTENT}}"
TASK_PROMPT="${TASK_PROMPT//'{{EDIT_SCOPE_BLOCK}}'/${EDIT_SCOPE_BLOCK}}"
TASK_PROMPT="${TASK_PROMPT//'{{CONTEXT_BLOCK}}'/${CONTEXT_BLOCK}}"
printf '%s\n' "${TASK_PROMPT}" > /tmp/aider_task_prompt.txt

TASK_PROMPT="${TASK_PROMPT//'{{TASK_CONTENT}}'/${TASK_CONTENT}}"
TASK_PROMPT="${TASK_PROMPT//'{{CONTEXT_BLOCK}}'/${CONTEXT_BLOCK}}"
printf '%s\n' "${TASK_PROMPT}" > /tmp/aider_task_prompt.txt

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

AIDER_FILES=()

# Keep the worklog editable in every task.
AIDER_FILES+=(".agent/WORKLOG.md")

# If FILES was provided, these are the only additional editable files.
if [[ "${#FILE_ARGS[@]}" -gt 0 ]]; then
  for file in "${FILE_ARGS[@]}"; do
    AIDER_FILES+=("$file")
  done
fi

exec aider \
  --config /workspace/control/.aider.conf.yml \
  --model "openai/${MODEL_ALIAS}" \
  --openai-api-base "http://llm:${LLM_PORT}/v1" \
  --openai-api-key "${OPENAI_API_KEY}" \
  --no-restore-chat-history \
  --chat-history-file /tmp/.aider.chat.history.md \
  --input-history-file /tmp/.aider.input.history \
  --read /workspace/control/prompts/OPERATING_CONVENTIONS.md \
  --message-file /tmp/aider_task_prompt.txt \
  "${AIDER_EXTRA_ARGS[@]}" \
  "${AIDER_FILES[@]}"