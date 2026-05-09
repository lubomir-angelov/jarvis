Here’s a clean summary you can drop into the README.

## Debugging notes

### 1. Missing `.env.example`

`make init` failed with:

```text
cp: cannot stat '.env.example': No such file or directory
```

Cause:

* the starter repo was copied/extracted without hidden files, or `make init` was run from the wrong folder

Fix:

* make sure `.env.example` exists in the repo root
* create `.env` from it with `make init`

Example `.env.example`:

```env
OPENAI_API_KEY=token-local-dev
LLM_PORT=8001
MODEL_ALIAS=qwen3.6-27b
MODEL_HF_REPO=unsloth/Qwen3.6-27B-GGUF
MODEL_HF_QUANT=UD-Q4_K_XL
LLM_CTX_SIZE=4096
LLM_TEMP=0.6
LLM_TOP_P=0.95
LLM_TOP_K=20
LLM_MIN_P=0.0
TARGET_REPO=/absolute/path/to/target/repo
```

---

### 2. `llm` container started but `make health` failed

Observed:

* container was `Up`
* `make health` returned connection refused

Cause:

* the model service was not actually the problem
* Docker healthcheck and the custom health check were probing the wrong port / using different expansion contexts

---

### 3. `llm` container marked `unhealthy`

Observed:

* Docker showed the `llm` container as `unhealthy`

Root cause:

* Docker healthcheck was probing `localhost:8080`
* the actual `llama-server` port was `8001`

Fix:

* update the `llm` service healthcheck in `docker-compose.yml` to probe the real port

Example:

```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8001/health || exit 1"]
  interval: 30s
  timeout: 10s
  retries: 60
  start_period: 10m
```

Then recreate the container:

```bash
docker compose down --remove-orphans
docker compose up -d --force-recreate
```

Verification:

```bash
docker ps
docker inspect jarvis-llm-1 --format '{{json .State.Health}}'
```

---

### 4. Manual `llama-server` launch failed with `stoi`

Observed:

```text
error while handling argument "--port": stoi
```

Cause:

* `${LLM_PORT}` and similar variables were not present inside the interactive container shell
* Compose substituted variables for container startup, but they were not exported in the shell session used for manual debugging

Fix:

* run `llama-server` with literal values, or export the env vars manually before launching

Example manual launch:

```bash
/app/llama-server \
  -hf "unsloth/Qwen3.6-27B-GGUF:UD-Q4_K_XL" \
  --alias "qwen3.6-27b" \
  --host 0.0.0.0 \
  --port 8001 \
  --ctx-size 4096 \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.0 \
  --reasoning off
```

---

### 5. Manual `llama-server` launch failed with missing shared library

Observed:

```text
/app/llama-server: error while loading shared libraries: libllama-common.so.0
```

Cause:

* `LD_LIBRARY_PATH` was not set correctly in the manual debug shell

Fix:

* set `LD_LIBRARY_PATH` to include `/app`

Example:

```bash
export LD_LIBRARY_PATH=/app:/usr/local/lib:/usr/lib:${LD_LIBRARY_PATH}
```

Durable fix in `docker-compose.yml`:

```yaml
environment:
  LD_LIBRARY_PATH: /app:/usr/local/lib:/usr/lib
```

---

### 6. `--reasoning off` passed incorrectly

Observed:

```text
error: invalid argument: --reasoning off
```

Cause:

* Compose command passed `"--reasoning off"` as a single argument

Fix:

* pass it as two separate arguments

Correct form:

```yaml
- "--reasoning"
- "off"
```

---

### 7. Large context size suspicion

Initially suspected:

* `Qwen3.6-27B` might be failing because of context size

Finding:

* manual testing inside the container showed the model could run even with larger context sizes
* the real blocker was the healthcheck and startup wiring, not the model itself

Practical recommendation:

* start with a smaller context like `4096` or `8192` for agent workflows
* increase only after the serving path is stable

---

### 8. `make health` still failed after container became healthy

Observed:

* Docker showed `jarvis-llm-1` as `healthy`
* `make health` still returned connection refused

Cause:

* the Makefile target used:

```make
http://llm:$${LLM_PORT}/v1
```

* but `LLM_PORT` was being expanded in the wrong shell context and ended up empty

Fix:

* run the check through `bash -lc` inside the agent container, or hardcode the port

Recommended Makefile target:

```make
health:
	@$(COMPOSE) exec agent bash -lc 'python /workspace/control/bin/llm_healthcheck.py --base-url "http://llm:$${LLM_PORT}/v1"'
```

Also ensure the `agent` service gets the required env vars from `.env`.

---

### 9. `make task` failed on Git preflight

Observed:

* `preflight_target.py` failed on `git branch --show-current` with exit code `128`

Cause:

* Git inside the container initially did not trust the mounted repo path, or repo checks were stricter inside the container than on the host

Fix:

* mark the mounted repo as safe inside the agent container

Command:

```bash
docker compose exec agent git config --global --add safe.directory /workspace/target
```

Verification:

```bash
docker compose exec agent git -C /workspace/target status
docker compose exec agent git -C /workspace/target branch --show-current
```

Durable fix:

* add this to the agent image build or container startup

---

### 10. Branch guard blocked execution

Observed:

* target repo was on `feature/agent_work`
* preflight logic expected `main`

Cause:

* the control repo was intentionally enforcing a single allowed branch

Fix:

* update `bin/preflight_target.py` to allow the chosen branch
* better: make it configurable through `.env`

Recommended approach:

```env
TARGET_BRANCH=feature/agent_work
```

and in `preflight_target.py`:

```python
allowed_branch = os.getenv("TARGET_BRANCH", "main")
if branch != allowed_branch:
    raise SystemExit(...)
```

Also update any prompt/rules file that says “work only on main”.

---

## Useful debug commands

Check service status:

```bash
docker compose ps
docker ps
```

Inspect `llm` logs:

```bash
docker compose logs -f --tail=200 llm
```

Inspect actual healthcheck failures:

```bash
docker inspect jarvis-llm-1 --format '{{range .State.Health.Log}}{{println .ExitCode .Output}}{{end}}'
```

Open an interactive `llm` shell:

```bash
docker compose run --rm --service-ports --entrypoint bash llm
```

Check target repo from inside agent container:

```bash
docker compose exec agent git -C /workspace/target status
docker compose exec agent git -C /workspace/target branch --show-current
```

Check resolved Compose config:

```bash
docker compose --env-file .env -f docker-compose.yml config
```

---

## Final state after debugging

Working points:

* `llm` container starts correctly
* Docker healthcheck points to the correct port
* `make health` needs to run with env expansion inside the agent container
* manual `llama-server` debugging works when using literal values and proper `LD_LIBRARY_PATH`
* mounted target repo is accessible from the agent container
* branch restrictions must match the intended workflow branch

If you want, I can turn this into a polished `README.md` section with headings like “Troubleshooting”, “Common failures”, and “Known-good configuration”.
