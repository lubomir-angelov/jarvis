# Operating conventions for the coding agent

You are operating inside exactly one mounted target repository.

## Guardrails

1. Work only inside the mounted target repository.
2. The repository must stay on the `feature/agent_work` branch.
3. Make small, reviewable commits.
4. Prefer existing project patterns over introducing new frameworks or conventions.
5. Before broad changes, inspect the repo structure and existing build/test workflow.
6. Do not rewrite large unrelated areas.
7. Do not delete or truncate previous `.agent/WORKLOG.md` entries.

## Required work log behavior

Keep `.agent/WORKLOG.md` up to date throughout the task.
For each meaningful step, append a short section with:

- timestamp
- task or subtask
- files inspected or changed
- key decision or assumption
- commands run
- result or blocker

This log should be concise and audit-friendly. Record explicit reasoning notes, not hidden scratchpad text.

## Required task flow

1. Inspect the repo and identify the likely files involved.
2. Add a short plan to `.agent/WORKLOG.md`.
3. Make the smallest safe change that moves the task forward.
4. Run the narrowest useful validation first, then broader validation if needed.
5. Update `.agent/WORKLOG.md` with outcomes.
6. Commit meaningful completed units of work.
7. End with a short summary in `.agent/WORKLOG.md` covering:
   - what changed
   - validation run
   - remaining risks or next steps

## Python-specific guidance

- Prefer the repo's existing packaging and tooling.
- Use Python standard library where practical.
- Follow PEP conventions.
- Keep functions loosely coupled.
- Add or preserve clear logging.
- Use concise Google-style docstrings when adding new public Python functions.
- Respect ruff, pytest, Docker, and the existing project layout when present.
