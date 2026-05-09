# Aider Agent Control Repo

This repo runs two services:

- `llm`: a local `llama-server` serving Unsloth `Qwen3.5-27B` behind an OpenAI-compatible API.
- `agent`: an Aider container that mounts **one target repo** and works only inside that repo.

## Fast path

```bash
make init
make set-target TARGET_REPO=/absolute/path/to/your/webapp
make build
make up
make health
make task TASK="Read the repo, create a short plan in .agent/WORKLOG.md, then implement task X safely."
```

## Reuse against another repo later

```bash
make set-target TARGET_REPO=/absolute/path/to/another/repo
make up
make task TASK="Implement task Y"
```

## Notes

- The agent container only sees the bound target repo and this control repo.
- The target repo must already be a git repo and must be on `main`.
- The task runner creates `.agent/WORKLOG.md` inside the target repo and asks Aider to keep it updated.
- Use `FILES="path1 path2"` to hint which files are likely relevant.
- The agent uses Aider auto-commits, auto-lint, and auto-test if the target repo exposes working lint/test commands.

## Sample task run
```bash
make task \
  TASK="Inspect how fragment totals are calculated and change fragment counting to use f_count instead of row count. Update .agent/WORKLOG.md, run narrow validation, and commit." \
  FILES=".agent/TASKS.md \
  .agent/WORKLOG.md \
  gkrp_data_portal/src/gkrp_data_portal/ui/repository/analytics_repo.py \
  gkrp_data_portal/src/gkrp_data_portal/ui/pages/analytics_table.py \
  gkrp_data_portal/src/gkrp_data_portal/ui/pages/analytics_chart.py"
```



```bash
make task \
  TASK="Inspect sqlalchemy.exc.ProgrammingError: (psycopg.errors.UndefinedColumn) column x.fragmentid does not exist LINE 7: ) x JOIN tblfragments f ON x.fragmentid = f.fragmentid HINT:  Perhaps you meant to reference the column f.fragmentid. Apply a fix and commit all changes." \
  FILES=".agent/TASKS.md \
  .agent/WORKLOG.md \
  gkrp_data_portal/src/gkrp_data_portal/ui/repository/analytics_repo.py \
  gkrp_data_portal/src/gkrp_data_portal/ui/pages/analytics_table.py \
  gkrp_data_portal/src/gkrp_data_portal/ui/pages/analytics_chart.py"
```

```bash
make task TASK="On the analytics_plot page, update the site, sector, and square filter fields so they support multi-value search by splitting the user input on these separators: comma (,), semicolon (;), and slash (/). The current behavior does exact string matching only, case-insensitive. Preserve case-insensitive matching, but when multiple values are provided, treat them as OR criteria within the same field. Trim whitespace around each split token, ignore empty tokens, and do not change unrelated filters or behavior. Update .agent/WORKLOG.md, run the narrowest useful validation, and commit." FILES="gkrp_data_portal/src/gkrp_data_portal/ui/repository/analytics_repo.py gkrp_data_portal/src/gkrp_data_portal/ui/pages/analytics_chart.py. Commit all files."
```